# PDF přílohy pobytových faktur v ABRA

Samostatný doplněk pro zálohové výzvy (`advance`) a konečné faktury (`final`).
Nemění účetní payloady, platby, odpočty ani stavy účetní synchronizace.
Chyba PDF nevyvolá nové vytvoření faktury. Ve výchozím nastavení je vypnutý.

## Lokální ověření

1. Spusť `mix ecto.migrate`.
2. Ponech dosavadní připojení do ABRA a nastav `ABRA_PDF_ENABLED=true`.
   Zapnutí spustí automatické zařazování příloh včetně starších faktur.
3. Spusť aplikaci obvyklým způsobem a přihlas se do administrace.
4. V **Dokladech z rezervací** otevři detail zálohové nebo konečné faktury.
   Panel **PDF v ABRA** ukazuje, zda je funkce vypnutá, čeká se na účetní
   export, PDF čeká na odeslání, přenos selhal, nebo bylo PDF přeneseno
   a ověřeno. Při chybě se zobrazí její důvod.
5. Po úspěšném účetním exportu použij **Odeslat PDF do ABRA**. Nemusíš čekat
   na automatické zařazení jednou za minutu. Stav se obnovuje každých deset
   sekund a tlačítkem **Obnovit stav PDF**. Při chybě použij **Znovu odeslat
   PDF do ABRA**. Již přenesené PDF další odesílací tlačítko nenabízí.
6. V přílohách faktury v ABRA porovnej PDF s místním stažením. Ověř zálohovou i konečnou fakturu
   a nezměněný stav účetního exportu, plateb a odpočtů.

Přenos používá současné přístupové údaje pobytové integrace. Pokud její
aktuální adresa či firma nesouhlasí s uloženým cílem účetního exportu,
PDF se neodešle. Pro testovací firmu potřebuješ doklad již synchronizovaný
do této firmy; změna konfigurace nepřesměruje starý doklad jinam.

## Zapnutí a vypnutí

Jediné nastavení je `ABRA_PDF_ENABLED=true` nebo `false`; po změně restartuj
aplikaci. Při zapnutí se každou minutu zařadí nejvýše 50 dosud nezařazených
příloh úspěšně synchronizovaných zálohových a konečných faktur, včetně
historických dokladů. Datum vystavení ani synchronizace odeslání neomezuje.
Výběr a vkládání záměrů i jobů jsou dávkové.

Přenos má vlastní tabulku `abra_pdf_transfers`, frontu a pět pokusů.
Po vyčerpání pokusů oprav příčinu a použij **Znovu odeslat PDF do ABRA**. Vypnutí
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
změnu cíle, vypnutí, stránkování, zahrnutí historických dokladů a zachování účetního exportu.
LiveView testy ověřují stav a akce v detailu dokladu, obnovování stavu,
opakování chyby, blokování vypnuté funkce i nedokončeného účetního exportu
a přístup pouze po správním přihlášení.

```sh
mix test test/cozy_checkout/financial/abra_pdf_attachments_test.exs
mix test test/cozy_checkout_web/billing_pdf_live_test.exs
```
