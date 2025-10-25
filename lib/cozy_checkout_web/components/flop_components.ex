defmodule CozyCheckoutWeb.FlopComponents do
  @moduledoc """
  Reusable components for Flop-based tables with filtering, sorting, and pagination.
  """
  use Phoenix.Component
  import CozyCheckoutWeb.CoreComponents

  @doc """
  Renders a sortable table header.

  ## Examples

      <.sortable_header meta={@meta} field={:check_in_date} path={~p"/admin/bookings"}>
        Check-in Date
      </.sortable_header>
  """
  attr :meta, Flop.Meta, required: true
  attr :field, :atom, required: true
  attr :path, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def sortable_header(assigns) do
    ~H"""
    <th class={[
      "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 transition-colors",
      @class
    ]}>
      <.link
        patch={build_path(@path, @meta, :order, @field)}
        class="flex items-center gap-2 no-underline"
      >
        <span><%= render_slot(@inner_block) %></span>
        <.sort_icon meta={@meta} field={@field} />
      </.link>
    </th>
    """
  end

  @doc """
  Renders a sort direction icon based on current ordering.
  """
  attr :meta, Flop.Meta, required: true
  attr :field, :atom, required: true

  def sort_icon(assigns) do
    direction = Flop.current_order(assigns.meta.flop, assigns.field)

    assigns = assign(assigns, :direction, direction)

    ~H"""
    <%= case @direction do %>
      <% :asc -> %>
        <.icon name="hero-chevron-up" class="w-4 h-4" />
      <% :desc -> %>
        <.icon name="hero-chevron-down" class="w-4 h-4" />
      <% _ -> %>
        <.icon name="hero-chevron-up-down" class="w-4 h-4 text-gray-300" />
    <% end %>
    """
  end

  @doc """
  Renders a filter form for a table.

  ## Examples

      <.filter_form meta={@meta} path={~p"/admin/bookings"} id="bookings-filter">
        <:filter>
          <.input type="select" name="filters[0][field]" value="status" class="hidden" />
          <.input type="select" name="filters[0][op]" value="==" class="hidden" />
          <.input
            type="select"
            name="filters[0][value]"
            label="Status"
            options={[
              {"All", ""},
              {"Upcoming", "upcoming"},
              {"Active", "active"},
              {"Completed", "completed"},
              {"Cancelled", "cancelled"}
            ]}
            value={get_filter_value(@meta, :status)}
          />
        </:filter>
      </.filter_form>
  """
  attr :meta, Flop.Meta, required: true
  attr :path, :string, required: true
  attr :id, :string, required: true
  attr :class, :string, default: nil

  slot :filter, required: true

  def filter_form(assigns) do
    ~H"""
    <div class={["p-4 border-b border-gray-200 bg-gray-50", @class]}>
      <form phx-change="filter" phx-submit="filter" id={@id}>
        <div class="flex flex-wrap gap-4 items-end">
          <%= for filter <- @filter do %>
            <div class="flex-1 min-w-[200px]">
              <%= render_slot(filter) %>
            </div>
          <% end %>

          <div class="flex gap-2">
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              Apply
            </button>
            <.link
              patch={@path}
              class="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors"
            >
              Clear
            </.link>
          </div>
        </div>
      </form>
    </div>
    """
  end

  @doc """
  Renders pagination controls.

  ## Examples

      <.pagination meta={@meta} path={~p"/admin/bookings"} />
  """
  attr :meta, Flop.Meta, required: true
  attr :path, :string, required: true
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <div class={["px-4 py-3 flex items-center justify-between border-t border-gray-200", @class]}>
      <!-- Mobile pagination -->
      <div class="flex-1 flex justify-between sm:hidden">
        <%= if @meta.has_previous_page? do %>
          <.link
            patch={build_path(@path, @meta, :previous)}
            class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Previous
          </.link>
        <% else %>
          <span class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-400 bg-gray-100 cursor-not-allowed">
            Previous
          </span>
        <% end %>

        <%= if @meta.has_next_page? do %>
          <.link
            patch={build_path(@path, @meta, :next)}
            class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Next
          </.link>
        <% else %>
          <span class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-400 bg-gray-100 cursor-not-allowed">
            Next
          </span>
        <% end %>
      </div>

      <!-- Desktop pagination -->
      <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
        <div>
          <p class="text-sm text-gray-700">
            Showing
            <span class="font-medium"><%= @meta.current_offset + 1 %></span>
            to
            <span class="font-medium">
              <%= min(@meta.current_offset + @meta.page_size, @meta.total_count) %>
            </span>
            of
            <span class="font-medium"><%= @meta.total_count %></span>
            results
          </p>
        </div>

        <div>
          <nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px">
            <!-- Previous button -->
            <%= if @meta.has_previous_page? do %>
              <.link
                patch={build_path(@path, @meta, :previous)}
                class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
              >
                <.icon name="hero-chevron-left" class="w-5 h-5" />
              </.link>
            <% else %>
              <span class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-gray-100 text-sm font-medium text-gray-400 cursor-not-allowed">
                <.icon name="hero-chevron-left" class="w-5 h-5" />
              </span>
            <% end %>
            <!-- Page numbers -->
            <%= for page <- page_numbers(@meta) do %>
              <%= if page == @meta.current_page do %>
                <span class="relative inline-flex items-center px-4 py-2 border border-blue-500 bg-blue-50 text-sm font-medium text-blue-600">
                  <%= page %>
                </span>
              <% else %>
                <.link
                  patch={build_path(@path, @meta, :page, page)}
                  class="relative inline-flex items-center px-4 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  <%= page %>
                </.link>
              <% end %>
            <% end %>
            <!-- Next button -->
            <%= if @meta.has_next_page? do %>
              <.link
                patch={build_path(@path, @meta, :next)}
                class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
              >
                <.icon name="hero-chevron-right" class="w-5 h-5" />
              </.link>
            <% else %>
              <span class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-gray-100 text-sm font-medium text-gray-400 cursor-not-allowed">
                <.icon name="hero-chevron-right" class="w-5 h-5" />
              </span>
            <% end %>
          </nav>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  @doc """
  Builds a URL path with Flop parameters for pagination and sorting.
  """
  def build_path(base_path, %Flop.Meta{flop: flop} = meta, action, field_or_page \\ nil) do
    params =
      case action do
        :order ->
          # Toggle sort order
          new_flop = Flop.push_order(flop, field_or_page)
          flop_to_params(new_flop)

        :page ->
          # Set specific page
          new_flop = Flop.set_page(flop, field_or_page)
          flop_to_params(new_flop)

        :next ->
          # Next page
          new_flop = Flop.to_next_page(flop, meta.total_pages)
          flop_to_params(new_flop)

        :previous ->
          # Previous page
          new_flop = Flop.to_previous_page(flop)
          flop_to_params(new_flop)
      end

    "#{base_path}?#{Plug.Conn.Query.encode(params)}"
  end

  @doc """
  Converts a Flop struct to URL query parameters.
  """
  def flop_to_params(%Flop{} = flop) do
    params = %{}

    # Always include page (default to 1) to avoid nil arithmetic errors
    params =
      Map.put(params, "page", flop.page || 1)

    # Always include page_size if there's a limit
    params =
      if flop.page_size || flop.limit do
        Map.put(params, "page_size", flop.page_size || flop.limit || 20)
      else
        params
      end

    # Keep order_by as a regular array (Flop expects arrays, not indexed maps)
    params =
      if flop.order_by && flop.order_by != [] do
        Map.put(params, "order_by", Enum.map(flop.order_by, &to_string/1))
      else
        params
      end

    # Keep order_directions as a regular array
    params =
      if flop.order_directions && flop.order_directions != [] do
        Map.put(params, "order_directions", Enum.map(flop.order_directions, &to_string/1))
      else
        params
      end

    # Handle filters
    params =
      if flop.filters && flop.filters != [] do
        filters =
          Enum.with_index(flop.filters)
          |> Enum.reduce(%{}, fn {filter, idx}, acc ->
            filter_params = %{
              "field" => to_string(filter.field),
              "op" => to_string(filter.op),
              "value" => filter.value
            }

            Map.put(acc, to_string(idx), filter_params)
          end)

        Map.put(params, "filters", filters)
      else
        params
      end

    params
  end

  @doc """
  Gets the value of a specific filter from the meta.
  """
  def get_filter_value(%Flop.Meta{flop: flop}, field) do
    case Enum.find(flop.filters || [], fn f -> f.field == field end) do
      nil -> ""
      filter -> filter.value || ""
    end
  end

  @doc """
  Generates a list of page numbers to display in pagination.
  Shows a maximum of 7 page numbers with ellipsis.
  """
  def page_numbers(%Flop.Meta{} = meta) do
    total_pages = meta.total_pages
    current_page = meta.current_page

    cond do
      # Show all pages if 7 or less
      total_pages <= 7 ->
        Enum.to_list(1..total_pages)

      # Current page is in the first 4 pages
      current_page <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total_pages]

      # Current page is in the last 4 pages
      current_page >= total_pages - 3 ->
        [
          1,
          :ellipsis,
          total_pages - 4,
          total_pages - 3,
          total_pages - 2,
          total_pages - 1,
          total_pages
        ]

      # Current page is in the middle
      true ->
        [
          1,
          :ellipsis,
          current_page - 1,
          current_page,
          current_page + 1,
          :ellipsis,
          total_pages
        ]
    end
    |> Enum.filter(&(&1 != :ellipsis))
  end
end
