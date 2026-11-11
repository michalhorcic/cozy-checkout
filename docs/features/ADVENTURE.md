# Cozy Adventure

Volitelná hobby hra pro Michala a Lucku. První etapa obsahuje osobní ruční
questy, XP a audit. Kampaně, společné XP, automatické achievementy a čtení
provozních KPI přijdou v další etapě; současná verze je ještě nevyhodnocuje.

## Zapnutí a používání

1. Nasaď migraci `20261111120000_create_adventure_foundation.exs` standardním
   postupem aplikace. Přidává pouze tři tabulky s prefixem `adventure_`.
2. Nastav `ADVENTURE_ENABLED=true` a restartuj aplikaci. Výchozí hodnota je
   `false`. Vypnutí skryje odkaz v administraci a zablokuje herní stránky i akce;
   herní data a historie zůstanou uložené. Nevznikají žádné background joby.
3. Po přihlášení stávajícím admin PINem otevři **Další agenda → Cozy Adventure**
   (`/admin/adventure`) a klikni na **Založit herní profily**. Opakování setupu
   nezduplikuje profily a nezmění již uložené profily.
4. Vyber Michala nebo Lucku. Jde o vlastní prohlášení, nikoli osobní přihlášení.
   Volba trvá pouze po dobu otevření LiveView; opuštění stránky či obnovení ji
   vymaže. Přepnutí profilu zruší rozpracované potvrzení questu.
5. Aktivuj nejvýše tři osobní questy. Splnění potvrď samostatným formulářem
   s poznámkou o 10–1000 znacích. Neuváděj osobní údaje hostů.
6. Historii XP najdeš pod **Nastavení a audit**. Dashboard zobrazuje až 100
   questů (aktivní vždy před dokončenými) a posledních 20 XP transakcí.

## Pravidla první verze

| Šablona | XP | Opakování |
| --- | --- | --- |
| Připravit další pobyt | 50 | jednou za týden |
| Zkontrolovat otevřené zálohy | 50 | jednou za týden |
| Dokončit týdenní nákupní plán | 100 | jednou za týden |
| Zavést jedno provozní zlepšení | 250 | jednorázově |

Týden začíná v pondělí podle `Europe/Prague`, včetně přechodů letního času.
Převod používá časovou databázi PostgreSQL. Aktivní quest lze dokončit i po
konci jeho týdne; patří stále k původnímu období a zabírá jeden ze tří slotů.
Za opakovanou aktivaci stejné šablony v daném období ani opakované potvrzení
splnění nevznikne další odměna. Jednorázový quest lze splnit jednou za profil.

Definice jsou verzované v `Adventure.Catalog`. Každá instance ukládá snapshot
názvu, odměny, verze a frekvence, takže další změna katalogu nepřepíše historii.
Unikátnost šablony a období platí napříč verzemi katalogu.

Úroveň L začíná při `100*(L-1)*L/2` XP. Úroveň se odvozuje z ledgeru; neukládá
se samostatně. XP nejsou Kč, provozní KPI, odměna zaměstnance ani účetní údaj.
Poznámka a potvrzení představují ruční prohlášení o úkolu, nikoli kontrolu
skutečného stavu rezervace, zálohy či nákupního plánu.

## Oddělení od provozu

- Veškerá logika a schémata jsou v `lib/cozy_checkout/adventure/`, webová vrstva
  v `lib/cozy_checkout_web/live/adventure_live/`, testy ve vlastních adresářích.
- Context `CozyCheckout.Adventure` zapisuje pouze do `adventure_profiles`,
  `adventure_quests` a `adventure_xp_transactions`. Neobsahuje cizí provozní FK,
  nevolá provozní mutace, neposílá emaily a nevytváří doklady či účetní operace.
- Jediné integrační body jsou admin router, podmíněný odkaz v navigaci
  a konfigurace vypínače. POS neobsahuje herní prvky.
- V této etapě hra ještě žádná provozní data nečte. Budoucí čtení patří do
  `Adventure.Sources.*`; musí zůstat jednosměrné a bez zpětného zápisu.
- Sdílený admin PIN chrání všechny tři trasy a LiveView události. Každá herní
  mutace navíc ověřuje vypínač a platný aktivní profil.

## Transakce a opravy

Aktivace, dokončení a opravy zamykají řádek herního profilu. Limit tří aktivních
questů proto platí i při souběžných požadavcích. Dokončení, důkaz a XP se zapisují
v jedné `Ecto.Multi` transakci. Unikátní `award_key` brání duplicitním odměnám.

`Adventure.reverse_award(profile_id, award_id, reason)` je opravné doménové API
pro chybně přiznané XP, zatím bez UI. Vyžaduje aktivní modul, vlastní profil
odměny a důvod o 10–1000 znacích. Přidá právě jednu zápornou transakci navázanou
na původní odměnu, nepřepisuje ji a neotevře quest k dalšímu získání XP. Není to
penalizace. Produkční obsluhu oprav lze později zpřístupnit ve chráněném UI.

## Ověření

Přidané testy pokrývají hranice levelů, týden v Praze, idempotentní setup,
limit aktivních questů, atomický rollback odměny, atribuci, opakované dokončení,
kompenzace, souběh na samostatných PostgreSQL spojeních, vypnutí modulu,
admin guard a kontrolu SQL zápisů pouze do herních tabulek.

Testy se podle pravidel repozitáře spouštějí v CI; výsledek ověřuje správce PR.
Pro ruční kontrolu po CI:

- [ ] Při vypnutém modulu chybí navigace a přímá herní URL přesměruje do adminu.
- [ ] Bez PINu všechny herní URL vedou na přihlášení.
- [ ] Založit profily, vybrat hráče a aktivovat tři questy; čtvrtý se odmítne.
- [ ] Dokončit quest s poznámkou, ověřit odměnu a audit, opakovat aktivaci.
- [ ] Přepnout profil a ověřit oddělenou historii a XP; obnovit stránku.
- [ ] Vypnout modul a ověřit zachovaná herní data.
- [ ] Ověřit mobilní šířku, tabulátor a čitelné textové stavy.
