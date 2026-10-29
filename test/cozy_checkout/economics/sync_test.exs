defmodule CozyCheckout.Economics.SyncTest do
  use CozyCheckout.DataCase, async: false
  import CozyCheckout.EconomicsFixtures
  alias CozyCheckout.{Economics, Repo}

  alias CozyCheckout.Economics.{
    AbraClient,
    Config,
    Sync,
    Snapshot,
    Confirmation,
    ImportRun,
    SyncWorker
  }

  setup do
    previous = Application.get_env(:cozy_checkout, :economics)
    options = Req.default_options()

    Application.put_env(:cozy_checkout, :economics,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "company-a",
      username: "reader",
      password: "secret"
    )

    Req.default_options(plug: {Req.Test, AbraClient})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :economics, previous),
        else: Application.delete_env(:cozy_checkout, :economics)

      Req.default_options(options)
    end)

    stub()
    :ok
  end

  defp stub(transform \\ fn _, rows -> rows end) do
    Req.Test.stub(AbraClient, fn conn ->
      assert conn.method == "GET"
      path = URI.decode(conn.request_path)

      {key, rows} =
        cond do
          String.ends_with?(path, "ucetni-obdobi.json") ->
            {"ucetni-obdobi",
             [%{"kod" => "FY-TEST", "platiOdData" => "2026-07-01", "platiDoData" => "2026-07-31"}]}

          String.ends_with?(path, "ucet.json") ->
            {"ucet", catalog()}

          String.contains?(path, "pohyb-na-uctech") ->
            {"pohyb-na-uctech",
             if(Plug.Conn.fetch_query_params(conn).query_params["postingState"] == "unposted",
               do: [],
               else: posted()
             )}

          String.ends_with?(path, "obratova-predvaha.json") ->
            {"obratova-predvaha", trial()}

          String.ends_with?(path, "saldo-k-datu.json") ->
            {"saldo-k-datu",
             [
               open_item(),
               open_item(%{
                 "idDokl" => "101",
                 "sumCelkem" => "-10",
                 "sumCelkemAkt" => "-10",
                 "juhSumDat" => "0"
               })
             ]}
        end

      Req.Test.json(conn, %{"winstrom" => %{key => transform.(key, rows)}})
    end)
  end

  test "publishes once, keeps identical version, and exposes local reports with separate credits" do
    assert {:ok, first} = Sync.run("FY-TEST")
    assert {:ok, second} = Sync.run("FY-TEST")
    assert first.id == second.id
    assert Repo.aggregate(Snapshot, :count) == 1
    assert {:ok, %{report: report}} = Economics.overview()
    assert Decimal.equal?(report.open_totals["receivable"]["total"], "75")
    assert Decimal.equal?(report.open_totals["receivable"]["credits"], "-10")
    refute hd(report.confirmations).confirmed
    assert {:ok, detail} = Economics.account_detail(%{}, "602001")
    assert length(detail.rows) == 1
    assert {:ok, %{report: %{error: :invalid_range}}} = Economics.overview(%{"from" => "2025-06"})
  end

  test "failed or incomplete import preserves the last snapshot and records a safe error" do
    assert {:ok, snapshot} = Sync.run("FY-TEST")
    stub(fn key, rows -> if key == "pohyb-na-uctech", do: [], else: rows end)
    assert {:error, :trial_balance_mismatch} = Sync.run("FY-TEST")
    assert Repo.get!(Snapshot, snapshot.id).active
    assert Repo.aggregate(Snapshot, :count) == 1
    assert {:ok, %{latest_run: run}} = Economics.overview()
    assert run.state == "failed" and run.error == "trial_balance_mismatch"
  end

  test "confirmations are local, require evidence and expire when accounting data changes" do
    assert {:ok, snapshot} = Sync.run("FY-TEST")

    assert {:error, :invalid_confirmation} =
             Economics.confirm_month(snapshot.id, "2026-07-01", "")

    assert {:ok, _} =
             Economics.confirm_month(
               snapshot.id,
               "2026-07-01",
               "Odsouhlaseno s účetní podle předvahy."
             )

    assert {:ok, %{report: %{confirmations: [%{confirmed: true}]}}} = Economics.overview()
    stub(fn key, rows -> if key == "saldo-k-datu", do: [], else: rows end)
    assert {:ok, updated} = Sync.run("FY-TEST")
    refute updated.id == snapshot.id
    assert {:ok, %{report: %{confirmations: [%{confirmed: false}]}}} = Economics.overview()

    assert {:error, :snapshot_changed} =
             Economics.confirm_month(
               snapshot.id,
               "2026-07-01",
               "Odsouhlaseno s účetní podle předvahy."
             )

    assert Repo.aggregate(Confirmation, :count) == 1
  end

  test "changing source isolates all data and disabled jobs make no requests" do
    assert {:ok, _} = Sync.run("FY-TEST")

    Application.put_env(
      :cozy_checkout,
      :economics,
      Keyword.put(Config.get(), :company_id, "company-b")
    )

    assert {:error, :not_imported} = Economics.overview()
    Application.put_env(:cozy_checkout, :economics, enabled: false)
    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    assert {:error, :disabled} = Economics.request_sync()
    assert Repo.aggregate(ImportRun, :count) == 1
  end
end
