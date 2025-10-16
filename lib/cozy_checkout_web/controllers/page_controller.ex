defmodule CozyCheckoutWeb.PageController do
  use CozyCheckoutWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
