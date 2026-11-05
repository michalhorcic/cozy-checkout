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

  defp extension("application/pdf"), do: ".pdf"
  defp extension("image/png"), do: ".png"
  defp extension(_), do: ".jpg"
end
