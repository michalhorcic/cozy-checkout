defmodule CozyCheckout.AbraSyncTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.{Abra, Sales}
  alias CozyCheckout.Abra.Client
  alias CozyCheckout.Workers.AbraSyncWorker

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  test "a paid order is sent once and subsequent sync uses the saved document ID" do
    order = paid_order()

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [invoice] = Jason.decode!(body)["winstrom"]["faktura-vydana"]
      assert invoice["hotovostni-uhrada"]["castka"] == "100.00"
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    assert {:ok, "42"} = Abra.sync_order(order.id)
    assert {:ok, "42"} = Abra.sync_order(order.id)
    updated = Sales.get_order!(order.id)
    assert updated.abra_sync_status == "synced"
    assert updated.abra_document_id == "42"
    assert updated.abra_synced_at != nil
  end

  test "HTTP failure does not mark an order synced and a retry can succeed" do
    order = paid_order()
    Req.Test.expect(Client, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)
    assert {:error, "HTTP 503"} = Abra.sync_order(order.id)
    assert Sales.get_order!(order.id).abra_document_id == nil

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    assert {:ok, "42"} = Abra.sync_order(order.id)
  end

  for status <- ["open", "partially_paid", "cancelled"] do
    @tag :known_bug
    test "#{status} orders are rejected before contacting ABRA" do
      order = order_fixture(%{"status" => unquote(status)})
      item_fixture(order)

      Req.Test.stub(Client, fn _conn ->
        flunk("Unpaid or cancelled orders must not be sent to ABRA")
      end)

      assert {:error, _} = Abra.sync_order(order.id)
    end
  end

  @tag :known_bug
  test "mismatched line total is rejected before contacting ABRA" do
    order = paid_order()
    order |> Ecto.Changeset.change(total_amount: Decimal.new("99")) |> Repo.update!()

    Req.Test.stub(Client, fn _conn ->
      flunk("Mismatched amounts must be rejected before contacting ABRA")
    end)

    assert {:error, _} = Abra.sync_order(order.id)
  end

  @tag :known_bug
  test "lost success response and retry do not create two remote invoices" do
    order = paid_order()
    {:ok, remote} = Agent.start_link(fn -> %{documents: %{}, sequence: 0} end)
    on_exit(fn -> if Process.alive?(remote), do: Agent.stop(remote) end)

    Req.Test.stub(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [invoice] = Jason.decode!(body)["winstrom"]["faktura-vydana"]
      # Simulate ABRA accepting an external ID as an idempotent invoice identity.
      id =
        Agent.get_and_update(remote, fn state ->
          identity = invoice["id"] || "new-#{state.sequence + 1}"
          id = Map.get(state.documents, identity, state.sequence + 1)

          {id,
           %{
             state
             | documents: Map.put(state.documents, identity, id),
               sequence: state.sequence + 1
           }}
        end)

      if Agent.get(remote, & &1.sequence) == 1 do
        Req.Test.transport_error(conn, :timeout)
      else
        Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => id}]}})
      end
    end)

    assert {:error, _} = Abra.sync_order(order.id)
    assert {:ok, _} = Abra.sync_order(order.id)
    assert Agent.get(remote, &map_size(&1.documents)) == 1
  end

  test "worker reports a successful sync and counts the attempt" do
    order = paid_order()
    Phoenix.PubSub.subscribe(CozyCheckout.PubSub, "abra_sync")

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    assert :ok =
             AbraSyncWorker.perform(%Oban.Job{
               args: %{"order_id" => order.id},
               attempt: 1,
               max_attempts: 5
             })

    assert_receive {:abra_sync_updated, id}
    assert id == order.id
    assert Sales.get_order!(order.id).abra_sync_attempts == 1
  end

  test "worker retries a temporary failure and marks the final attempt failed" do
    order = paid_order()
    Phoenix.PubSub.subscribe(CozyCheckout.PubSub, "abra_sync")
    Req.Test.expect(Client, 2, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)

    assert {:error, "HTTP 503"} =
             AbraSyncWorker.perform(%Oban.Job{
               args: %{"order_id" => order.id},
               attempt: 1,
               max_attempts: 5
             })

    assert Sales.get_order!(order.id).abra_sync_status != "failed"

    assert {:cancel, "HTTP 503"} =
             AbraSyncWorker.perform(%Oban.Job{
               args: %{"order_id" => order.id},
               attempt: 5,
               max_attempts: 5
             })

    assert_receive {:abra_sync_updated, id}
    assert id == order.id
    updated = Sales.get_order!(order.id)
    assert updated.abra_sync_status == "failed"
    assert updated.abra_sync_error == "HTTP 503"
    assert updated.abra_sync_attempts == 2
  end

  defp paid_order do
    order = order_fixture()
    item_fixture(order)
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    Sales.get_order!(order.id)
  end
end
