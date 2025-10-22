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
alias CozyCheckout.Bookings.Booking
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

  def random_datetime_in_range(from_datetime, to_datetime) do
    from_seconds = DateTime.to_unix(from_datetime)
    to_seconds = DateTime.to_unix(to_datetime)

    if from_seconds >= to_seconds do
      from_datetime
    else
      random_seconds = from_seconds + :rand.uniform(to_seconds - from_seconds)
      DateTime.from_unix!(random_seconds) |> DateTime.truncate(:second)
    end
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
Repo.delete_all(Booking)
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

# Create 100 unique guests (persons who may visit multiple times)
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

guests =
  Enum.map(1..100, fn i ->
    name = "#{SeedHelper.random_element(first_names)} #{SeedHelper.random_element(last_names)}"

    Repo.insert!(%Guest{
      name: name,
      # Add the guest number to ensure unique emails
      email:
        if(:rand.uniform() > 0.3,
          do: "#{String.downcase(String.replace(name, " ", "."))}#{i}@example.com",
          else: nil
        ),
      phone: "+420#{:rand.uniform(900_000_000) + 100_000_000}",
      notes: if(:rand.uniform() > 0.8, do: "VIP guest - prefers quiet rooms", else: nil)
    })
  end)

IO.puts("Created #{length(guests)} guests")

IO.puts("Creating rooms...")

# Create 13 rooms
room_data = [
  {"101", "Mountain View", "Cozy room with a beautiful view of the mountains", 2},
  {"102", "Forest Room", "Peaceful room overlooking the forest", 2},
  {"103", "Lake Suite", "Spacious suite with lake view", 4},
  {"104", "Deluxe Double", "Comfortable double room with modern amenities", 2},
  {"105", "Family Room", "Large room perfect for families", 4},
  {"201", "Attic Retreat", "Charming attic room with sloped ceilings", 2},
  {"202", "Garden View", "Room with a view of the garden", 2},
  {"203", "Premium Suite", "Luxurious suite with premium furnishings", 3},
  {"204", "Standard Double", "Standard room with double bed", 2},
  {"205", "Triple Room", "Room with three single beds", 3},
  {"301", "Penthouse", "Top floor penthouse with panoramic views", 4},
  {"302", "Cozy Single", "Perfect for solo travelers", 1},
  {"303", "Honeymoon Suite", "Romantic suite for couples", 2}
]

rooms =
  Enum.map(room_data, fn {room_number, name, description, capacity} ->
    Repo.insert!(%CozyCheckout.Rooms.Room{
      room_number: room_number,
      name: name,
      description: description,
      capacity: capacity
    })
  end)

IO.puts("Created #{length(rooms)} rooms")

IO.puts("Creating bookings...")

# Create 300 bookings - some guests have multiple bookings
today = Date.utc_today()

# Track guest+date combinations to avoid duplicates
used_combinations = MapSet.new()

bookings =
  Enum.reduce_while(1..300, {[], used_combinations}, fn i, {bookings_acc, used_combos} ->
    # Pick a random guest (some guests will have multiple bookings)
    # Try up to 10 times to find a guest+date combination that hasn't been used
    result =
      Enum.find_value(1..10, fn _attempt ->
        guest = SeedHelper.random_element(guests)

        # 40% of bookings check in today, 30% checked in recently, 30% historical
        {check_in, check_out, status} =
          cond do
            i <= 120 ->
              # Bookings checking in today (active)
              check_in = today
              check_out = Date.add(today, :rand.uniform(7))
              {check_in, check_out, "active"}

            i <= 210 ->
              # Bookings checked in recently (some active, some completed)
              days_ago = :rand.uniform(7)
              check_in = Date.add(today, -days_ago)
              check_out = Date.add(check_in, :rand.uniform(7))

              status =
                if Date.compare(check_out, today) == :lt do
                  "completed"
                else
                  "active"
                end

              {check_in, check_out, status}

            true ->
              # Historical bookings (completed)
              check_in = SeedHelper.random_date_in_range(180, 0)
              check_out = Date.add(check_in, :rand.uniform(14))
              {check_in, check_out, "completed"}
          end

        combination = {guest.id, check_in}

        if MapSet.member?(used_combos, combination) do
          nil
        else
          {guest, check_in, check_out, status, combination}
        end
      end)

    case result do
      nil ->
        # Couldn't find a unique combination after 10 attempts, stop creating bookings
        {:halt, {bookings_acc, used_combos}}

      {guest, check_in, check_out, status, combination} ->
        booking =
          Repo.insert!(%Booking{
            guest_id: guest.id,
            room_number: "#{:rand.uniform(50)}#{SeedHelper.random_element(["A", "B", ""])}",
            check_in_date: check_in,
            check_out_date: check_out,
            status: status,
            notes: if(:rand.uniform() > 0.9, do: "Late check-in requested", else: nil)
          })

        # Assign 1-2 random rooms to the booking (most bookings have 1 room)
        num_rooms = if :rand.uniform() > 0.8, do: 2, else: 1
        selected_rooms = Enum.take_random(rooms, num_rooms)

        Enum.each(selected_rooms, fn room ->
          Repo.insert!(%CozyCheckout.Bookings.BookingRoom{
            booking_id: booking.id,
            room_id: room.id
          })
        end)

        {:cont, {[booking | bookings_acc], MapSet.put(used_combos, combination)}}
    end
  end)
  |> elem(0)
  |> Enum.reverse()

IO.puts("Created #{length(bookings)} bookings")

IO.puts("Creating orders...")

# Create 500 orders - ensure many are for today
orders =
  Enum.flat_map(bookings, fn booking ->
    # Most active bookings (checked in today) have 1-3 orders
    # Recent bookings have 1-2 orders
    # Historical bookings have 0-2 orders
    num_orders =
      cond do
        booking.status == "active" and Date.compare(booking.check_in_date, today) == :eq ->
          :rand.uniform(3)

        booking.status == "active" ->
          :rand.uniform(2)

        true ->
          if(:rand.uniform() > 0.3, do: :rand.uniform(2), else: 0)
      end

    Enum.map(1..num_orders, fn _order_idx ->
      # Generate order date between check-in and today
      order_date =
        if booking.status == "active" do
          # Active bookings: order date between check-in and today
          days_since_checkin = Date.diff(today, booking.check_in_date)

          if days_since_checkin > 0 do
            Date.add(booking.check_in_date, :rand.uniform(days_since_checkin))
          else
            today
          end
        else
          # Completed bookings: order date between check-in and check-out
          days_of_stay = Date.diff(booking.check_out_date, booking.check_in_date)

          if days_of_stay > 0 do
            Date.add(booking.check_in_date, :rand.uniform(days_of_stay))
          else
            booking.check_in_date
          end
        end

      order_datetime = SeedHelper.random_datetime_in_range(Date.diff(today, order_date))

      # Determine order status (completed bookings: all paid, active bookings: 70% paid, 30% open)
      status =
        if booking.status == "completed" do
          "paid"
        else
          case :rand.uniform(10) do
            n when n <= 7 -> "paid"
            _ -> "open"
          end
        end

      # Generate unique order number
      order_number =
        "ORD-#{Date.to_string(order_date) |> String.replace("-", "")}-#{String.pad_leading(Integer.to_string(:rand.uniform(9999)), 4, "0")}-#{booking.id |> String.slice(0..7)}"

      Repo.insert!(%Order{
        booking_id: booking.id,
        guest_id: booking.guest_id,
        order_number: order_number,
        status: status,
        total_amount: Decimal.new("0"),
        discount_amount:
          if(:rand.uniform() > 0.8,
            do: SeedHelper.random_decimal(10, 100),
            else: Decimal.new("0")
          ),
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
          |> Decimal.mult(
            Decimal.add(Decimal.new("1"), Decimal.div(vat_rate, Decimal.new("100")))
          )
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

{payments, _final_counters} =
  Enum.flat_map_reduce(orders, invoice_counters, fn order, counters ->
    case order.status do
      "paid" ->
        payment_datetime =
          SeedHelper.random_datetime_in_range(order.inserted_at, DateTime.utc_now())

        payment_date = DateTime.to_date(payment_datetime)
        date = DateTime.to_date(order.inserted_at)
        counter = Map.get(counters, date, 0) + 1
        invoice_number = SeedHelper.generate_invoice_number(date, counter)

        payment =
          Repo.insert!(%Payment{
            order_id: order.id,
            amount: order.total_amount,
            payment_method: Enum.random(["cash", "qr_code"]),
            payment_date: payment_date,
            notes: nil,
            invoice_number: invoice_number
          })

        {[payment], Map.put(counters, date, counter)}

      _ ->
        # Open orders have no payments
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
IO.puts("  - Bookings: #{length(bookings)}")
IO.puts("  - Orders: #{length(orders)}")
IO.puts("  - Order Items: #{length(order_items)}")
IO.puts("  - Payments: #{length(payments)}")
IO.puts("")
IO.puts("Active bookings (checked in today): ~120")
IO.puts("Active orders for today: many")
IO.puts("")
