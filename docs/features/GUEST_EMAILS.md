# Emaily hostům

Rozesílání hostům je dostupné v administraci v sekci **Email Guests**. Zprávy se řadí do Oban fronty; stránka po zařazení zobrazuje stav aktuální rozesílky. Každý příjemce obdrží samostatný email.

Produkční nasazení potřebuje následující proměnné:

* `RESEND_API_KEY` – tajný API klíč účtu Resend.
* `EMAIL_FROM_ADDRESS` – ověřená adresa odesílatele; výchozí hodnota je `jindrichuvdum@jindrichuvdum.cz`.

Před prvním odesláním přidejte doménu `jindrichuvdum.cz` do Resendu a nastavte DNS záznamy, které Resend pro ověření domény zobrazí. Bez platného API klíče je odesílání v produkci vypnuté; chybějící secret nebrání startu aplikace.

HTML těla šablon jsou verzovaná v `priv/email_templates/pre_arrival/`. Pro přidání další šablony přidejte HTML soubor vhodný pro emailové klienty a její metadata (identifikátor, popis, výchozí předmět, jazyk a sezónu) do `CozyCheckout.GuestEmails.TemplateCatalog`. Interaktivní náhled `priv/static/email_pred_prijezdem.html` slouží pouze jako zdroj obsahu a není přímo odesílán.

V administraci lze místo šablony napsat vlastní prostý text; v emailu se bezpečně převede do HTML a zároveň zůstane dostupný jako textová alternativa. Při zařazení do fronty se uloží přesný obsah zobrazený v náhledu, takže pozdější úprava souboru šablony již zařazené emaily nezmění. V development prostředí se emaily zachytávají lokálně a lze je zobrazit na `/dev/mailbox`; skutečné odesílání přes Resend je nakonfigurované pouze v produkci.

Katalogové šablony podporují proměnné `{{guest_name}}`, `{{check_in_date}}` a `{{check_out_date}}` v těle i předmětu. Datum je ve formátu `DD.MM.RRRR`; chybějící datum odjezdu má český nebo německý fallback. V editoru lze u více vybraných rezervací přepínat, pro kterou z nich se zobrazuje náhled. Historie se ukládá pro každého příjemce zvlášť a zobrazuje se v detailu rezervace. Ukládá se předmět a metadata odeslání, nikoli tělo e-mailu; záznamy se automaticky nemažou. Stav „Accepted by provider“ znamená, že Resend požadavek přijal, nikoli že byl e-mail potvrzeně doručen.
