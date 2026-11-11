defmodule CozyCheckout.AdventureFixtures do
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Profile}
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Guests.Guest

  def adventure_profile do
    {:ok, :ok} = Adventure.initialize()
    Repo.get_by!(Profile, slug: "michal")
  end

  def campaign_attrs(attrs \\ %{}) do
    today = CozyCheckout.Adventure.Sources.Stays.today()

    Map.merge(
      %{
        name: "Testovací kampaň",
        starts_on: Date.add(today, -30),
        ends_on: Date.add(today, 30),
        capacity: 45,
        completed_goal: 10,
        reserved_goal: 1000,
        occupancy_goal: 50
      },
      attrs
    )
  end

  def active_campaign(profile, attrs \\ %{}) do
    {:ok, draft} = Campaigns.create(campaign_attrs(attrs))

    draft
    |> Ecto.Changeset.change(
      status: "active",
      activated_by_id: profile.id,
      activated_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -30 * 86_400)
    )
    |> Repo.update!()
  end

  def adventure_booking(attrs \\ %{}) do
    guest =
      Repo.insert!(%Guest{
        name: "Soukromé jméno hosta",
        email: "#{Ecto.UUID.generate()}@example.test"
      })

    defaults = %{
      guest_id: guest.id,
      check_in_date: ~D[2026-10-01],
      check_out_date: ~D[2026-10-03],
      adults: 2,
      status: "completed"
    }

    Repo.insert!(struct(Booking, Map.merge(defaults, attrs)))
  end

  def fixed_campaign(profile) do
    Repo.insert!(%Campaign{
      name: "Říjen",
      starts_on: ~D[2026-10-01],
      ends_on: ~D[2026-10-10],
      capacity: 10,
      completed_goal: 10,
      reserved_goal: 100,
      occupancy_goal: 50,
      status: "active",
      activated_by_id: profile.id,
      activated_at: ~U[2026-09-30 12:00:00Z]
    })
  end
end
