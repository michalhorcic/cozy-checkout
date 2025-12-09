defmodule CozyCheckoutWeb.IcalImportLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.IcalImporter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import iCal Bookings")
     |> assign(:uploaded_files, [])
     |> assign(:import_result, nil)
     |> allow_upload(:ical_file,
       accept: ~w(.ics),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :ical_file, ref)}
  end

  @impl true
  def handle_event("import", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :ical_file, fn %{path: path}, _entry ->
        content = File.read!(path)
        {:ok, content}
      end)

    case uploaded_files do
      [content] ->
        case IcalImporter.import_ical(content) do
          {:ok, stats} ->
            {:noreply,
             socket
             |> assign(:import_result, {:ok, stats})
             |> put_flash(:info, "Import completed successfully!")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:import_result, {:error, reason})
             |> put_flash(:error, "Import failed: #{reason}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "Please select a file to import")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/admin"} class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block">
          ← Back to Dashboard
        </.link>
        <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
        <p class="text-primary-400 mt-2">
          Import bookings from an iCal (.ics) file. The system will create guests and bookings automatically.
        </p>
      </div>

      <div class="bg-white shadow-lg rounded-lg p-6">
        <form phx-submit="import" phx-change="validate" class="space-y-6">
          <div>
            <label class="block text-sm font-medium text-primary-500 mb-2">
              Select iCal File
            </label>
            <div
              class="mt-1 flex justify-center px-6 pt-5 pb-6 border-2 border-secondary-300 border-dashed rounded-lg hover:border-blue-400 transition-colors"
              phx-drop-target={@uploads.ical_file.ref}
            >
              <div class="space-y-1 text-center">
                <.icon name="hero-document-arrow-up" class="mx-auto h-12 w-12 text-primary-300" />
                <div class="flex text-sm text-primary-400">
                  <label
                    for={@uploads.ical_file.ref}
                    class="relative cursor-pointer bg-white rounded-md font-medium text-tertiary-600 hover:text-white opacity-900"
                  >
                    <span>Upload a file</span>
                    <.live_file_input upload={@uploads.ical_file} class="sr-only" />
                  </label>
                  <p class="pl-1">or drag and drop</p>
                </div>
                <p class="text-xs text-primary-400">iCal files (.ics) up to 5MB</p>
              </div>
            </div>
          </div>

          <%!-- Show uploaded files --%>
          <div
            :for={entry <- @uploads.ical_file.entries}
            class="flex items-center gap-4 p-4 bg-secondary-50 rounded-lg"
          >
            <.icon name="hero-document-text" class="w-8 h-8 text-tertiary-600" />
            <div class="flex-1">
              <p class="text-sm font-medium text-primary-500">{entry.client_name}</p>
              <p class="text-xs text-primary-400">{format_bytes(entry.client_size)}</p>
            </div>
            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              class="text-error hover:text-error-dark"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <%!-- Upload errors --%>
          <div :for={err <- upload_errors(@uploads.ical_file)} class="text-error text-sm">
            {error_to_string(err)}
          </div>

          <div class="flex justify-end">
            <.button type="submit" disabled={@uploads.ical_file.entries == []}>
              <.icon name="hero-arrow-down-tray" class="w-5 h-5 mr-2" /> Import Bookings
            </.button>
          </div>
        </form>
      </div>

      <%!-- Import Results --%>
      <div :if={@import_result} class="mt-6 bg-white shadow-lg rounded-lg p-6">
        <h2 class="text-2xl font-bold text-primary-500 mb-4">Import Results</h2>

        <%= case @import_result do %>
          <% {:ok, stats} -> %>
            <div class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div class="bg-success-light border border-green-200 rounded-lg p-4">
                  <p class="text-sm text-success-dark font-medium">Guests Created</p>
                  <p class="text-3xl font-bold text-green-900">{stats.guests_created}</p>
                </div>
                <div class="bg-tertiary-50 border border-blue-200 rounded-lg p-4">
                  <p class="text-sm text-tertiary-600 font-medium">Guests Found</p>
                  <p class="text-3xl font-bold text-blue-900">{stats.guests_found}</p>
                </div>
                <div class="bg-success-light border border-green-200 rounded-lg p-4">
                  <p class="text-sm text-success-dark font-medium">Bookings Created</p>
                  <p class="text-3xl font-bold text-green-900">{stats.bookings_created}</p>
                </div>
                <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                  <p class="text-sm text-yellow-600 font-medium">Bookings Skipped</p>
                  <p class="text-3xl font-bold text-yellow-900">{stats.bookings_skipped}</p>
                </div>
              </div>

              <div :if={stats.errors != []} class="mt-4">
                <h3 class="text-lg font-semibold text-primary-500 mb-2">Errors</h3>
                <div class="bg-error-light border border-red-200 rounded-lg p-4 space-y-2">
                  <div :for={{guest_name, error} <- stats.errors} class="text-sm text-error-dark">
                    <span class="font-medium">{guest_name}:</span> {error}
                  </div>
                </div>
              </div>
            </div>
          <% {:error, reason} -> %>
            <div class="bg-error-light border border-red-200 rounded-lg p-4">
              <p class="text-error-dark">{reason}</p>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted (only .ics files)"
  defp error_to_string(:too_many_files), do: "Too many files (max 1)"

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 2)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end
end
