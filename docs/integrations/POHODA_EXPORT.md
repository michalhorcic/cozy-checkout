# Export barových účtů do POHODA

Na `/admin/pohoda-export` vyberte období, načtěte zaplacené účty, označte je a
zvolte **Export Selected Orders**. Stránka vyžaduje správní relaci.
Stáhne se `pohoda_export_YYYY-MM-DD.xml` pro ruční import do POHODA.

Exportuje se evidence baru. [Pobytové faktury](../features/BILLING.md) do tohoto
exportu nepatří. Export sám nepotvrzuje import do účetnictví ani neeviduje,
že byl konkrétní soubor již importován.

## Konfigurace a omezení

Modul `lib/cozy_checkout/pohoda.ex` používá `:pohoda_ico` a `:bank_account`
z konfigurace aplikace. Dodavatelskou adresu, předkontaci `1Op` a označení banky
`Fio` má přímo ve vytvářeném XML; nečte profil dodavatele pobytové fakturace.
Položka `:pohoda_default_account` v konfiguraci se v implementaci exportu nepoužívá.
Před reálným importem proto zkontrolujte XML a nastavení cílového účetnictví.

## Výběr a částky

- Zahrnují se nesmazané účty ve stavu `paid`; období se vztahuje k vytvoření
  objednávky, nikoli k datu přijetí platby.
- Smazané položky se vynechávají. Způsob platby v hlavičce se vybírá ze všech
  načtených plateb bez samostatného filtru smazaných plateb.
- Seskupení respektuje produkt, jednotkové množství, uloženou cenu a DPH.
- Sleva se poměrně rozděluje mezi daňové sazby, spropitné je samostatně bez DPH.
  Před vytvořením XML se kontroluje soulad součtu s částkou účtu.
- Sazby 0, 12 a 21 % se mapují na `none`, `low` a `high`.
- QR se mapuje na bankovní platbu, hotovost na hotovostní. Hlavička odvozuje
  jediný způsob z první načtené platby, nerozepisuje smíšené úhrady.
- Názvy výrobků se čtou z aktuálního katalogu, ale ceny a DPH z uložených položek.
  Změna názvu produktu proto může změnit text nového exportu.
- Servisní příznak účet z exportu automaticky nevylučuje.

XML obsahuje hlavičku vydané faktury, položky, souhrn DPH a částku likvidace.
Opakovaný export vytváří znovu soubor; chování při opakovaném importu závisí
na nastavení cílové POHODA.

## Ověření a řešení problémů

Při prázdném seznamu ověřte stav účtu a datum vytvoření. Při odmítnutí importu
ověřte identitu dodavatele, předkontaci, banku a podporované sazby v XML.
Implementaci obsluhuje `PohodaExportLive.Index` a výběr záznamů kontext `Sales`.

`test/cozy_checkout/financial/accounting_amounts_test.exs` ověřuje částky exportů,
slevy, spropitné a historickou DPH. Tyto testy neprovádějí reálný import do POHODA;
kompatibilitu konkrétní instalace je potřeba ověřit odděleně. Viz
[finanční testy](../development/FINANCIAL_TESTS.md).
