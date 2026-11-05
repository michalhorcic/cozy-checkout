defmodule CozyCheckoutWeb.IncomingDocumentFormLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckoutWeb.AdminAuth

  setup do
    previous = IncomingDocuments.config()
    pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "pilot",
      username: "test",
      password: "test"
    )

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :incoming_documents, previous)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    :ok
  end

  defp admin(conn),
    do:
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

  defp attrs,
    do: %{
      "nazFirmy" => "Dodavatel",
      "cisDosle" => "R42",
      "datVyst" => "2026-11-05",
      "datSplat" => "2026-11-05",
      "sumOsv" => "123,45",
      "sumCelkem" => "123,45"
    }

  test "form requires admin PIN", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/incoming-document-form")
    assert to =~ "/admin/login"
  end

  test "manual form requires confirmation and opens existing accounting detail", %{conn: conn} do
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form")
    params = %{"agenda" => "zavazek", "document" => attrs()}
    view |> form("#incoming-header-form", params) |> render_submit()
    assert IncomingDocuments.list() == []
    view |> form("#incoming-header-form", Map.put(params, "reviewed", "true")) |> render_change()
    assert has_element?(view, "input[name=reviewed][type=checkbox][checked]")
    view |> form("#incoming-header-form", Map.put(params, "reviewed", "true")) |> render_submit()
    [doc] = IncomingDocuments.list()
    assert_redirect(view, "/admin/incoming-documents/#{doc.id}")
    {:ok, detail, _} = live(admin(build_conn()), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(detail, "#incoming-accounting")
    assert has_element?(detail, "a[href='/admin/incoming-document-form/#{doc.id}']")
    refute has_element?(detail, "iframe")
    refute has_element?(detail, "img[data-original]")

    assert_error_sent 404, fn ->
      get(admin(build_conn()), "/admin/incoming-documents/#{doc.id}/original")
    end
  end

  test "partial proposals can be opened in either detail without the item editor crashing", %{
    conn: conn
  } do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "partial.pdf", "zavazek", "header_form")

    data =
      File.read!("test/fixtures/incoming_documents/penny.json")
      |> Jason.decode!()
      |> Map.put("complete", false)

    doc |> Ecto.Changeset.change(state: "review", extracted_data: data) |> Repo.update!()
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert has_element?(view, "textarea[name='document[poznam]']")
    assert has_element?(view, "iframe")
    {:ok, detail, _} = live(admin(build_conn()), "/admin/incoming-documents/#{doc.id}")
    refute has_element?(detail, "#incoming-approve")
    refute has_element?(detail, "#incoming-source-form")
  end
end
