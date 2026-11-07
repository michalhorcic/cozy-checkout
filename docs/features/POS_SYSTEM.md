# Samoobslužný bar (POS)

POS je veřejné rozhraní na `/` a `/pos`. Administrace na `/admin` vyžaduje
[PIN](ADMINISTRATION.md#admin-pin). Rozhraní POS je přizpůsobené dotykovému ovládání.

## Běžný postup

1. Vyberte otevřený účet nebo tlačítkem **Nový účet** založte pojmenovaný účet.
2. Seznam zahrnuje otevřené i částečně zaplacené účty, včetně starších účtů
   navázaných na pobyt. Rezervace se nenabízejí a nové účty se na ně nevážou.
3. V účtu `/pos/orders/:id` vybírejte produkty podle kategorií nebo oblíbenosti.
   U produktů s jednotkou vyberte přednastavené nebo vlastní množství.
4. Zkontrolujte položky a celkovou částku. Opakované položky se
   [vizuálně seskupují](VISUAL_GROUPING.md); jednotlivé záznamy lze rozbalit a odebrat.
5. [Platbu](PAYMENT_FUNCTIONALITY.md) nebo rozdělení účtu otevře obsluha po zadání PINu.
   Účtenka je dostupná na `/pos/orders/:id/receipt`.

[Rozlišení standardních a servisních účtů](SERVICE_ORDERS.md) slouží mimo jiné
pro vlastní spotřebu. Hostům zůstává výběr produktů a účtů veřejně dostupný.

## Ceny a data

Položky používají aktivní ceník. Při přidání se ukládá cena a DPH; pozdější změna
katalogu nepřepočítává starý nákup. Součty, slevy a spropitné používají `Decimal`.
Také ve správě se nový účet zakládá pod vlastním názvem, bez výběru rezervace.
Historické vazby účtů zůstávají zachované.
Barové účty jsou oddělené od [fakturace ubytování](BILLING.md).

## Implementace

- `lib/cozy_checkout/sales.ex`: seznam otevřených účtů, tvorba účtů a položek, platby.
- `lib/cozy_checkout_web/live/pos_live/`: výběr účtu a správa objednávky.
- `lib/cozy_checkout_web/live/order_item_grouper.ex`: seskupení pro zobrazení.
- `assets/js/app.js`: importy JavaScriptu a POS hooky včetně dotykového ovládání.
- `lib/cozy_checkout_web/router.ex`: veřejné POS a chráněné administrativní cesty.

Cesty ke zdrojům v dokumentaci jsou relativní ke kořeni repozitáře.

## Ověření

[Finanční sada](../development/FINANCIAL_TESTS.md) pokrývá ceny a platby.
Při ruční kontrole ověřte výběr účtu i založení nového účtu, přidání různých množství,
seskupení a odebrání položek, rozdělení platby, QR náhled a účtenku.
Dotyková gesta je potřeba ověřit na dotykovém zařízení.
