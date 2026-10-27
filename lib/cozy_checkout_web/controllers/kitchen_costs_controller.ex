defmodule CozyCheckoutWeb.KitchenCostsController do
  use CozyCheckoutWeb, :controller
  alias CozyCheckout.KitchenCosts.Import

  def catalog(conn, _) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_download({:binary, Jason.encode!(Import.catalog(), pretty: true)},
      filename: "kitchen-catalog.json",
      content_type: "application/json"
    )
  end

  def contract(conn, %{"file" => file})
      when file in ["receipt-v1.schema.json", "receipt-v1.example.json", "CHATGPT.md"] do
    path = Application.app_dir(:cozy_checkout, "priv/kitchen_costs/" <> file)
    send_download(conn, {:file, path}, filename: file)
  end

  def contract(conn, _), do: send_resp(conn, 404, "Nenalezeno")
end
