# ABRA Flexi — zálohové výzvy za ubytování

První samostatně ověřitelná část integrace: **ruční export vystavené zálohové
výzvy** z detailu `/admin/billing/documents/:id`. Export je ve výchozím stavu
vypnutý. Nevytváří platbu, ZDD ani bankovní nebo pokladní pohyb. Přijetí peněz
ani finanční stav pobytu se exportem nemění.

Tento dokument popisuje původní ruční postup. Nyní lze zapnout také
[automatický export výzev a konečných faktur se společným přehledem chyb](ABRA_INTEGRATION.md#automatický-export-a-společný-přehled-přenosů).
Bankovní zálohy, ZDD, odpočty a doplatky popisuje navazující provozní dokumentace.

## Nastavení pro testovací firmu

Spusťte migrace `20261026120000_create_accommodation_abra_exports.exs` a
`20261026130000_set_cozy_advance_prefix.exs`. Druhá nastaví místním řadám
zálohových výzev prefix `COZY-ZF`, zachová jejich čítače i již vystavené
doklady. Při rollbacku ponechá nový prefix zachovaný. Formulář pro zakládání
řad jej také předvyplňuje.
Připojení a přístupové údaje jsou společné s existující integrací do stejného
účetnictví (`ABRA_BASE_URL`, `ABRA_COMPANY_ID`, `ABRA_USERNAME`, `ABRA_PASSWORD`).
Mapování dokladů ubytování je samostatné; barový builder ani barová řada se
nepoužívají. Pro jiné testovací prostředí ubytování lze přepsat pouze jeho
server a firmu pomocí `ABRA_ACCOMMODATION_BASE_URL` a
`ABRA_ACCOMMODATION_COMPANY_ID`; přihlašovací údaje zůstávají společné.

| Proměnná | Význam |
| --- | --- |
| `ABRA_ACCOMMODATION_ENABLED` | `true` povolí celou synchronizaci ubytování včetně automatického exportu a banky; výchozí `false`. |
| `ABRA_ACCOMMODATION_ENABLED_FROM` | Povinný okamžik zapojení **nově vytvořených rezervací**, ISO 8601 s časovou zónou, např. `2026-10-26T12:00:00+01:00`. Posuzuje se `booking.inserted_at`, nikoli datum příjezdu. |
| `ABRA_ACCOMMODATION_ADVANCE_TYPE_CODE` | Typ zálohy bez `code:`, výchozí `ZÁLOHA` podle XML. |
| `ABRA_ACCOMMODATION_BANK_ACCOUNT_CODE` | Kód účtu bez `code:`, výchozí `BANKOVNÍ ÚČET` podle XML. Musí odpovídat účtu na místním dokladu. |

V testovací firmě předem ověřte dostupnost číselníků a oprávnění API uživatele
pro čtení i vytváření vydaných faktur. Čísla přiděluje výhradně místní databáze:
např. `COZY-ZF202600009`. ABRA dostává hotové číslo v `kod`; vazba `rada` se
neposílá ani nekontroluje a samostatná řada v ABRA není pro export potřeba.
Proměnná `ABRA_ACCOMMODATION_ADVANCE_SERIES_CODE` se již nepoužívá.

## Obsah a bezpečné opakování

- Použije se uložený snapshot odběratele, původní číslo (`kod`, nejvýše
  20 znaků), VS, datum vystavení, splatnost a měna CZK.
- Nový VS je odvozený ze stejné řady jako číslo dokladu: číslice druhu,
  čtyřmístný rok a pětimístné pořadí. `COZY-ZF202600009` má VS `1202600009`.
  Kódy druhů jsou `1` výzva, `2` konečná faktura, `3` doklad k platbě, `4` oprava.
  Písmena se ve VS nepoužívají. Při překročení 99 999 dokladů ročně daného
  druhu se vystavení odmítne, číslice se nikdy neořezávají. Historické VS z
  dřívější nezávislé sekvence zůstávají zachované; export je nepřepočítává.
- Podle XML jde o `faktura-vydana`, `ucetni=false`, `bezPolozek=false`, členění
  DPH `000U` a kontrolního hlášení `0.0.` na hlavičce i položkách; DUZP se
  neodesílá. Nevzniká daňový doklad ani úhrada.
- Místní záloha již uchovává rozdělení požadované částky do daňových skupin.
  Každá skupina se přenese jako jedna položka s množstvím 1 a přesnou částkou
  zálohy, nikoli jako celý původní pobyt. Sazby 12/21/0 % a nezdaněný poplatek
  navazují na XML. Toto mapování neřeší budoucí daňové režimy ZDD/vyúčtování.
- Poznámka `poznam` obsahuje původní rozpis celého pobytu ze snapshotu
  `advance_calculation`: názvy, množství, noci/jednotky, jednotkové a celkové
  ceny, celkovou cenu pobytu a výpočet požadované zálohy. Rozpis celého pobytu
  je výslovně odlišen od částky zálohy. Pozdější změny kalkulace se do něj
  nepřenášejí. Starší doklad bez rozpisu obsahuje pouze částku a informaci,
  že původní položky nebyly uloženy; aktuální kalkulace se k němu nedoplňuje.
- Položky se zaokrouhlují na haléře; korunní zaokrouhlení hlavičky ze vzoru
  se nepřebírá, protože nesmí změnit již vystavenou místní částku.
- V jedné databázové transakci se uloží jedinečný export a unikátní Oban job.
  Zámek rezervace brání dvojkliku při zařazování. Síťová komunikace běží až ve
  workeru mimo tuto transakci, ve frontě `abra_sync`, nejvýše pět pokusů.
- Export uchovává cílový server a firmu, původní payload a stabilní identitu
  `ext:cozy-checkout:accommodation:<UUID dokladu>`. Přístupové údaje neukládá.
  Ruční opakování neposkládá jiný payload z aktuální konfigurace nebo ceníku.
- Před každým importem se hledá vzdálený doklad pod externím ID. Existující
  doklad se pouze zkontroluje. Nový import používá `@create=ok` a `@update=fail`, takže
  souběh ani opožděná odpověď nesmějí vést k aktualizaci existujícího dokladu.
  Jde o [režimy importu](https://podpora.flexibee.eu/cs/articles/4725944-rezim-pro-zalozeni-zmenu),
  nikoli o `@action`, které je určeno pro akce nad existujícím záznamem.
- Po importu se doklad znovu načte a porovná se číslo, VS, částka, měna, typ,
  účet a neúčetní daňové členění. Nesoulad je chyba k ručnímu prověření;
  integrace vzdálený doklad neopravuje. Timeout po přijatém importu se při
  dalším pokusu řeší načtením existujícího dokladu, bez dalšího POST.
- Změna serveru nebo firmy zablokuje uložený export. Testovací identitu nelze
  přesměrovat do jiné firmy. Pro test použijte nové rezervace/doklady.

## Ruční ověření

1. Nastavte připojení na testovací firmu, samostatné mapování a okamžik
   zapojení. Zapněte export. Až potom vytvořte novou rezervaci.
2. Připravte kalkulaci, odběratele a vystavte zálohovou výzvu běžným postupem.
   Doporučený první případ: 50% záloha s ubytováním 12 % a rekreačním
   poplatkem. Vyzkoušejte i explicitní částku s haléři.
3. V detailu dokladu použijte **Exportovat do ABRA** a následně **Obnovit stav
   exportu**. Export je oddělený od generování PDF a odesílání e-mailu.
4. V ABRA porovnejte číslo, VS, odběratele, adresu, data, měnu, bankovní účet,
   položky, poznámku s původním rozpisem, požadovanou částku a neúčetní charakter. Zkontrolujte nepřítomnost
   platby, ZDD a nežádoucího účtování/DPH. Vlastní číslo má zůstat zachované.
5. Při chybě je vidět poslední důvod a počet pokusů. Po vyčerpání pokusů lze
   použít **Opakovat export do ABRA**. Ověřte, že další pokus nepřidá druhý
   doklad. Timeout po skutečně přijatém požadavku vyzkoušejte v testovací
   infrastruktuře; automatický test tento průběh pouze simuluje přes Req.Test.
6. Starší rezervace a ostatní druhy dokladů se nesmějí exportovat. Po vypnutí
   přepínače worker odkládá čekající joby, doklady i evidence exportů zůstanou.

Administrace zůstává chráněna stávajícím PIN. Chyby jobů a jejich historii
zobrazuje také Oban dashboard. Stav dokončeného exportu neznamená potvrzenou
úhradu a další ruční spárování nebo úpravy v ABRA se v této části nesledují.

## Ověření při vývoji

Zásadní testy pokrývají mapování snapshotu, opakované zařazení, vyloučení starých
rezervací, úspěšný přenos, timeout po přijatém zápisu, konflikt částky, změnu
cílové firmy a ruční administrátorský postup. HTTP používá `Req.Test` a nevytváří
reálné účetní doklady. Lokální testy nebyly spuštěny; výsledky CI ověří uživatel.
Skutečné API a účetní shodu ověří uživatel proti své testovací firmě před další
částí implementace.
