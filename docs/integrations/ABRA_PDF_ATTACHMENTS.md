# PDF přílohy pobytových faktur v ABRA

Samostatný doplněk pro zálohové výzvy (`advance`) a konečné faktury (`final`).
Nemění účetní payloady, platby, odpočty ani stavy účetní synchronizace.
Chyba PDF nevyvolá nové vytvoření faktury. Ve výchozím nastavení je vypnutý.

## Lokální zkouška jednoho dokladu

1. Spusť `mix ecto.migrate`.
2. Ponech dosavadní připojení do ABRA a nastav `ABRA_PDF_ENABLED=true`.
   `ABRA_PDF_AUTOMATIC_FROM` zatím nenastavuj: automatické zařazování neběží.
3. Spusť aplikaci přes `iex -S mix phx.server`.
4. Vyber UUID místního dokladu, který už je úspěšně synchronizovaný do ABRA:

   ```elixir
   alias CozyCheckout.Abra.PdfAttachments
   PdfAttachments.enqueue("UUID-dokladu")
   PdfAttachments.status("UUID-dokladu")
   ```

   Fronta `abra_pdf` přenos provede na pozadí. Úspěšný stav je `uploaded`.
   Chyba je v poli `error` při stavu `failed`.

5. V přílohách faktury v ABRA porovnej PDF s místním stažením. Zopakuj
   `enqueue/1`: další příloha nesmí přibýt. Ověř zálohovou i konečnou fakturu
   a nezměněný stav účetního exportu, plateb a odpočtů.

Přenos používá současné přístupové údaje pobytové integrace. Pokud její
aktuální adresa či firma nesouhlasí s uloženým cílem účetního exportu,
PDF se neodešle. Pro testovací firmu potřebuješ doklad již synchronizovaný
do této firmy; změna konfigurace nepřesměruje starý doklad jinam.

## Volitelné automatické odesílání

Po ruční zkoušce nastav také `ABRA_PDF_AUTOMATIC_FROM` na ISO 8601 čas
s časovou zónou, např. `2026-11-03T12:00:00Z`, a restartuj aplikaci.
Každou minutu se zařadí nejvýše 50 dosud nezařazených příloh faktur, jejichž
**účetní synchronizace skončila v tento čas nebo později**. Starší datum
může zahrnout historii. Výběr a vkládání záměrů i jobů jsou dávkové.

Přenos má vlastní tabulku `abra_pdf_transfers`, frontu a pět pokusů.
Po vyčerpání pokusů oprav příčinu a zopakuj `enqueue/1`. Vypnutí
`ABRA_PDF_ENABLED` pozastaví i zařazené přenosy. Účetní synchronizace
pokračuje jako dosud; přílohy uložené v ABRA se nemažou.

## PDF a opakování

Použije se `Billing.ensure_pdf/1`. Uložené PDF se nemění, chybějící se
připraví běžným rendererem. Název přílohy je `cozy-{UUID}-{SHA256}.pdf`.
Před uploadem se načte seznam příloh včetně dalších stránek. Existující
příloha se ověří stažením a porovnáním SHA256. Stejná kontrola následuje
po uploadu. Při timeoutu další pokus nejprve ověří předchozí upload.
Odlišný obsah pod stejným názvem se nepřepisuje.

API účet potřebuje čtení a zápis příloh. Použité API:

- `GET /c/{firma}/faktura-vydana/{id}/prilohy.json`
- `PUT /c/{firma}/faktura-vydana/{id}/prilohy/new/{nazev}.pdf`
  s `Content-Type: application/pdf` a původními bajty v těle.
- `GET /c/{firma}/faktura-vydana/{id}/prilohy/{priloha-id}/content`

Podobu odpovědí a oprávnění je nutné ověřit na místní instanci.
Podklad: [klient ABRA Flexi](https://github.com/Spoje-NET/php-abraflexi/blob/f79d01089f8f09d1dd4f7c8739f3dc2dc5efdf1e/src/AbraFlexi/Priloha.php).

## Testy

Testy používají `Req.Test`, bez skutečných účetních dokladů a uploadů.
Pokrývají původní PDF, ověření obsahu, timeout a opakování, chyby oprávnění,
změnu cíle, vypnutí, stránkování, časový filtr a zachování účetního exportu.

```sh
mix test test/cozy_checkout/financial/abra_pdf_attachments_test.exs
```
