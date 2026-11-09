defmodule CozyCheckoutWeb.IncomingDocumentComponents do
  use CozyCheckoutWeb, :html

  attr :active, :string, required: true

  def navigation(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3">
      <nav aria-label="Přijaté doklady" class="flex rounded-lg bg-base-200 p-1 gap-1">
        <.link
          navigate={~p"/admin/incoming-documents"}
          aria-current={@active == "batches" && "page"}
          class={[
            "btn btn-sm min-h-11",
            if(@active == "batches", do: "bg-base-100 shadow-sm", else: "btn-ghost")
          ]}
        >Dávky</.link>
        <.link
          navigate={~p"/admin/incoming-documents/all"}
          aria-current={@active == "documents" && "page"}
          class={[
            "btn btn-sm min-h-11",
            if(@active == "documents", do: "bg-base-100 shadow-sm", else: "btn-ghost")
          ]}
        >Doklady</.link>
      </nav>
      <div class="flex flex-wrap gap-2 w-full sm:w-auto">
        <.link
          navigate={~p"/admin/incoming-document-batches/new"}
          class="btn btn-primary min-h-11 w-full sm:w-auto"
        ><.icon name="hero-camera" class="size-5" /> Nahrát doklady</.link>
        <.link navigate={~p"/admin/incoming-document-form"} class="btn btn-ghost min-h-11">Nový doklad ručně</.link>
      </div>
    </div>
    """
  end

  def document_state_class(state) when state in ["failed", "uncertain"], do: "badge-error"
  def document_state_class("sent"), do: "badge-success"
  def document_state_class("review"), do: "badge-warning"
  def document_state_class(_), do: "badge-info"
end
