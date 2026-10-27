# Čtení účtenek pro Cozy Checkout — schéma v1

Přikládám aktuální export katalogu Cozy, JSON schéma v1 a fotografie účtenky.
Vrať pouze jeden JSON objekt podle schématu. Fotografie zůstávají v chatu;
do JSONu nedávej obrázky, URL ani soubory. Cozy nic z internetu nestahuje.

- Použij nové UUID `import_id` pro každý nový doklad. Při opakovaném předání
  stejného návrhu zachovej stejné ID; opravovaný potvrzený nákup se v Cozy
  otevírá jako náhradní verze, nikoli přepsáním existujícího importu.
- Zachovej obchod, datum, číslo dokladu a všechny položky včetně drogerie.
  Čísla a množství piš jako desetinné řetězce s tečkou, nikdy JSON čísla.
  Ceny jsou v CZK včetně DPH a mají nejvýše dvě desetinná místa.
  Nečitelné údaje dej jako `null` a vysvětli je v `warnings`.
- `source_name` obsahuje nákupní název, značku a balení. Názvy neslučuj podle
  podobnosti. `proposed_ingredient_id` použij výhradně z exportu katalogu;
  nepřiřazuj archivované suroviny a nevymýšlej nová ID. Název je kontrolní,
  rozhoduje ID. Více značek může mít stejné ID. Známé přiřazení hledej podle
  obchodu a úplného názvu; při konfliktu návrh vysvětli v `mapping_reason`
  a upozornění. Zboží mimo katalog nech bez ID.
- `quantity` a `unit` jsou CELKOVÉ nakoupené množství: dvě balení po 140 g
  znamenají `quantity: "280", unit: "g"`. `kind: "packaged"` dále obsahuje
  `package_count`, `package_quantity`, `package_unit`. Velikost balení vždy
  přečti z tohoto dokladu, nekopíruj ji ze starého přiřazení.
- U váženého zboží použij `kind: "weighed"`, skutečné celkové množství a
  žádné balení (pole vynech nebo nastav na null). Převody jsou jen g/kg,
  ml/l a ks/ks. Hmotnost kusu ani hustotu neodhaduj. Při nejasné hmotnosti
  balení ponech množství null a popiš problém.
- `line_total_after_discount` je konečná cena celého řádku po jeho řádkové
  slevě. Společnou slevu, kterou nelze bezpečně přiřadit jednotlivým řádkům,
  ZATÍM NEODEČÍTEJ od řádků: uveď ji jako kladnou `receipt.shared_discount`.
  Obsluha ji následně výslovně rozdělí nebo přiřadí ručně v náhledu.
  Pokud už je společná sleva v cenách řádků zahrnutá, napiš shared_discount
  jako "0". Jednu slevu nesmíš odečíst dvakrát.
- `receipt.rounding` je samostatné znaménkové zaokrouhlení dokladu, nikoli
  sleva. Platí: součet řádků − dosud nerozdělená společná sleva + zaokrouhlení
  = `total_paid`. Rozdíl nikdy nezakrývej smyšlenou cenou nebo zaokrouhlením;
  zaznamenej upozornění. Vratky a záporné položky tato verze nepodporuje.

Nejasnosti se doplňují v Cozy. Žádný návrh sám nevytváří suroviny, účetní
doklady ani uložená přiřazení. Obsluha kontroluje řádky a potvrzuje celý nákup.
