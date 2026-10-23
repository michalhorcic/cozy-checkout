# Cozy Checkout — agent instructions

Cozy Checkout is a self-service POS and guesthouse management application for
Jindřichův dům. It uses Elixir, Phoenix 1.8 / LiveView, PostgreSQL, Oban,
Tailwind CSS v4 and daisyUI, with Docker deployment through Coolify.

## Instruction ownership and maintenance

- `AGENTS.md` is the single source of truth for repository-wide development instructions. `.github/copilot-instructions.md` points here so Copilot and other agents follow the same rules.
- Read these instructions before changing code. Inspect the existing implementation, schemas, migrations and tests before applying a rule to a particular feature.
- **Whenever you make substantial changes during development, review and update these instructions as part of the same change.** This includes changes to architecture, business rules, data models, integrations, configuration, build/test commands, deployment or development workflow.
- Keep `AGENTS.md` accurate and keep `.github/copilot-instructions.md` aligned with it. Put shared rules here rather than duplicating them in the Copilot file; update that file when its reference or Copilot-specific guidance changes.
- Remove obsolete or contradictory instructions and record the final supported behaviour. Do not turn historical feature requests or speculative ideas into implementation tasks.
- Before completing a task, check whether the instructions need updating and mention any material documentation changes in the handoff.

## Product and development principles

- Keep guest-facing POS flows extremely simple, with large touch-friendly controls and as few steps as possible. Accounting, inventory and other administrative complexity belongs in the admin interface.
- Keep business logic in contexts, outside controllers and LiveViews. Follow existing patterns and prefer simple solutions over unnecessary abstractions.
- Do not silently change business behaviour. Ask for clarification when a requirement materially affects the implementation and cannot be resolved from the repository.
- Use Ecto migrations for database changes. Use Oban for retryable/background operations where appropriate; external integrations must tolerate temporary failures.
- Use the included `Req` HTTP client, not `:httpoison`, `:tesla` or `:httpc`. Add dependencies only with a strong reason.
- Never hardcode secrets, credentials or production URLs.

## Data and financial rules

- Follow the existing `:binary_id` primary/foreign key convention. Include `inserted_at` / `updated_at` timestamps, indexes on foreign keys and database unique indexes for unique values.
- Preserve soft deletes on business records using an indexed `deleted_at` field. For `:utc_datetime`, truncate timestamps to seconds; preserve the precision of fields explicitly using microseconds.
- Capture the unit price, unit amount and VAT rate on order items at purchase time. Later catalog changes must not alter historical financial records.
- Use `Decimal` and the existing financial helpers for monetary calculations. Preserve proportional discount allocation across VAT rates and report voluntary tips separately without VAT.
- Use `CozyCheckoutWeb.CurrencyHelper.format_currency/1` for money and `format_number/1` for numbers in templates/LiveViews. Currency defaults to CZK and is configured by `@currency_symbol` in that helper; do not hardcode currency symbols in new UI.
- The default VAT rate is zero. Preserve explicit per-item VAT rates, payment validation and concurrency protection for payments and document numbering.
- Keep ABRA synchronization retryable and idempotent. Test external HTTP through `Req.Test`; tests must not create real accounting documents.

## Guests, bookings and rooms

- Guests represent people who may return; bookings represent individual stays. Keep booking-specific notes, short notes and dietary restrictions on bookings.
- Preserve booking statuses `upcoming`, `active`, `completed` and `cancelled`; default booking sorting is ascending `check_in_date`.
- `booking_guests` links people to a stay. Create the primary guest association automatically, show the primary guest in booking/calendar summaries, and allow managing additional guests without removing the primary guest.
- `booking_rooms` links rooms to stays. Keep room availability and capacity rules in the booking/room contexts; show booked room numbers in booking and calendar views. Do not assume `booking_rooms` contains a historical snapshot of room fields.
- iCal imports find or create guests and import stay dates, contact details and notes from VEVENTs. See `ICAL_IMPORT.md`.
- Redirect newly created bookings to their detail page (`/admin/bookings/:id`).
- Cottage capacity is 45 people, defined in `CozyCheckout.Bookings`. Occupancy counts invoice items with `item_type = "person"`, including personal stays. Calendar thresholds are green below 30, yellow 30–39, orange 40–44 and red at 45 or more.

## Orders and POS

- Standalone orders are valid without a booking or guest. `guest_id` and `booking_id` are nullable; an order must have either a guest or a nonblank name. Keep standalone orders payable in POS.
- In order lists/details, payments, receipts and accounting exports, handle missing bookings/guests safely: use the booking guest when available, otherwise the order name with the standalone indicator. Exports may fall back to "Unknown Customer" if neither is available.
- Keep individual `order_items` records while grouping their UI presentation by product and unit amount. Allow expanding groups and deleting individual items; POS must not delete whole groups.
- Show order names in order selection and prices on product cards or amount choices. For products with `default_unit_amounts`, offer only predefined amounts; preserve the existing fallback for products without presets.
- Prefer Flop for admin filtering, sorting and pagination without adding `flop_phoenix` unless compatibility is established. Keep reusable UI separate from query logic, encode filters in URLs and handle empty results.
- Flop schemas use `use Flop.Schema` and `@flop_options` (Flop 0.29+). Keep `tiebreaker: false` to preserve the existing ordering; review any future change to tie ordering explicitly.
- Orders support status, name, guest, order-number, creation-date range and booking guest-name filters. Order-number search uses ILIKE. Support sorting by creation time and status, defaulting to newest first.
- Preserve the 80mm receipt at `/admin/orders/:id/receipt`, accessible from order details and POS cash/QR payment success. Include items, total, payment date, document number and VAT breakdown.
- Printed company details are Moruška s.r.o., IČO 23741457, Jindřichův dům, Pec pod Sněžkou 24.

## Catalog and pricelists

- Products have an optional unit and optional `default_unit_amounts`, currently stored as a JSON-encoded string. Decode/validate it rather than assuming a native PostgreSQL array.
- Tiered pricing belongs to `CozyCheckout.Catalog.Pricelist` / `pricelists`, not a separate `pricelist_items` model. `price_tiers` is `{:array, :map}`, default `[]`, with string keys `"unit_amount"` and `"price"`.
- Preserve single `price` support for products without presets. Validate that a price or tiers exist; tier amounts must be positive and prices nonnegative. Use `Pricelist.get_price_for_amount/2` and `Catalog.get_price_for_product/3` for amount pricing.
- Show all preset amounts in tier forms and require complete pricing. Show tiers in indexes, a single price when appropriate, or an em dash when absent. Sort a product's pricelists by `valid_to` descending (not `valid_until`).
- Product autocomplete searches product/category names with a 300ms debounce, shows category/unit context, and supports clearing the selection. Keep product selection disabled when editing an existing pricelist.
- Price management (`/admin/pricelists/management`) distinguishes missing, expired/invalid and incomplete tier prices with red, yellow and orange indicators and quick-edit forms.
- Categories use explicit `order`, with name as tie-breaker; new categories go last. Preserve this ordering in POS.
- Printable pricelists (`/admin/pricelists/print`) include only currently valid prices, category selection (all by default), an empty-selection warning and a custom title defaulting to "Ceník".
- Preserve portrait A4 printing, two flowing columns, category blocks without internal breaks, Czech alphabetical product sorting, cottage/company details and the generation date (`Date.utc_today()`). Hide selection controls on print. Show tiers in corresponding amount/price order, e.g. `Product (300/500 ml) 45/70 CZK`.

## Booking invoices and billing

- `booking_invoices` / `booking_invoice_items` are editable stay calculations and occupancy sources, not issued financial documents. `person` items count toward occupancy; `extra` items do not. Quantity may be zero; nights default to 1. Preserve exact category names used by the calendar.
- New calculations use `pricing_basis = "gross"`, seasonal arrival-date prices for the entire stay, and 12% VAT by default. Missing seasonal prices remain nil and must not fall back to hardcoded amounts. Preserve `legacy_net` calculations, old numbers and states as internal history; do not infer payments or issued documents from them.
- Accommodation seasons are separate from bar/catalog pricelists, include both end dates, and cannot overlap (PostgreSQL date-range exclusion). Repricing is explicit and copies prices, VAT and nights; later season changes do not affect saved calculations or documents.
- `CozyCheckout.Billing` owns supplier/customer profiles, numbering, immutable document snapshots, manual payments/refunds, advance deductions, PDFs and delivery records. Keep logic out of LiveViews. All billing mutations concerning a stay lock its booking row; series allocation locks the series row in the same transaction. Requests carry UUID idempotency keys.
- There is one final document per booking, with multiple advance requests and tax receipts. Each received pre-settlement advance creates a tax receipt, including receipts without a request and overpayments. Deductions retain the original rounded net/VAT and never create another payment. Refunds require sufficient available credit; no bank transfers are executed.
- Corrections are linked differential documents with reasons. Correct a final after settlement, not the deducted tax receipts. Do not expose deletion, editing or draft transitions for issued documents. Supplier/customer details and financial lines are copied at issuance.
- New series are configured per document kind/year before issuance; used series cannot be changed. Preserve the old `YY08XXXXX` numbers solely as legacy internal identifiers. Unique ten-digit variable symbols use a separate PostgreSQL sequence; do not derive them by stripping prefixes from document numbers. Bar numbering is unchanged.
- Use `Billing.Money` / `Decimal` for gross calculations and haléř rounding; distinguish `taxable` zero VAT from `outside` VAT (manual local stay fee). Do not silently reinterpret old net prices as gross.
- Generate self-contained A4 PDF using ChromicPDF/Chromium and persist bytes plus SHA-256 in PostgreSQL. Reuse the same stored PDF for downloads and email attachments. PDF generation and mail use Oban queue `billing`, with idempotency keys for Resend. Provider acceptance means sent, not confirmed delivery. Require recorded electronic-document consent before enqueueing.
- `Billing.PdfBrowser` lazily starts and owns a persistent Chrome instance with a dedicated temporary `--user-data-dir` (required by branded Chrome 136+), serializes render calls and cleans up its profile on shutdown. Do not launch PDF Chrome against the user's default profile. `Billing.Pdf` isolates work in unlinked supervised tasks and catches exits/timeouts. Render outside SQL transactions; persist the first completed PDF under a short row lock and reuse that winner for concurrent requests. Dev stderr remains visible; downloads and email history expose actionable errors. Local-mailbox regression tests use the actual Swoosh Local storage and a caller that does not trap exits.
- Billing previews and PDFs share `Billing.Presentation`: Czech decimal commas, two decimal places and `dd.mm.yyyy` dates, including snapshot stay dates. New advance requests snapshot the full stay lines and the requested percentage or explicit amount in `snapshot["advance_calculation"]` before tax-group allocation. Preview, document detail and PDF show adults/child categories, quantities, nights and gross unit/line prices, followed by the stay total and advance calculation; never show net/VAT breakdown on advance requests. Explicit amounts take precedence over percentages. Tax receipts keep their summary presentation; final invoices keep the detailed tax calculation. Old advances lacking the snapshot retain their generic description rather than using a current calculation. Show positive balances as “K úhradě”, negative balances as positive “Přeplatek”, and zero as “Zbývá k úhradě”. Embed the Cozy Checkout knot from `priv/static/images/cozy-knot.svg` beside the Jindřichův dům name in PDFs. Existing stored PDF bytes remain unchanged after template updates.
- The booking billing workspace overrides the default narrow layout with `max-w-7xl`; keep calculation tables readable, align amounts right and contain horizontal scrolling within the table on mobile. Document previews occupy the full workspace width below the customer/issuance form grid so stay breakdowns remain readable. Do not show redundant “Osoby” badges on person rows. Keep the item type selector because it controls occupancy. Issued documents offer direct PDF downloads and an email composer modal in the workspace; reuse `BillingComponents.email_form` and `BillingLive.Helpers.email_defaults` with the document detail screen. Only compose documents belonging to the current booking, retain input after validation errors, and keep email request IDs on the server for retries. Sending queues the existing immutable PDF via `Billing.enqueue_email`; it does not navigate away or imply delivery.
- The stay calculation uses an inline batch editor: quantity, nights and unit price are directly editable; name, occupancy type and VAT stay in row details. Additions and removals remain drafts until “Uložit změny”; “Zahodit změny” reloads the saved calculation. Use `Billing.save_calculation_items/3` to save atomically under the booking lock with `calculation_version/1` conflict detection. Preview draft totals with `Billing.Money`; block issuance, payments, repricing and personal-state changes until drafts are saved or discarded. Preserve draft input on errors and unrelated workspace refreshes. On mobile, show the same fields as cards.
- All billing routes and PDF downloads belong behind existing admin authentication. Keep personal stays available without issued documents and preserve their occupancy. ABRA integration for accommodation is deferred; leave bar exports separate.
- Booking-list financial states and filters come from `Billing.BookingSummary`, derived from issued documents, final corrections and net recorded receipts/refunds. Apply filters before pagination; never infer issuance or payments from legacy calculation states. An advance is distinct from a final invoice, even if fully prepaid. The list shows only one compact financial-state badge; document numbers, balances and explanatory text belong in a native top-layer popover accessible by mouse hover, keyboard focus and touch, with a link to billing. Personal stays show “Soukromý pobyt” without balances or financial forms; their occupancy and catering remain available.
- See `BILLING.md` for setup, financial workflow, backups and operational limits. Financial regression tests include actual Chromium PDF rendering, Swoosh test-adapter delivery, LiveView flows and independent-connection concurrency tests.

## Kitchen shopping presentation

- Keep the shopping list compact, with an inline summary and rows retaining purchase quantity, packaging, consumption, checkboxes, purchase settings and expandable recipe/group provenance.
- The dedicated print route uses an explicit two-column CSS grid on screen and A4 paper (read left to right, then down), with category headings spanning both columns. Avoid CSS multicolumn flow for this checklist because paged printing can differ from the screen preview. It is a checklist with blank paper checkboxes, full ingredient names, purchase quantities, packaging and ongoing-purchase labels. Preserve the selected date/group scope and incomplete-data warnings; omit interactive controls, recipe breakdowns and duplicate consumption figures. Browser-local completion must not remove ingredients from the printed list.

## Admin navigation and operational dashboard

- The authenticated admin LiveView layout owns the shared sidebar, mobile navigation and header controls (Pokladna / Zamknout). `CozyCheckoutWeb.AdminNavigation` tracks the current route through an on-mount `handle_params` hook; keep it in the authenticated session after `AdminAuth`.
- Main navigation prioritizes the reservation calendar, food, bar stock, guest emails and bar accounts/payments. Keep all secondary administration reachable in named groups under Další agenda; technical diagnostics belong under Systém.
- Food screens retain their focused navigation and expose the main administration through Přejít do jiné oblasti. Hide the outer admin sidebar/mobile menu on food screens and all navigation/controls on print.
- `CozyCheckout.Dashboard.overview/1` is a read-only overview. Its stay list includes nondeleted upcoming/active stays overlapping today through the same day of the following month, inclusive, clamped at month end. Include today's departures and ongoing stays; exclude cancelled/completed stays from the list and attention items.
- Reuse calendar occupancy (invoice person items, including personal stays) and planner portion calculations (including departure meals). These are different measures; do not substitute meal counts for bed occupancy. Attention items use existing incomplete-catering and missing/stale-menu rules, scoped to displayed stays. The connected dashboard refreshes once per minute.

## Application identity

- Cozy Checkout and `priv/static/images/cozy-knot.svg` identify the internal application. The authenticated admin LiveView session owns the shared brand header; `Layouts.app` does not show another header by default. Food pages show the brand in their navigation and hide the shared header. Keep Jindřichův dům as the primary identity in printed documents and guest-facing POS content. Billing PDFs explicitly use the Cozy Checkout knot alongside the house name at the owner’s request.
- The compact landscape-tablet POS header uses the locally bundled `priv/static/images/rano-nad-udolim.webp` photograph (source: `michalhorcic/Moruska`, `img/gallery/web/rano-nad-mlhou.webp`). Keep this photograph as a decorative background beneath a pale overlay behind the house name and existing controls, with no separate hero, greeting, altitude or caption. The authenticated admin header keeps its logo/name on one line. Keep the photograph on the welcome screen only; ordering screens use the house name and confirmed cash/QR payments show the personal thank-you. Do not show the payment thank-you on QR preview.
- Keep favicon and Apple touch icon consistent with the cozy knot. When changing the SVG, regenerate the opaque 180px touch icon on a white background with generous padding.

## Validation and handoff

- Use the Elixir/Erlang versions in `.tool-versions` (mise/asdf); CI reads that file. Keep Docker's runtime arguments aligned and the Elixir requirement in `mix.exs` accurate. Review dependency updates in small groups, commit `mix.lock`, run `mix hex.audit`, and verify production assets/release as well as tests after upgrades. See README for the maintenance cadence and macOS setup.
- After completing and validating repository changes, automatically create a feature branch, commit and push the changes, and open a pull request without asking for additional confirmation, unless the user explicitly requests otherwise. Include the completed checks and any verification limits in the PR description.
- Add or update tests for business-logic changes. Run relevant tests, check formatting and run `mix precommit` before completing changes; fix issues introduced by the change and report any blockers.
- `mix precommit` compiles with warnings as errors, checks unused dependencies, formats and runs tests. See `test/FINANCIAL_TESTS.md` for the financial regression suite.
- Explain the resulting behaviour and validation performed. Mention migrations, configuration changes and possible breaking changes when applicable.

## Framework guidelines

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `CozyCheckoutWeb.Layouts` module is aliased in the `cozy_checkout_web.ex` file, so you can use it without needing to alias it again
- Preserve the existing admin authentication: the `:admin_auth` pipeline and `live_session :admin` with `CozyCheckoutWeb.AdminAuth` on-mount validation. `Layouts.app` accepts an optional `current_scope`; do not assume Phoenix-generated account authentication is installed or move public POS routes into the admin session to satisfy an assign.
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for Heroicons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- Use the imported `<.input>` component from `core_components.ex` for form fields. Dynamic price-tier inputs may use plain HTML inputs with explicit `name` attributes when they are not changeset fields.
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/cozy_checkout_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- Follow the existing Tailwind CSS v4 and daisyUI components and theme in `assets/css/app.css`; use custom styles where needed. Keep the application light-themed (`prefersdark: false`) and preserve the existing design system.
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - Put new JavaScript in `assets/js` and import it through `app.js`; do not add inline scripts to templates. The existing root-layout light-theme bootstrap is an exception.
- Flash notices use LiveView's native `lv:clear-flash` command on the whole notice, including clicks bubbling from its close button. Preserve this dismissal behavior when restyling. LiveView clears flash on client live patches; daisyUI toast styles provide an entrance animation, not timed dismissal.

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- In this local environment, PostgreSQL uses the `elixir` role rather than the test config's default `postgres`; run tests with `PGUSER=elixir PGPASSWORD='' mix test`.
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `cozy_checkout_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use CozyCheckoutWeb, :html`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: 0)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
