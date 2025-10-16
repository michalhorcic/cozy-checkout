# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     CozyCheckout.Repo.insert!(%CozyCheckout.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query
alias CozyCheckout.Repo
alias CozyCheckout.Catalog.{Category, Product, Pricelist}
alias CozyCheckout.Guests.Guest
alias CozyCheckout.Sales.{Order, OrderItem, Payment}

# Helper functions
defmodule SeedHelper do
  def random_date_in_range(days_ago, days_ahead \\ 0) do
    today = Date.utc_today()
    offset = :rand.uniform(days_ago + days_ahead) - days_ago
    Date.add(today, offset)
  end

  def random_decimal(min, max) do
    value = min + :rand.uniform() * (max - min)
    Decimal.from_float(value) |> Decimal.round(2)
  end

  def random_datetime_in_range(days_ago) do
    today = DateTime.utc_now()
    offset_seconds = if days_ago > 0, do: :rand.uniform(days_ago * 24 * 60 * 60), else: 0
    DateTime.add(today, -offset_seconds, :second) |> DateTime.truncate(:second)
  end

  def random_element(list) do
    Enum.random(list)
  end

  def generate_invoice_number(order_date, counter) do
    date_string = Date.to_string(order_date) |> String.replace("-", "")
    sequence = String.pad_leading(Integer.to_string(counter), 4, "0")
    "PAY-#{date_string}-#{sequence}"
  end
end

# Clear existing data (optional - comment out if you want to preserve existing data)
IO.puts("Clearing existing data...")
Repo.delete_all(Payment)
Repo.delete_all(OrderItem)
Repo.delete_all(Order)
Repo.delete_all(Pricelist)
Repo.delete_all(Product)
Repo.delete_all(Category)
Repo.delete_all(Guest)

IO.puts("Creating categories...")

# Create 15 categories
category_data = [
  {"Beer", "Various types of beer"},
  {"Wine", "Red, white, and rosé wines"},
  {"Spirits", "Hard liquor and spirits"},
  {"Soft Drinks", "Non-alcoholic beverages"},
  {"Coffee & Tea", "Hot beverages"},
  {"Snacks", "Chips, nuts, and small snacks"},
  {"Desserts", "Sweet treats and desserts"},
  {"Sandwiches", "Prepared sandwiches"},
  {"Hot Food", "Warm meals and dishes"},
  {"Energy Drinks", "Energy and sports drinks"},
  {"Juices", "Fresh and bottled juices"},
  {"Water", "Still and sparkling water"},
  {"Cocktails", "Mixed drinks and cocktails"},
  {"Local Specialties", "Regional products"},
  {"Ice Cream", "Ice cream and frozen treats"}
]

categories =
  Enum.map(category_data, fn {name, description} ->
    Repo.insert!(%Category{
      name: name,
      description: description
    })
  end)

IO.puts("Created #{length(categories)} categories")

IO.puts("Creating products...")

# Create 200 products
product_templates = [
  # Beer products
  {"Pilsner Urquell", "ml", "[300, 500]"},
  {"Budweiser Budvar", "ml", "[300, 500]"},
  {"Staropramen", "ml", "[300, 500]"},
  {"Kozel Dark", "ml", "[300, 500]"},
  {"Radegast", "ml", "[300, 500]"},
  {"Bernard", "ml", "[330, 500]"},
  {"Krušovice", "ml", "[330, 500]"},
  {"Gambrinus", "ml", "[500]"},
  # Wine products
  {"Chardonnay", "ml", "[150, 750]"},
  {"Merlot", "ml", "[150, 750]"},
  {"Cabernet Sauvignon", "ml", "[150, 750]"},
  {"Riesling", "ml", "[150, 750]"},
  {"Pinot Noir", "ml", "[150, 750]"},
  {"Sauvignon Blanc", "ml", "[150, 750]"},
  # Spirits
  {"Becherovka", "ml", "[40, 500]"},
  {"Slivovice", "ml", "[40, 500]"},
  {"Vodka", "ml", "[40, 500]"},
  {"Rum", "ml", "[40, 500]"},
  {"Whiskey", "ml", "[40, 500]"},
  {"Gin", "ml", "[40, 500]"},
  # Soft Drinks
  {"Coca-Cola", "ml", "[250, 330, 500]"},
  {"Sprite", "ml", "[250, 330, 500]"},
  {"Fanta", "ml", "[250, 330, 500]"},
  {"Tonic Water", "ml", "[250, 500]"},
  {"Ginger Ale", "ml", "[250, 500]"},
  # Coffee & Tea
  {"Espresso", "ml", "[30, 60]"},
  {"Cappuccino", "ml", "[200, 300]"},
  {"Latte", "ml", "[250, 400]"},
  {"Black Tea", "ml", "[250, 400]"},
  {"Green Tea", "ml", "[250, 400]"},
  {"Herbal Tea", "ml", "[250, 400]"},
  # Snacks
  {"Potato Chips", "g", "[50, 100, 150]"},
  {"Peanuts", "g", "[100, 200]"},
  {"Cashews", "g", "[100, 200]"},
  {"Mixed Nuts", "g", "[100, 200]"},
  {"Pretzels", "g", "[50, 100]"},
  {"Popcorn", "g", "[100, 200]"},
  # Others without units
  {"Club Sandwich", nil, nil},
  {"Ham Sandwich", nil, nil},
  {"Cheese Sandwich", nil, nil},
  {"Goulash", nil, nil},
  {"Chicken Soup", nil, nil}
]

products =
  Enum.flat_map(1..5, fn variation ->
    Enum.map(product_templates, fn {name, unit, amounts} ->
      category = SeedHelper.random_element(categories)
      suffix = if variation > 1, do: " #{variation}", else: ""

      Repo.insert!(%Product{
        name: "#{name}#{suffix}",
        description: "High quality #{name}",
        category_id: category.id,
        active: :rand.uniform() > 0.1,
        unit: unit,
        default_unit_amounts: amounts
      })
    end)
  end)

IO.puts("Created #{length(products)} products")

IO.puts("Creating pricelists...")

# Create pricelists for all products (300+ pricelists)
pricelists =
  Enum.flat_map(products, fn product ->
    # Most products have 1-2 pricelists, some have historical prices
    num_pricelists = if :rand.uniform() > 0.8, do: 2, else: 1

    Enum.map(1..num_pricelists, fn idx ->
      valid_from = SeedHelper.random_date_in_range(180, 0)
      price = SeedHelper.random_decimal(20, 500)
      vat_rate = SeedHelper.random_element([Decimal.new("15"), Decimal.new("21")])

      Repo.insert!(%Pricelist{
        product_id: product.id,
        price: price,
        vat_rate: vat_rate,
        valid_from: valid_from,
        valid_to: if(idx > 1, do: Date.add(valid_from, 90), else: nil),
        active: idx == 1
      })
    end)
  end)

IO.puts("Created #{length(pricelists)} pricelists")

IO.puts("Creating guests...")

# Create 300 guests - make sure many are for today's date
first_names = [
  "Jan",
  "Petr",
  "Pavel",
  "Josef",
  "Martin",
  "Tomáš",
  "Jakub",
  "Lukáš",
  "David",
  "Michal",
  "Anna",
  "Eva",
  "Marie",
  "Hana",
  "Jana",
  "Petra",
  "Lucie",
  "Kateřina",
  "Veronika",
  "Tereza",
  "John",
  "Michael",
  "James",
  "Robert",
  "William",
  "Sarah",
  "Emma",
  "Olivia",
  "Emily",
  "Sophie"
]

last_names = [
  "Novák",
  "Svoboda",
  "Novotný",
  "Dvořák",
  "Černý",
  "Procházka",
  "Kučera",
  "Veselý",
  "Horák",
  "Němec",
  "Smith",
  "Johnson",
  "Williams",
  "Brown",
  "Jones",
  "García",
  "Müller",
  "Schmidt",
  "Schneider",
  "Fischer"
]

today = Date.utc_today()

guests =
  Enum.map(1..300, fn i ->
    # 40% of guests check in today, 30% checked in recently, 30% historical
    {check_in, check_out} =
      cond do
        i <= 120 ->
          # Guests checking in today
          {today, Date.add(today, :rand.uniform(7))}

        i <= 210 ->
          # Guests checked in recently (last 7 days)
          days_ago = :rand.uniform(7)
          check_in = Date.add(today, -days_ago)
          {check_in, Date.add(check_in, :rand.uniform(7) + days_ago)}

        true ->
          # Historical guests
          check_in = SeedHelper.random_date_in_range(180, 0)
          {check_in, Date.add(check_in, :rand.uniform(14))}
      end

    Repo.insert!(%Guest{
      name:
        "#{SeedHelper.random_element(first_names)} #{SeedHelper.random_element(last_names)}",
      room_number: "#{:rand.uniform(50)}#{SeedHelper.random_element(["A", "B", ""])}",
      phone: "+420#{:rand.uniform(900_000_000) + 100_000_000}",
      notes: if(:rand.uniform() > 0.7, do: "VIP guest", else: nil),
      check_in_date: check_in,
      check_out_date: check_out
    })
  end)

IO.puts("Created #{length(guests)} guests")

IO.puts("Creating orders...")

# Create 500 orders - ensure many are for today
orders =
  Enum.flat_map(guests, fn guest ->
    # Most active guests (checked in today) have 1-3 orders
    # Recent guests have 1-2 orders
    # Historical guests have 0-2 orders
    num_orders =
      cond do
        Date.compare(guest.check_in_date, today) == :eq ->
          :rand.uniform(3)

        Date.diff(today, guest.check_in_date) <= 7 ->
          :rand.uniform(2)

        true ->
          if(:rand.uniform() > 0.3, do: :rand.uniform(2), else: 0)
      end

    Enum.map(1..num_orders, fn _order_idx ->
      # Generate order date between check-in and check-out or today
      order_date =
        if Date.compare(guest.check_in_date, today) == :eq or
             Date.compare(guest.check_in_date, today) == :gt do
          today
        else
          max_days = min(Date.diff(today, guest.check_in_date), 30)
          Date.add(guest.check_in_date, :rand.uniform(max(max_days, 1)))
        end

      order_datetime = SeedHelper.random_datetime_in_range(Date.diff(today, order_date))

      # Determine order status (70% paid, 20% partially paid, 10% open)
      status =
        case :rand.uniform(10) do
          n when n <= 7 -> "paid"
          n when n <= 9 -> "partially_paid"
          _ -> "open"
        end

      # Generate unique order number
      order_number =
        "ORD-#{Date.to_string(order_date) |> String.replace("-", "")}-#{String.pad_leading(Integer.to_string(:rand.uniform(9999)), 4, "0")}-#{guest.id |> String.slice(0..7)}"

      Repo.insert!(%Order{
        guest_id: guest.id,
        order_number: order_number,
        status: status,
        total_amount: Decimal.new("0"),
        discount_amount: if(:rand.uniform() > 0.8, do: SeedHelper.random_decimal(10, 100), else: Decimal.new("0")),
        notes: if(:rand.uniform() > 0.8, do: "Special request", else: nil),
        inserted_at: order_datetime,
        updated_at: order_datetime
      })
    end)
  end)

IO.puts("Created #{length(orders)} orders")

IO.puts("Creating order items...")

# Create 2000+ order items (multiple items per order)
order_items =
  Enum.flat_map(orders, fn order ->
    # Each order has 1-8 items
    num_items = :rand.uniform(8)

    items =
      Enum.map(1..num_items, fn _ ->
        product = SeedHelper.random_element(products)

        # Get an active pricelist for this product
        pricelist =
          Repo.one(
            from p in Pricelist,
              where: p.product_id == ^product.id and p.active == true,
              limit: 1
          )

        unit_price = pricelist.price
        vat_rate = pricelist.vat_rate
        quantity = :rand.uniform(5)

        # Calculate unit_amount if product has units
        unit_amount =
          if product.unit && product.default_unit_amounts do
            amounts =
              product.default_unit_amounts
              |> Jason.decode!()
              |> Enum.map(&Decimal.new/1)

            SeedHelper.random_element(amounts)
          else
            nil
          end

        subtotal =
          unit_price
          |> Decimal.mult(quantity)
          |> Decimal.mult(Decimal.add(Decimal.new("1"), Decimal.div(vat_rate, Decimal.new("100"))))
          |> Decimal.round(2)

        Repo.insert!(%OrderItem{
          order_id: order.id,
          product_id: product.id,
          quantity: quantity,
          unit_price: unit_price,
          unit_amount: unit_amount,
          vat_rate: vat_rate,
          subtotal: subtotal,
          inserted_at: order.inserted_at,
          updated_at: order.updated_at
        })
      end)

    # Update order total
    total =
      items
      |> Enum.map(& &1.subtotal)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    total_with_discount = Decimal.sub(total, order.discount_amount)

    Repo.update!(
      Ecto.Changeset.change(order,
        total_amount: total_with_discount,
        updated_at: order.updated_at
      )
    )

    items
  end)

IO.puts("Created #{length(order_items)} order items")

# Create payments for paid and partially_paid orders
IO.puts("Creating payments...")
# Track invoice counter per date
invoice_counters = %{}

{payments, _final_counters} = Enum.flat_map_reduce(orders, invoice_counters, fn order, counters ->
  case order.status do
    :paid ->
      payment_date = SeedHelper.random_datetime_in_range(order.inserted_at, DateTime.utc_now())
      date = DateTime.to_date(order.inserted_at)
      counter = Map.get(counters, date, 0) + 1
      invoice_number = SeedHelper.generate_invoice_number(date, counter)
      
      payment = Repo.insert!(%Payment{
        order_id: order.id,
        amount: order.total_amount,
        payment_method: Enum.random([:cash, :qr_code]),
        payment_date: payment_date,
        notes: nil,
        invoice_number: invoice_number
      })
      {[payment], Map.put(counters, date, counter)}
    
    :partially_paid ->
      # Create 1-2 partial payments
      num_payments = Enum.random(1..2)
      payment_dates = Enum.map(1..num_payments, fn _ ->
        SeedHelper.random_datetime_in_range(order.inserted_at, DateTime.utc_now())
      end) |> Enum.sort()
      
      date = DateTime.to_date(order.inserted_at)
      
      {payments_list, new_counter} = Enum.map_reduce(payment_dates, Map.get(counters, date, 0), fn payment_date, counter ->
        amount = Decimal.mult(order.total_amount, Decimal.from_float(:rand.uniform() * 0.7))
        new_counter = counter + 1
        invoice_number = SeedHelper.generate_invoice_number(date, new_counter)
        
        payment = Repo.insert!(%Payment{
          order_id: order.id,
          amount: amount,
          payment_method: Enum.random([:cash, :qr_code]),
          payment_date: payment_date,
          notes: "Partial payment",
          invoice_number: invoice_number
        })
        
        {payment, new_counter}
      end)
      
      {payments_list, Map.put(counters, date, new_counter)}
    
    _ ->
      {[], counters}
  end
end)

IO.puts("Created #{length(payments)} payments")

IO.puts("")
IO.puts("=" |> String.duplicate(60))
IO.puts("Seeds completed successfully!")
IO.puts("=" |> String.duplicate(60))
IO.puts("")
IO.puts("Summary:")
IO.puts("  - Categories: #{length(categories)}")
IO.puts("  - Products: #{length(products)}")
IO.puts("  - Pricelists: #{length(pricelists)}")
IO.puts("  - Guests: #{length(guests)}")
IO.puts("  - Orders: #{length(orders)}")
IO.puts("  - Order Items: #{length(order_items)}")
IO.puts("  - Payments: #{length(payments)}")
IO.puts("")
IO.puts("Guests with today's check-in date: ~120")
IO.puts("Active orders for today: many")
IO.puts("")
