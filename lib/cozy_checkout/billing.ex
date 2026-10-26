defmodule CozyCheckout.Billing do
  @moduledoc "Seasonal accommodation prices and immutable issued documents, separate from occupancy."
  import Ecto.Query
  alias CozyCheckout.{Repo, Bookings}
  alias CozyCheckout.Bookings.{Booking, BookingInvoice, BookingInvoiceItem}

  alias CozyCheckout.Billing.{
    Season,
    Profile,
    Customer,
    Series,
    Document,
    Payment,
    Delivery,
    Money
  }

  @categories [{"Dospělí", :adult}, {"Děti do 2 let", :infant}, {"Děti do 12 let", :child}]
  @variable_symbol_codes %{
    "advance" => "1",
    "final" => "2",
    "tax_receipt" => "3",
    "correction" => "4"
  }
  @party_fields ~w(name street city postcode country company_id vat_id email phone registry bank_account iban due_days)
  def categories, do: @categories
  def today, do: Date.utc_today()

  def kinds,
    do: [
      {"Zálohová výzva", "advance"},
      {"Doklad k přijaté platbě", "tax_receipt"},
      {"Faktura", "final"},
      {"Opravný daňový doklad", "correction"}
    ]

  def kind_label(kind),
    do: Enum.find_value(kinds(), kind, fn {label, key} -> if key == kind, do: label end)

  def list_seasons,
    do: Repo.all(from s in Season, where: is_nil(s.deleted_at), order_by: s.valid_from)

  def get_season!(id), do: Repo.get!(Season, id)

  def save_season(attrs, id \\ nil),
    do:
      if(id, do: get_season!(id), else: %Season{})
      |> Season.changeset(attrs)
      |> Repo.insert_or_update()

  def delete_season(id),
    do:
      get_season!(id)
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()

  def season_on(date),
    do:
      Repo.one(
        from s in Season,
          where: is_nil(s.deleted_at) and s.valid_from <= ^date and s.valid_to >= ^date
      )

  def copy_season(id) do
    source = get_season!(id)

    save_season(%{
      name: source.name <> " (kopie)",
      valid_from: Date.shift(source.valid_from, year: 1),
      valid_to: Date.shift(source.valid_to, year: 1),
      adult: source.adult,
      infant: source.infant,
      child: source.child,
      vat_rate: source.vat_rate
    })
  end

  def profile,
    do:
      Repo.get_by(Profile, singleton: true) ||
        %Profile{
          data: %{
            "name" => "Moruška s.r.o.",
            "company_id" => "23741457",
            "country" => "CZ",
            "due_days" => "14"
          }
        }

  def customer(booking_id),
    do:
      Repo.get_by(Customer, booking_id: booking_id) ||
        %Customer{booking_id: booking_id, data: %{}}

  def save_profile(attrs) do
    transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(821901)")
      current = profile()

      updated =
        party_data(attrs)
        |> Map.update!("due_days", fn value -> if value == "", do: "14", else: value end)

      case Integer.parse(updated["due_days"] || "14") do
        {days, ""} when days in 0..365 -> :ok
        _ -> fail("Splatnost musí být 0 až 365 dnů")
      end

      updated = normalize_bank!(updated)
      current |> Ecto.Changeset.change(data: updated) |> Repo.insert_or_update!()
    end)
  end

  def save_customer(booking_id, attrs) do
    transaction(fn ->
      lock_booking!(booking_id)
      updated = party_data(attrs)
      validate_party!(updated, false)

      if Repo.exists?(from d in Document, where: d.booking_id == ^booking_id) and
           customer(booking_id).data != updated,
         do: fail("Odběratel má vystavené doklady; změnu údajů řešte opravou")

      customer(booking_id)
      |> Ecto.Changeset.change(data: updated)
      |> Repo.insert_or_update!()
    end)
  end

  defp normalize_bank!(data) do
    if data["bank_account"] == "" do
      data
    else
      qr =
        try do
          CozyCheckout.Payments.QrCode.generate_qr_data(%{
            account_number: data["bank_account"],
            amount: Decimal.new(1),
            variable_symbol: "1"
          })
        rescue
          _ -> fail("Neplatný český bankovní účet dodavatele")
        end

      account = qr |> String.split("*") |> Enum.find(&String.starts_with?(&1, "ACC:"))
      derived = String.replace_prefix(account, "ACC:", "")

      if not Regex.match?(~r/\ACZ\d{22}\z/, derived),
        do:
          fail(
            "Neplatný český bankovní účet: základní číslo smí mít nejvýše 10 číslic, předčíslí nejvýše 6 a kód banky 4"
          )

      entered = (data["iban"] || "") |> String.replace(" ", "") |> String.upcase()
      if entered != "" and entered != derived, do: fail("IBAN neodpovídá českému bankovnímu účtu")
      Map.put(data, "iban", derived)
    end
  end

  defp party_data(attrs),
    do: Map.new(@party_fields, fn key -> {key, String.trim(Map.get(attrs, key, ""))} end)

  def list_series, do: Repo.all(from s in Series, order_by: [desc: s.year, asc: s.kind])

  def save_series(attrs) do
    transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(821902)")
      changeset = Series.changeset(%Series{}, attrs)
      if not changeset.valid?, do: fail(changeset)
      data = Ecto.Changeset.apply_changes(changeset)
      existing = Repo.get_by(Series, kind: data.kind, year: data.year)

      if existing do
        # Prefix and width are immutable after the first document in this series/year.
        used =
          Repo.exists?(
            from d in Document,
              where:
                d.kind == ^data.kind and
                  fragment("EXTRACT(YEAR FROM ?)", d.issued_on) == ^data.year
          )

        if used, do: fail("Použitou řadu nelze měnit; založte řadu pro další rok")
        existing |> Series.changeset(attrs) |> Repo.update!()
      else
        case Repo.insert(changeset) do
          {:ok, row} -> row
          {:error, cs} -> fail(cs)
        end
      end
    end)
  end

  def create_calculation(booking_id) do
    transaction(fn ->
      lock_booking!(booking_id)
      calculation(booking_id) || create_calculation!(booking_id)
    end)
  end

  defp create_calculation!(booking_id) do
    booking = Bookings.get_booking!(booking_id)
    season = season_on(booking.check_in_date)

    invoice =
      %BookingInvoice{
        booking_id: booking_id,
        pricing_basis: "gross",
        priced_on: booking.check_in_date
      }
      |> Repo.insert!()

    Enum.with_index(@categories, 1)
    |> Enum.each(fn {{name, field}, position} ->
      %BookingInvoiceItem{booking_invoice_id: invoice.id}
      |> BookingInvoiceItem.changeset(%{
        name: name,
        quantity: if(position == 1, do: 2, else: 0),
        nights: max(BookingInvoice.calculate_nights(booking), 1),
        price_per_night: season && Map.fetch!(season, field),
        vat_rate: if(season, do: season.vat_rate, else: Decimal.new(12)),
        item_type: "person",
        position: position
      })
      |> Repo.insert!()
    end)

    recalculate!(invoice.id)
  end

  def recalculate_calculation(booking_id) do
    transaction(fn ->
      lock_booking!(booking_id)
      invoice = calculation(booking_id) || fail("Chybí kalkulace")
      recalculate!(invoice.id)
    end)
  end

  def calculation(booking_id), do: Bookings.get_invoice_by_booking_id(booking_id)

  def pricing_preview(booking_id) do
    booking = Bookings.get_booking!(booking_id)
    invoice = calculation(booking_id)
    season = season_on(booking.check_in_date)

    nights =
      if booking.check_out_date,
        do: Date.diff(booking.check_out_date, booking.check_in_date),
        else: 0

    preview = %{
      season: season,
      nights: nights,
      changed_date: invoice && invoice.priced_on != booking.check_in_date,
      changed_nights:
        invoice && Enum.any?(invoice.items, &(&1.item_type == "person" and &1.nights != nights)),
      rows:
        Enum.map(@categories, fn {name, field} ->
          old =
            if invoice,
              do: Enum.find(invoice.items, &(&1.name == name and &1.item_type == "person"))

          %{
            name: name,
            old: old && old.price_per_night,
            price: season && Map.fetch!(season, field),
            quantity: if(old, do: old.quantity, else: 0)
          }
        end)
    }

    Map.put(preview, :token, digest({preview, invoice}))
  end

  def apply_pricing(booking_id, expected_token \\ nil) do
    transaction(fn ->
      booking = lock_booking!(booking_id)
      preview = pricing_preview(booking_id)

      if expected_token && expected_token != preview.token,
        do: fail("Ceník nebo kalkulace se změnily. Zobrazte nový náhled")

      if is_nil(preview.season), do: fail("Pro příjezd chybí ceník")
      if preview.nights <= 0, do: fail("Doplňte odjezd po dni příjezdu")
      invoice = calculation(booking_id) || create_calculation!(booking.id)
      # Extras on a legacy net calculation retain their gross monetary value on conversion.
      if invoice.pricing_basis == "legacy_net" do
        Enum.each(invoice.items, fn item ->
          unless Enum.any?(@categories, fn {name, _} ->
                   item.name == name and item.item_type == "person"
                 end) do
            if item.price_per_night do
              gross =
                Decimal.mult(
                  item.price_per_night,
                  Decimal.add(1, Decimal.div(item.vat_rate, 100))
                )

              item |> Ecto.Changeset.change(price_per_night: Money.round(gross)) |> Repo.update!()
            end
          end
        end)
      end

      Enum.with_index(preview.rows, 1)
      |> Enum.each(fn {row, pos} ->
        item =
          Enum.find(invoice.items, &(&1.name == row.name and &1.item_type == "person")) ||
            %BookingInvoiceItem{booking_invoice_id: invoice.id}

        item
        |> BookingInvoiceItem.changeset(%{
          name: row.name,
          quantity: row.quantity,
          nights: preview.nights,
          price_per_night: row.price,
          vat_rate: preview.season.vat_rate,
          item_type: "person",
          tax_mode: "taxable",
          position: pos
        })
        |> Repo.insert_or_update!()
      end)

      invoice
      |> Ecto.Changeset.change(pricing_basis: "gross", priced_on: booking.check_in_date)
      |> Repo.update!()

      recalculate!(invoice.id)
    end)
  end

  def save_item(booking_id, attrs, id \\ nil) do
    transaction(fn ->
      lock_booking!(booking_id)
      invoice = calculation(booking_id) || create_calculation!(booking_id)

      item =
        if id,
          do: Repo.get_by!(BookingInvoiceItem, id: id, booking_invoice_id: invoice.id),
          else: %BookingInvoiceItem{booking_invoice_id: invoice.id}

      case item |> BookingInvoiceItem.changeset(attrs) |> Repo.insert_or_update() do
        {:ok, _} -> recalculate!(invoice.id)
        {:error, cs} -> fail(cs)
      end
    end)
  end

  @calculation_item_fields ~w(name quantity nights price_per_night vat_rate item_type tax_mode position)a

  @doc "Version of the editable calculation; checked under the booking lock on batch save."
  def calculation_version(invoice) do
    {invoice.pricing_basis, invoice.priced_on, invoice.state,
     invoice.items
     |> Enum.sort_by(& &1.id)
     |> Enum.map(&Map.take(&1, [:id | @calculation_item_fields]))}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  @doc "Atomically saves a complete calculation editor batch, including additions and removals."
  def save_calculation_items(booking_id, rows, version) do
    transaction(fn ->
      lock_booking!(booking_id)
      invoice = calculation(booking_id) || fail("Chybí kalkulace")

      if calculation_version(invoice) != version,
        do:
          fail(
            "Kalkulace se mezitím změnila. Vaše úpravy zůstaly zachované. Pro načtení aktuální kalkulace použijte Zahodit změny a zadejte úpravy znovu."
          )

      for row <- rows do
        item =
          if row.id,
            do:
              Enum.find(invoice.items, &(&1.id == row.id)) ||
                fail("Položka nepatří k této kalkulaci"),
            else: %BookingInvoiceItem{booking_invoice_id: invoice.id}

        if row.delete do
          if item.id, do: Repo.delete!(item)
        else
          attrs = Map.take(row.attrs, Enum.map(@calculation_item_fields, &Atom.to_string/1))

          case item |> BookingInvoiceItem.changeset(attrs) |> Repo.insert_or_update() do
            {:ok, _} -> :ok
            {:error, cs} -> fail(cs)
          end
        end
      end

      recalculate!(invoice.id)
    end)
  end

  def set_personal(booking_id, personal? \\ true) do
    transaction(fn ->
      lock_booking!(booking_id)

      if Repo.exists?(from d in Document, where: d.booking_id == ^booking_id),
        do: fail("Pobyt má vystavené doklady")

      invoice = calculation(booking_id) || fail("Chybí kalkulace")

      invoice
      |> Ecto.Changeset.change(state: if(personal?, do: "personal", else: "draft"))
      |> Repo.update!()
    end)
  end

  def delete_item(booking_id, id) do
    transaction(fn ->
      lock_booking!(booking_id)
      invoice = calculation(booking_id) || fail("Chybí kalkulace")
      Repo.get_by!(BookingInvoiceItem, id: id, booking_invoice_id: invoice.id) |> Repo.delete!()
      recalculate!(invoice.id)
    end)
  end

  defp recalculate!(id) do
    invoice = Bookings.get_booking_invoice!(id)

    totals =
      Enum.map(invoice.items, fn item ->
        if item.price_per_night do
          line =
            Money.line(
              item.name,
              item.quantity,
              item.nights,
              item.price_per_night,
              item.vat_rate,
              item.tax_mode,
              invoice.pricing_basis
            )

          item
          |> Ecto.Changeset.change(
            subtotal: Money.value(line, "net"),
            vat_amount: Money.value(line, "vat"),
            total: Money.value(line, "gross")
          )
          |> Repo.update!()

          line
        else
          item
          |> Ecto.Changeset.change(subtotal: nil, vat_amount: nil, total: nil)
          |> Repo.update!()

          nil
        end
      end)

    complete =
      Enum.zip(invoice.items, totals)
      |> Enum.all?(fn {item, line} -> line != nil or item.quantity == 0 end)

    totals = Enum.reject(totals, &is_nil/1)

    invoice
    |> Ecto.Changeset.change(
      subtotal: if(complete, do: Money.sum(Enum.map(totals, &Money.value(&1, "net")))),
      vat_amount: if(complete, do: Money.sum(Enum.map(totals, &Money.value(&1, "vat")))),
      total_price: if(complete, do: Money.total(totals))
    )
    |> Repo.update!()

    calculation(invoice.booking_id)
  end

  def list_documents(filters \\ %{}) do
    query =
      from d in Document,
        order_by: [desc: d.inserted_at, desc: d.id],
        select: map(d, ^document_fields())

    query =
      if filters["booking_id"] not in [nil, ""],
        do: where(query, [d], d.booking_id == ^filters["booking_id"]),
        else: query

    query =
      if filters["kind"] not in [nil, ""],
        do: where(query, [d], d.kind == ^filters["kind"]),
        else: query

    query =
      if filters["number"] not in [nil, ""],
        do: where(query, [d], ilike(d.number, ^("%" <> filters["number"] <> "%"))),
        else: query

    Repo.all(query)
  end

  defp document_fields,
    do: [
      :id,
      :booking_id,
      :kind,
      :number,
      :variable_symbol,
      :parent_id,
      :issued_on,
      :tax_date,
      :due_on,
      :snapshot,
      :lines,
      :total,
      :inserted_at,
      :request_id
    ]

  def get_document!(id), do: Repo.get!(Document, id)

  def list_payments(booking_id),
    do:
      Repo.all(
        from p in Payment,
          where: p.booking_id == ^booking_id,
          order_by: [asc: p.paid_on, asc: p.inserted_at]
      )

  def list_deliveries(id),
    do: Repo.all(from d in Delivery, where: d.document_id == ^id, order_by: [desc: d.inserted_at])

  def final_document(booking_id),
    do: Repo.one(from d in Document, where: d.booking_id == ^booking_id and d.kind == "final")

  def balance(booking_id) do
    payments = list_payments(booking_id)

    received =
      payments
      |> Enum.map(fn p -> if p.kind == "refund", do: Decimal.negate(p.amount), else: p.amount end)
      |> Money.sum()

    final = final_document(booking_id)

    total =
      if final,
        do: adjusted_total(final),
        else: (calculation(booking_id) || %{}) |> Map.get(:total_price)

    %{received: received, total: total, outstanding: if(total, do: Decimal.sub(total, received))}
  end

  def payment_state(%{outstanding: nil}), do: "Chybí kalkulace"

  def payment_state(%{outstanding: outstanding, received: received}) do
    cond do
      Decimal.lt?(outstanding, 0) -> "Přeplatek"
      Decimal.equal?(outstanding, 0) -> "Uhrazeno"
      Decimal.gt?(received, 0) -> "Částečně uhrazeno"
      true -> "Neuhrazeno"
    end
  end

  def adjusted_lines(doc) do
    corrections =
      Repo.all(from d in Document, where: d.parent_id == ^doc.id and d.kind == "correction")

    doc.lines ++ Enum.flat_map(corrections, & &1.lines)
  end

  def adjusted_total(doc), do: Money.total(adjusted_lines(doc))

  def preview(booking_id, kind, attrs \\ %{}) do
    transaction(fn ->
      lock_booking!(booking_id)
      if kind not in ["advance", "final"], do: fail("Nepodporovaný druh dokladu")
      build_preview!(booking_id, kind, attrs)
    end)
  end

  defp build_preview!(booking_id, kind, attrs) do
    booking = Bookings.get_booking!(booking_id)

    if booking.deleted_at || booking.status == "cancelled",
      do: fail("Rezervace je zrušená nebo odstraněná")

    if is_nil(booking.check_out_date) ||
         Date.compare(booking.check_out_date, booking.check_in_date) != :gt,
       do: fail("Doplňte platný konec pobytu")

    invoice = calculation(booking_id) || fail("Nejdříve doplňte kalkulaci")
    if invoice.state == "personal", do: fail("Osobní pobyt nevystavuje doklady")
    supplier = profile().data
    buyer = customer(booking_id).data
    validate_party!(supplier, true)
    validate_party!(buyer, false)
    if invoice.items == [], do: fail("Kalkulace nemá položky")

    lines =
      invoice.items
      |> Enum.filter(&(&1.quantity > 0))
      |> Enum.map(fn item ->
        if is_nil(item.price_per_night), do: fail("Chybí cena položky #{item.name}")

        Money.line(
          item.name,
          item.quantity,
          item.nights,
          item.price_per_night,
          item.vat_rate,
          item.tax_mode,
          invoice.pricing_basis
        )
      end)

    if not Decimal.gt?(Money.total(lines), 0), do: fail("Cena pobytu musí být kladná")

    due_days =
      case Integer.parse(supplier["due_days"] || "14") do
        {n, ""} -> n
        _ -> 14
      end

    tax_date = parse_date!(attrs["tax_date"] || Date.to_iso8601(booking.check_out_date))
    due_on = parse_date!(attrs["due_on"] || Date.to_iso8601(Date.add(today(), due_days)))

    snapshot = %{
      "supplier" => supplier,
      "customer" => buyer,
      "check_in" => to_string(booking.check_in_date),
      "check_out" => to_string(booking.check_out_date),
      "currency" => "CZK"
    }

    {lines, deductions, snapshot} =
      case kind do
        type when type in ["advance", "tax_receipt"] ->
          if final_document(booking_id), do: fail("Vyúčtování již existuje")

          explicit_amount? = attrs["amount"] not in [nil, ""]
          percent = if not explicit_amount?, do: parse_money!(attrs["percent"] || "50")

          amount =
            if explicit_amount?,
              do: parse_money!(attrs["amount"]),
              else:
                Money.round(
                  Decimal.mult(
                    Money.total(lines),
                    Decimal.div(percent, 100)
                  )
                )

          if not Decimal.gt?(amount, 0) ||
               (kind == "advance" and Decimal.gt?(amount, Money.total(lines))),
             do: fail("Záloha musí být kladná a nejvýše cena pobytu")

          snapshot =
            if kind == "advance" do
              Map.put(snapshot, "advance_calculation", %{
                "method" => if(explicit_amount?, do: "amount", else: "percent"),
                "percent" => if(percent, do: to_string(percent)),
                "amount" => to_string(amount),
                "stay_total" => to_string(Money.total(lines)),
                "lines" => lines
              })
            else
              snapshot
            end

          {Money.allocate(lines, amount), [], snapshot}

        "final" ->
          if Date.compare(tax_date, today()) == :gt,
            do: fail("DUZP konečné faktury nesmí být v budoucnu")

          if final_document(booking_id), do: fail("Konečná faktura už existuje")

          if Repo.exists?(
               from d in Document,
                 where:
                   d.booking_id == ^booking_id and d.kind == "tax_receipt" and
                     d.tax_date > ^tax_date
             ),
             do: fail("DUZP nesmí předcházet přijatým zálohám")

          # Previously taxed advances are deductions, never a second incoming payment.
          receipts =
            Repo.all(
              from d in Document,
                where: d.booking_id == ^booking_id and d.kind == "tax_receipt",
                order_by: d.inserted_at
            )

          deductions =
            Enum.flat_map(receipts, fn doc ->
              adjusted_lines(doc)
              |> Money.groups()
              |> Enum.map(
                &(&1
                  |> Money.negate("Odpočet zálohy #{doc.number}")
                  |> Map.put("source_document_id", doc.id))
              )
            end)

          {lines, deductions, snapshot}

        _ ->
          fail("Nepodporovaný druh dokladu")
      end

    result = %{
      booking_id: booking_id,
      kind: kind,
      issued_on: today(),
      tax_date: tax_date,
      due_on: due_on,
      snapshot: Map.put(snapshot, "deductions", deductions),
      lines: lines,
      total: Money.total(lines)
    }

    Map.put(result, :token, digest(result))
  end

  def issue(booking_id, kind, attrs, request_id) do
    transaction(fn ->
      lock_booking!(booking_id)
      validate_request!(request_id)
      if kind not in ["advance", "final"], do: fail("Nepodporovaný druh dokladu")

      case Repo.get_by(Document, request_id: request_id) do
        %Document{booking_id: ^booking_id, kind: ^kind} = existing ->
          existing

        nil ->
          data = build_preview!(booking_id, kind, attrs)

          if attrs["preview_token"] != data.token,
            do: fail("Podklady se změnily. Zobrazte znovu náhled")

          insert_document!(Map.delete(data, :token), request_id)

        _ ->
          fail("Požadavek již byl použit")
      end
    end)
  end

  @doc "Preview the ZDD that an explicitly confirmed bank advance will issue."
  def preview_advance_payment(booking_id, amount, paid_on) do
    transaction(fn ->
      booking = lock_booking!(booking_id)
      advance_payment_preview!(booking, Money.decimal(amount), paid_on)
    end)
  end

  defp advance_payment_preview!(booking, amount, paid_on) do
    if final_document(booking.id),
      do: fail("Vyúčtování již existuje; příjem nelze potvrdit jako zálohu")

    if Date.compare(paid_on, today()) == :gt, do: fail("Platba nemůže být v budoucnu")

    if Date.compare(paid_on, booking.check_out_date || paid_on) != :lt,
      do: fail("Pro platbu při dokončení pobytu nejprve vystavte konečnou fakturu")

    data =
      build_preview!(booking.id, "tax_receipt", %{"amount" => to_string(amount)})
      |> Map.put(:tax_date, paid_on)
      |> Map.put(:due_on, paid_on)
      |> Map.delete(:token)

    Map.put(data, :token, digest(data))
  end

  def record_payment(booking_id, attrs) do
    transaction(fn ->
      booking = lock_booking!(booking_id)
      validate_request!(attrs["request_id"])

      case Repo.get_by(Payment, request_id: attrs["request_id"]) do
        %Payment{booking_id: ^booking_id} = existing ->
          existing

        nil ->
          cs = Payment.changeset(%Payment{booking_id: booking_id}, attrs)
          if not cs.valid?, do: fail(cs)
          payment = Ecto.Changeset.apply_changes(cs)

          if Decimal.compare(payment.amount, Money.round(payment.amount)) != :eq,
            do: fail("Platba musí být v celých haléřích")

          if Date.compare(payment.paid_on, today()) == :gt,
            do: fail("Platba nemůže být v budoucnu")

          linked =
            if payment.document_id,
              do:
                Repo.get_by(Document, id: payment.document_id, booking_id: booking_id) ||
                  fail("Doklad nepatří této rezervaci")

          if linked && linked.kind not in ["advance", "final", "correction"],
            do: fail("Platbu přiřaďte výzvě, faktuře nebo opravě")

          if payment.kind == "refund" do
            validate_refund!(booking_id, payment)
            Repo.insert!(cs)
          else
            final = final_document(booking_id)

            if final && Date.compare(payment.paid_on, final.tax_date) == :lt,
              do:
                fail(
                  "Platba před DUZP patří mezi zálohy. Vyúčtování je nutné nejprve opravit; platbu nelze zaevidovat jako doplatek"
                )

            if final && linked && linked.kind != "final",
              do: fail("Po vyúčtování přiřaďte příjem konečné faktuře")

            if is_nil(final) &&
                 Date.compare(payment.paid_on, booking.check_out_date || payment.paid_on) != :lt,
               do: fail("Pro platbu při dokončení pobytu nejprve vystavte konečnou fakturu")

            payment =
              Repo.insert!(
                Ecto.Changeset.put_change(
                  cs,
                  :document_id,
                  if(final, do: final.id, else: payment.document_id)
                )
              )

            if final do
              payment
            else
              preview =
                advance_payment_preview!(booking, payment.amount, payment.paid_on)

              # Overpayments are accepted and taxed too, even above the expected stay price.
              tax_doc =
                preview
                |> Map.delete(:token)
                |> Map.merge(%{
                  kind: "tax_receipt",
                  tax_date: payment.paid_on,
                  due_on: payment.paid_on,
                  parent_id: payment.document_id
                })
                |> insert_document!(Ecto.UUID.generate())

              payment |> Ecto.Changeset.change(tax_document_id: tax_doc.id) |> Repo.update!()
            end
          end

        _ ->
          fail("Požadavek již byl použit")
      end
    end)
  end

  defp validate_refund!(booking_id, payment) do
    balance = balance(booking_id)
    if Decimal.gt?(payment.amount, balance.received), do: fail("Vratka převyšuje přijaté peníze")
    final = final_document(booking_id)

    available =
      if final do
        Decimal.max(Decimal.sub(balance.received, adjusted_total(final)), 0)
      else
        taxed =
          Repo.all(
            from d in Document, where: d.booking_id == ^booking_id and d.kind == "tax_receipt"
          )
          |> Enum.map(&adjusted_total/1)
          |> Money.sum()

        Decimal.max(Decimal.sub(balance.received, taxed), 0)
      end

    if Decimal.gt?(payment.amount, available),
      do: fail("Nejprve vystavte opravný doklad pro vracenou zálohu nebo fakturu")
  end

  def correct(document_id, attrs, request_id) do
    transaction(fn ->
      original = get_document!(document_id)
      lock_booking!(original.booking_id)
      validate_request!(request_id)

      case Repo.get_by(Document, request_id: request_id) do
        %Document{parent_id: ^document_id, kind: "correction"} = existing ->
          existing

        nil ->
          if original.kind not in ["final", "tax_receipt"],
            do: fail("Opravit lze fakturu nebo doklad k přijaté platbě")

          if original.kind == "tax_receipt" && final_document(original.booking_id),
            do: fail("Po vyúčtování opravujte konečnou fakturu")

          reason = String.trim(attrs["reason"] || "")
          if reason == "", do: fail("Uveďte důvod opravy")
          amount = parse_money!(attrs["amount"])
          available_lines = adjusted_lines(original)

          if not Decimal.gt?(amount, 0) ||
               (attrs["direction"] != "increase" and
                  Decimal.gt?(amount, Money.total(available_lines))),
             do: fail("Oprava převyšuje zbývající hodnotu dokladu")

          direction = attrs["direction"] || "decrease"
          if direction not in ["decrease", "increase"], do: fail("Neplatný směr opravy")

          lines =
            if direction == "increase",
              do:
                Money.allocate(original.lines, amount)
                |> Enum.map(&Map.put(&1, "name", "Oprava: zvýšení ceny")),
              else: Money.credit(available_lines, amount)

          data = %{
            booking_id: original.booking_id,
            kind: "correction",
            parent_id: original.id,
            issued_on: today(),
            tax_date: parse_date!(attrs["tax_date"] || to_string(today())),
            due_on: today(),
            lines: lines,
            snapshot:
              original.snapshot
              |> Map.put("reason", reason)
              |> Map.put("original_number", original.number)
              |> Map.put("deductions", []),
            total: Money.total(lines)
          }

          insert_document!(data, request_id)

        _ ->
          fail("Požadavek již byl použit")
      end
    end)
  end

  defp validate_party!(data, supplier?) do
    fields =
      if supplier?,
        do: ~w(name street city postcode country company_id vat_id registry bank_account),
        else: ~w(name)

    missing = Enum.filter(fields, &(String.trim(data[&1] || "") == ""))

    if missing != [],
      do:
        fail(
          "Doplňte #{if supplier?, do: "dodavatele", else: "odběratele"}: #{Enum.map_join(missing, ", ", &Map.get(%{"name" => "název/jméno", "street" => "ulice a číslo", "city" => "město", "postcode" => "PSČ", "country" => "země", "company_id" => "IČO", "vat_id" => "DIČ", "registry" => "zápis v rejstříku", "bank_account" => "bankovní účet"}, &1, &1))}"
        )

    if supplier? do
      try do
        qr =
          CozyCheckout.Payments.QrCode.generate_qr_data(%{
            account_number: data["bank_account"],
            amount: Decimal.new(1),
            variable_symbol: "1"
          })

        if not Regex.match?(~r/\*ACC:CZ\d{22}\*/, qr),
          do: fail("Neplatný český bankovní účet dodavatele")
      rescue
        _ -> fail("Neplatný český bankovní účet dodavatele")
      end
    end
  end

  defp insert_document!(data, request_id) do
    configured = Repo.aggregate(from(s in Series, where: s.year == ^today().year), :count)

    if configured != 4,
      do: fail("Před prvním vystavením nastavte všechny čtyři číselné řady pro aktuální rok")

    series =
      Repo.one(
        from s in Series,
          where: s.kind == ^data.kind and s.year == ^today().year,
          lock: "FOR UPDATE"
      ) || fail("Nejdříve nastavte číselnou řadu #{kind_label(data.kind)} pro aktuální rok")

    if String.length(to_string(series.next_number)) > series.digits,
      do: fail("Číselná řada je vyčerpaná")

    if series.next_number > 99_999,
      do:
        fail(
          "Číselná řada je vyčerpaná: variabilní symbol dovoluje nejvýše 99 999 dokladů za rok a druh"
        )

    number =
      series.prefix <>
        to_string(series.year) <>
        String.pad_leading(to_string(series.next_number), series.digits, "0")

    if Repo.exists?(from d in Document, where: d.number == ^number),
      do: fail("Číslo koliduje s jinou řadou")

    symbol =
      Map.fetch!(@variable_symbol_codes, series.kind) <>
        to_string(series.year) <>
        String.pad_leading(to_string(series.next_number), 5, "0")

    if Repo.exists?(from d in Document, where: d.variable_symbol == ^symbol),
      do: fail("Variabilní symbol koliduje s již vystaveným dokladem")

    series |> Ecto.Changeset.change(next_number: series.next_number + 1) |> Repo.update!()

    doc =
      struct!(
        Document,
        Map.merge(data, %{request_id: request_id, number: number, variable_symbol: symbol})
      )
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:number)
      |> Ecto.Changeset.unique_constraint(:variable_symbol)
      |> Ecto.Changeset.unique_constraint(:request_id)
      |> Ecto.Changeset.unique_constraint(:booking_id, name: :billing_one_final)
      |> Repo.insert()
      |> case do
        {:ok, doc} -> doc
        {:error, changeset} -> fail(changeset)
      end

    {:ok, _} =
      %{document_id: doc.id} |> CozyCheckout.Workers.BillingPdfWorker.new() |> Oban.insert()

    :ok = CozyCheckout.Abra.Accommodation.enqueue_issued(doc)
    doc
  end

  def enqueue_email(document_id, attrs, request_id) do
    transaction(fn ->
      document = get_document!(document_id)
      lock_booking!(document.booking_id)
      validate_request!(request_id)

      if attrs["consent"] != "true",
        do: fail("Potvrďte souhlas odběratele s elektronickou podobou dokladu")

      case Repo.get_by(Delivery, request_id: request_id) do
        %Delivery{document_id: ^document_id} = existing ->
          existing

        nil ->
          cs =
            Delivery.changeset(
              %Delivery{document_id: document_id},
              Map.merge(attrs, %{
                "request_id" => request_id,
                "consented_at" => DateTime.utc_now() |> DateTime.truncate(:second)
              })
            )

          delivery =
            case Repo.insert(cs) do
              {:ok, row} -> row
              {:error, cs} -> fail(cs)
            end

          {:ok, _} =
            %{delivery_id: delivery.id}
            |> CozyCheckout.Workers.BillingEmailWorker.new()
            |> Oban.insert()

          delivery

        _ ->
          fail("Požadavek již byl použit")
      end
    end)
  end

  def ensure_pdf(document_id) do
    # Browser startup can be slow on a workstation. Never hold a database
    # connection or row lock while Chrome is starting or rendering.
    doc = get_document!(document_id)

    if doc.pdf do
      {:ok, doc}
    else
      case CozyCheckout.Billing.Pdf.render(doc) do
        {:ok, bytes} ->
          transaction(fn ->
            current =
              Repo.one!(from d in Document, where: d.id == ^document_id, lock: "FOR UPDATE")

            if current.pdf do
              current
            else
              current
              |> Ecto.Changeset.change(
                pdf: bytes,
                pdf_sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
              )
              |> Repo.update!()
            end
          end)

        {:error, reason} ->
          require Logger
          Logger.warning("Billing PDF #{document_id} failed: #{reason}")
          {:error, reason}
      end
    end
  end

  defp lock_booking!(id), do: Repo.one!(from b in Booking, where: b.id == ^id, lock: "FOR UPDATE")

  defp digest(data),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(data)) |> Base.encode16(case: :lower)

  defp validate_request!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> :ok
      _ -> fail("Neplatný identifikátor požadavku")
    end
  end

  defp parse_date!(date) do
    case Date.from_iso8601(date) do
      {:ok, value} -> value
      _ -> fail("Neplatné datum")
    end
  end

  defp parse_money!(value) do
    text = to_string(value || "")

    if not Regex.match?(~r/\A\d{1,10}(?:\.\d{1,2})?\z/, text),
      do: fail("Zadejte částku s nejvýše dvěma desetinnými místy")

    Decimal.new(text)
  end

  defp transaction(fun), do: Repo.transaction(fun)
  defp fail(reason), do: Repo.rollback(reason)
end
