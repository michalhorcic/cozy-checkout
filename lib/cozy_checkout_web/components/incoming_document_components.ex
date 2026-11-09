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

  attr :loading, :boolean, required: true
  attr :error, :any, default: nil
  attr :empty, :boolean, required: true

  def accounting_catalog_status(assigns) do
    ~H"""
    <div class="space-y-2">
      <p :if={@loading} role="status" class="flex items-center gap-2 text-sm text-base-content/70">
        <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Načítám předpisy z ABRA…
      </p>
      <p :if={@error} role="alert" class="rounded-lg bg-error/10 p-3 text-sm text-error">
        {@error} Aktuální předpis zůstává zachovaný.
      </p>
      <p :if={!@loading && !@error && @empty} role="status" class="text-sm text-base-content/70">
        V ABRA nejsou pro tuto kategorii dostupné žádné předpisy. Aktuální předpis zůstává zachovaný.
      </p>
      <button
        :if={!@loading}
        type="button"
        phx-click="accounting-load"
        class="btn btn-ghost btn-sm min-h-11"
      >
        <.icon name="hero-arrow-path" class="size-4" /> {if @error,
          do: "Zkusit znovu",
          else: "Obnovit předpisy z ABRA"}
      </button>
    </div>
    """
  end
end
