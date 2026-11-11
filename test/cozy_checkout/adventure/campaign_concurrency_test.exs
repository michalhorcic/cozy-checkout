defmodule CozyCheckout.Adventure.CampaignConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import CozyCheckout.AdventureFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias CozyCheckout.Repo
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Evaluation, Profile, Unlock, XpTransaction}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)

    {profile, campaign, booking} =
      Sandbox.unboxed_run(Repo, fn ->
        profile =
          Repo.insert!(%Profile{
            slug: "campaign-race-#{Ecto.UUID.generate()}",
            display_name: "Race"
          })

        campaign = active_campaign(profile)
        today = CozyCheckout.Adventure.Sources.Stays.today()

        booking =
          adventure_booking(%{
            check_in_date: Date.add(today, -4),
            check_out_date: Date.add(today, -2)
          })

        {profile, campaign, booking}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.get!(Campaign, campaign.id)
        |> Ecto.Changeset.change(last_evaluation_id: nil)
        |> Repo.update!()

        unlock_ids = from u in Unlock, where: u.campaign_id == ^campaign.id, select: u.id

        Repo.delete_all(
          from x in XpTransaction,
            where: x.unlock_id in subquery(unlock_ids) and not is_nil(x.reverses_id)
        )

        Repo.delete_all(from x in XpTransaction, where: x.unlock_id in subquery(unlock_ids))
        Repo.delete_all(from u in Unlock, where: u.campaign_id == ^campaign.id)
        Repo.delete_all(from e in Evaluation, where: e.campaign_id == ^campaign.id)
        Repo.delete_all(from c in Campaign, where: c.id == ^campaign.id)
        Repo.delete!(Repo.get!(CozyCheckout.Bookings.Booking, booking.id))
        Repo.delete!(Repo.get!(CozyCheckout.Guests.Guest, booking.guest_id))
        Repo.delete!(profile)
      end)

      Application.put_env(:cozy_checkout, :adventure_enabled, previous)
    end)

    {:ok, profile: profile, campaign: campaign, booking: booking}
  end

  test "parallel evaluations and reconciliation cannot duplicate unlocks or corrections", %{
    profile: p,
    campaign: c,
    booking: b
  } do
    assert Enum.all?(race(fn -> Campaigns.evaluate(c.id, p.id) end), &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(u in Unlock, where: u.campaign_id == ^c.id), :count) == 1

      assert Repo.aggregate(from(x in XpTransaction, where: x.recipient_type == "shared"), :count) ==
               1

      b |> Ecto.Changeset.change(status: "cancelled") |> Repo.update!()
    end)

    assert Enum.all?(race(fn -> Campaigns.evaluate(c.id, p.id) end), &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.get_by!(Unlock, campaign_id: c.id).status == "revoked"

      assert Repo.aggregate(from(x in XpTransaction, where: x.recipient_type == "shared"), :count) ==
               2
    end)
  end

  defp race(fun) do
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Sandbox.unboxed_run(Repo, fun)
          end
        end)
      end

    for _ <- tasks do
      receive do
        {:ready, _} -> :ok
      after
        5000 -> flunk("Task did not start")
      end
    end

    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 15_000))
  end
end
