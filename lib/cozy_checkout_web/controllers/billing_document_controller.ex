defmodule CozyCheckoutWeb.BillingDocumentController do
  use CozyCheckoutWeb, :controller

  def show(conn, %{"id" => id}) do
    case CozyCheckout.Billing.ensure_pdf(id) do
      {:ok, doc} ->
        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{doc.number}.pdf\"")
        |> send_resp(200, doc.pdf)

      {:error, _} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, "PDF se nepodařilo připravit. Zkuste stažení znovu.")
    end
  end
end
