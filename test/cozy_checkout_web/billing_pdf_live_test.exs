defmodule CozyCheckoutWeb.BillingPdfLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.BillingFixtures
  use Oban.Testing, repo: CozyCheckout.Repo
  alias CozyCheckout.Repo
  alias CozyCheckout.Abra.{AccommodationExport, PdfAttachments, PdfTransfer}
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    old_pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    old_pdf = Application.get_env(:cozy_checkout, :abra_pdf)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))
    Application.put_env(:cozy_checkout, :abra_pdf, enabled: true)

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :admin_pin_hash, old_pin)
      Application.put_env(:cozy_checkout, :abra_pdf, old_pdf)
    end)

    %{booking: booking} = billing_fixture()
    doc = issue_without_abra!(booking, "advance", %{"amount" => "1000"})

    export =
      Repo.insert!(%AccommodationExport{
        document_id: doc.id,
        base_url: "https://accounting.test",
        company_id: "test",
        external_id: "ext:test:#{doc.id}",
        payload: %{},
        state: "synced",
        remote_id: "42",
        synced_at: DateTime.utc_now(:second)
      })

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    %{conn: conn, doc: doc, export: export}
  end

  test "admin can queue PDF separately from the successful accounting export", ctx do
    {:ok, view, _} = live(ctx.conn, "/admin/billing/documents/#{ctx.doc.id}")
    assert has_element?(view, "#accommodation-abra-pdf-state", "PDF zatím nebylo zařazeno")
    view |> element("#accommodation-abra-pdf-send") |> render_click()
    transfer = PdfAttachments.status(ctx.doc.id)
    assert transfer.state == "queued"
    assert_enqueued(worker: CozyCheckout.Workers.AbraPdfWorker, args: %{transfer_id: transfer.id})
    assert has_element?(view, "#accommodation-abra-pdf-state", "PDF čeká na odeslání")
    refute has_element?(view, "#accommodation-abra-pdf-send")
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "disabled PDF delivery is visible and cannot be bypassed by a forged event", ctx do
    Application.put_env(:cozy_checkout, :abra_pdf, enabled: false)
    {:ok, view, _} = live(ctx.conn, "/admin/billing/documents/#{ctx.doc.id}")
    assert has_element?(view, "#accommodation-abra-pdf-disabled", "vypnuté")
    refute has_element?(view, "#accommodation-abra-pdf-send")
    render_click(view, "abra-pdf-send")
    assert PdfAttachments.status(ctx.doc.id) == nil
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "PDF waits for accounting synchronization and cannot queue before it succeeds", ctx do
    ctx.export |> Ecto.Changeset.change(state: "queued") |> Repo.update!()
    {:ok, view, _} = live(ctx.conn, "/admin/billing/documents/#{ctx.doc.id}")
    assert has_element?(view, "#accommodation-abra-pdf-waiting", "po úspěšném exportu")
    refute has_element?(view, "#accommodation-abra-pdf-send")
    render_click(view, "abra-pdf-send")
    assert PdfAttachments.status(ctx.doc.id) == nil
  end

  test "failed PDF shows its error and can be retried without re-exporting the invoice", ctx do
    transfer =
      Repo.insert!(%PdfTransfer{
        export_id: ctx.export.id,
        state: "failed",
        error: "ABRA PDF: HTTP 403"
      })

    {:ok, view, _} = live(ctx.conn, "/admin/billing/documents/#{ctx.doc.id}")
    assert has_element?(view, "#accommodation-abra-pdf-error", "HTTP 403")
    assert has_element?(view, "#accommodation-abra-pdf-send", "Znovu odeslat")
    view |> element("#accommodation-abra-pdf-send") |> render_click()
    assert PdfAttachments.status(ctx.doc.id).id == transfer.id
    assert PdfAttachments.status(ctx.doc.id).state == "queued"
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "refresh and automatic polling show the latest PDF result", ctx do
    transfer = Repo.insert!(%PdfTransfer{export_id: ctx.export.id, state: "queued"})
    {:ok, view, _} = live(ctx.conn, "/admin/billing/documents/#{ctx.doc.id}")

    transfer
    |> Ecto.Changeset.change(state: "uploaded", uploaded_at: DateTime.utc_now(:second))
    |> Repo.update!()

    send(view.pid, :abra_tick)
    assert has_element?(view, "#accommodation-abra-pdf-state", "přeneseno a ověřeno")
    refute has_element?(view, "#accommodation-abra-pdf-send")
    view |> element("#accommodation-abra-pdf-refresh") |> render_click()
    assert has_element?(view, "#accommodation-abra-pdf-state", "přeneseno a ověřeno")
  end

  test "final invoice detail offers the same action and requires admin authentication", ctx do
    ctx.doc |> Ecto.Changeset.change(kind: "final") |> Repo.update!()
    {:ok, view, _} = live(ctx.conn, "/admin/billing/documents/#{ctx.doc.id}")
    assert has_element?(view, "#accommodation-abra-pdf-send")

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(build_conn(), "/admin/billing/documents/#{ctx.doc.id}")
  end
end
