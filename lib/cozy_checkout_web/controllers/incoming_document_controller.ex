defmodule CozyCheckoutWeb.IncomingDocumentController do
  use CozyCheckoutWeb, :controller
  alias CozyCheckout.IncomingDocuments

  def show(conn, %{"id" => id}) do
    doc = IncomingDocuments.get!(id)

    conn
    |> put_resp_content_type(doc.content_type)
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header(
      "content-disposition",
      "inline; filename=\"doklad#{extension(doc.content_type)}\""
    )
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, doc.original)
  end

  def xml(conn, %{"id" => id}) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    case IncomingDocuments.diagnostic_xml(id) do
      {:ok, xml} ->
        conn
        |> put_resp_content_type("application/xml")
        |> put_resp_header("content-disposition", "attachment; filename=\"NEOVERENO-abra.xml\"")
        |> send_resp(200, xml)

      {:error, reason} ->
        conn |> put_resp_content_type("text/plain") |> send_resp(422, reason)
    end
  end

  defp extension("application/pdf"), do: ".pdf"
  defp extension("image/png"), do: ".png"
  defp extension(_), do: ".jpg"
end
