defmodule CozyCheckout.BillingPdfEmailTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  import Swoosh.TestAssertions
  alias CozyCheckout.Billing
  alias CozyCheckout.Billing.Delivery
  alias CozyCheckout.Workers.BillingEmailWorker
  setup :set_swoosh_global
  setup do: billing_fixture()

  @tag timeout: 60_000
  test "Chromium renders real immutable A4 PDF and the mail worker attaches those exact bytes", %{
    booking: booking
  } do
    final = issue!(booking, "final")
    assert {:ok, stored} = Billing.ensure_pdf(final.id)
    assert stored.pdf =~ "%PDF-"
    assert byte_size(stored.pdf) > 5000
    assert stored.pdf_sha256 == Base.encode16(:crypto.hash(:sha256, stored.pdf), case: :lower)
    assert {:ok, repeated} = Billing.ensure_pdf(final.id)
    assert repeated.pdf == stored.pdf

    attrs = %{
      "recipient" => "test@example.com",
      "subject" => "Česká faktura",
      "body" => "Dobrý den, zasíláme fakturu.",
      "consent" => "true"
    }

    key = Ecto.UUID.generate()
    assert {:ok, delivery} = Billing.enqueue_email(final.id, attrs, key)
    assert {:ok, same} = Billing.enqueue_email(final.id, attrs, key)
    assert delivery.id == same.id
    job = %Oban.Job{args: %{"delivery_id" => delivery.id}, attempt: 1, max_attempts: 5}
    assert :ok = BillingEmailWorker.perform(job)

    assert_email_sent(fn email ->
      [attachment] = email.attachments

      attachment.data == stored.pdf and attachment.filename == "#{final.number}.pdf" and
        email.subject == "Česká faktura"
    end)

    assert Repo.get!(Delivery, delivery.id).state == "accepted"
    assert :ok = BillingEmailWorker.perform(job)
    refute_email_sent()
    Billing.save_profile(Map.put(supplier_attrs(), "name", "Jiný dodavatel"))
    assert {:ok, after_change} = Billing.ensure_pdf(final.id)
    assert after_change.pdf == stored.pdf
  end

  test "email consent is required and template escapes parties", %{booking: booking} do
    final = issue!(booking, "final")

    assert {:error, _} =
             Billing.enqueue_email(
               final.id,
               %{"recipient" => "test@example.com", "subject" => "Test", "body" => "Test"},
               Ecto.UUID.generate()
             )

    edited = %{
      final
      | snapshot: put_in(final.snapshot, ["customer", "name"], "<script>Žluťoučký kůň</script>")
    }

    html = CozyCheckout.Billing.Pdf.html(edited)
    assert html =~ "&lt;script&gt;Žluťoučký kůň&lt;/script&gt;"
    refute html =~ "<script>"
    assert html =~ "Jedn. bez DPH"
  end

  @tag timeout: 60_000
  test "large documents render multiple pages with Czech fonts", %{booking: booking} do
    for i <- 1..45 do
      {:ok, _} =
        Billing.save_item(booking.id, %{
          "name" => "Doplňková služba číslo #{i} – příliš žluťoučký kůň",
          "quantity" => "1",
          "nights" => "1",
          "price_per_night" => "10",
          "vat_rate" => "21",
          "item_type" => "extra"
        })
    end

    final = issue!(booking, "final")
    assert {:ok, stored} = Billing.ensure_pdf(final.id)
    assert length(Regex.scan(~r{/Type /Page\b}, stored.pdf)) >= 2
  end
end
