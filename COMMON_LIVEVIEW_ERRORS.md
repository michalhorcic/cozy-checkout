# Common LiveView Errors & Solutions

## ❌ Error: "no function clause matching in handle_event/3"

### Cause
This error occurs when the parameters sent from the client don't match the pattern in any `handle_event/3` function clause.

### Common Scenarios

#### 1. phx-click vs phx-change parameter structure
```elixir
# ❌ WRONG - phx-change sends entire form, not just the changed field
def handle_event("select_product", %{"index" => index, "value" => product_id}, socket)

# ✅ CORRECT - phx-click sends simple params
def handle_event("add_item", _params, socket)
```

**Solution**: Remove `phx-change` event handlers from form inputs unless you handle the entire form params, or add a catch-all clause.

#### 2. Missing catch-all clause
```elixir
# ✅ ALWAYS add this at the end of your handle_event clauses
def handle_event(event, params, socket) do
  require Logger
  Logger.warning("Unhandled event: #{event}, params: #{inspect(params)}")
  {:noreply, socket}
end
```

#### 3. Socket assigns not initialized
```elixir
# ❌ WRONG - items might not exist in assigns
def handle_event("add_item", _params, socket) do
  {:noreply, assign(socket, :items, socket.assigns.items ++ [new_item])}
end

# ✅ CORRECT - ensure items is initialized in update/2
def update(assigns, socket) do
  {:ok, socket |> assign(assigns) |> assign(:items, [])}
end
```

### Prevention Checklist

- [ ] Always initialize all assigns in `update/2` or `mount/3`
- [ ] Add catch-all `handle_event/3` clause for debugging
- [ ] Avoid `phx-change` on individual form inputs (use form-level validation instead)
- [ ] Test form submission with and without optional fields
- [ ] Use `IO.inspect()` or `Logger.debug()` to see actual params

### Quick Fix Template

```elixir
@impl true
def handle_event(event, params, socket) do
  require Logger
  Logger.warning("Unhandled event in #{__MODULE__}: #{event}")
  Logger.debug("Params: #{inspect(params, pretty: true)}")
  {:noreply, socket}
end
```

Add this as the **last** `handle_event/3` clause to catch any unmatched events and see what's actually being sent.

---

## 📝 Other Common Issues

### undefined function simple_form/1
- **Cause**: Using `<.simple_form>` instead of `<.form>`
- **Fix**: Replace `<.simple_form>` with `<.form>` and move `:actions` slot content to regular div

### Cannot access socket.assigns.some_field
- **Cause**: Assign not initialized in `update/2` or `mount/3`
- **Fix**: Initialize all assigns before using them

### phx-update="stream" errors
- **Cause**: Not providing `id` attribute on streamed items
- **Fix**: Always use `<div :for={{id, item} <- @streams.items} id={id}>`
