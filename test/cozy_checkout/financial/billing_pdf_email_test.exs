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

  test "Czech formatting, stay descriptions and balance labels match each document kind", %{
    booking: booking
  } do
    alias CozyCheckout.Billing.{Pdf, Presentation}

    advance = issue!(booking, "advance", %{"amount" => "2850"})
    advance_html = Pdf.html(advance)
    assert advance_html =~ "Záloha na pobyt a objednané služby"
    refute advance_html =~ "Přijatá záloha"
    refute advance_html =~ "<th>Počet</th>"
    refute advance_html =~ "<th>Nocí</th>"
    refute advance_html =~ "DUZP"
    assert advance_html =~ "K úhradě: 2 850,00 CZK"

    assert advance_html =~
             "Pobyt: #{Presentation.date(booking.check_in_date)} – #{Presentation.date(booking.check_out_date)}"

    refute advance_html =~ Date.to_iso8601(booking.check_in_date)
    assert advance_html =~ "class=\"brand-logo\""

    receipt!(booking, "2850")

    receipt =
      Enum.find(
        Billing.list_documents(%{"booking_id" => booking.id}),
        &(&1.kind == "tax_receipt")
      )

    receipt = Billing.get_document!(receipt.id)
    receipt_html = Pdf.html(receipt)
    assert receipt_html =~ "Přijatá záloha na pobyt a objednané služby"
    assert receipt_html =~ "Přijetí platby:"
    refute receipt_html =~ "NÁHLED – NEVYSTAVENÝ DOKLAD"
    refute receipt_html =~ "Splatnost:"
    refute receipt_html =~ "<th>Počet</th>"
    refute receipt_html =~ "<th>Nocí</th>"

    final = issue!(booking, "final")
    final_html = Pdf.html(final)
    assert final_html =~ "<th>Počet</th>"
    assert final_html =~ "<th>Nocí</th>"
    assert final_html =~ "848,21"
    refute final_html =~ "848.214"
    refute final_html =~ "K úhradě / přeplatek"
    assert Presentation.number("1234567.895") == "1 234 567,90"
    assert Presentation.number("-285.126") == "-285,13"

    assert {:ok, pdf} = Pdf.render(receipt)
    assert pdf =~ "%PDF-"
  end

  test "a fully prepaid final and an overpaid final have unambiguous balances", %{
    booking: booking
  } do
    alias CozyCheckout.Billing.Pdf
    {:ok, preview} = Billing.preview(booking.id, "final", %{})
    total = preview.total
    receipt!(booking, to_string(total))
    {:ok, prepaid} = Billing.preview(booking.id, "final", %{})
    assert Pdf.html(prepaid) =~ "Zbývá k úhradě: 0,00 CZK"

    receipt!(booking, "285")
    final = issue!(booking, "final")
    html = Pdf.html(final)
    assert html =~ "Přeplatek: 285,00 CZK"
    refute html =~ "Přeplatek: -"
    refute html =~ "alt=\"QR platba\""
  end

  test "Chrome exits and renderer timeouts return errors without killing the caller", %{
    booking: booking
  } do
    doc = issue!(booking, "advance")

    for renderer <- [
          CozyCheckout.BillingPdfFailures.Shutdown,
          CozyCheckout.BillingPdfFailures.Killed
        ] do
      assert {:error, reason} = CozyCheckout.Billing.Pdf.render(doc, renderer: renderer)
      assert reason =~ "PDF:"
      assert reason =~ "CHROME_EXECUTABLE"
    end

    assert {:error, reason} =
             CozyCheckout.Billing.Pdf.render(doc,
               renderer: CozyCheckout.BillingPdfFailures.Slow,
               timeout: 20
             )

    assert reason =~ "časový limit"
  end

  test "a missing Chrome binary is reported through the real ChromicPDF startup", %{
    booking: booking
  } do
    start_supervised!(
      {CozyCheckout.BillingPdfFailures.MissingChrome,
       on_demand: true,
       no_sandbox: true,
       chrome_executable: "/missing/cozy-billing-chrome",
       session_pool: [init_timeout: 1000, checkout_timeout: 1000]}
    )

    doc = issue!(booking, "advance")

    assert {:error, reason} =
             CozyCheckout.Billing.Pdf.render(doc,
               renderer: CozyCheckout.BillingPdfFailures.MissingChrome,
               timeout: 5000
             )

    assert reason =~ "Chrome"
    refute Billing.get_document!(doc.id).pdf
  end

  test "an asynchronous worker delivers an advance PDF to the dev mailbox storage", %{
    booking: booking
  } do
    config = Application.fetch_env!(:cozy_checkout, CozyCheckout.Mailer)
    Application.put_env(:cozy_checkout, CozyCheckout.Mailer, adapter: Swoosh.Adapters.Local)
    on_exit(fn -> Application.put_env(:cozy_checkout, CozyCheckout.Mailer, config) end)
    doc = issue!(booking, "advance")

    {:ok, delivery} =
      Billing.enqueue_email(
        doc.id,
        %{
          "recipient" => "local@example.com",
          "subject" => "Lokální záloha #{doc.number}",
          "body" => "Doklad v příloze",
          "consent" => "true"
        },
        Ecto.UUID.generate()
      )

    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, false)

        result =
          BillingEmailWorker.perform(%Oban.Job{
            args: %{"delivery_id" => delivery.id},
            attempt: 1,
            max_attempts: 5
          })

        send(parent, {:mail_result, self(), result})
      end)

    assert_receive {:mail_result, ^pid, :ok}, 15_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    stored = Billing.get_document!(doc.id)

    email =
      Enum.find(
        Swoosh.Adapters.Local.Storage.Memory.all(),
        &(&1.subject == "Lokální záloha #{doc.number}")
      )

    assert email
    assert hd(email.attachments).data == stored.pdf
    assert Repo.get!(Delivery, delivery.id).state == "accepted"
    Swoosh.Adapters.Local.Storage.Memory.delete_all()
  end

  test "an old snapshot with an invalid account cannot produce a misleading payment QR", %{
    booking: booking
  } do
    doc = issue!(booking, "advance")

    doc = %{
      doc
      | snapshot: put_in(doc.snapshot, ["supplier", "bank_account"], "1234567890123/2010")
    }

    html = CozyCheckout.Billing.Pdf.html(doc)
    assert html =~ "Platební údaje ověřte s vystavovatelem"
    refute html =~ "alt=\"QR platba\""
  end
end
