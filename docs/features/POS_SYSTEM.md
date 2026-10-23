# Samoobslužný bar (POS)

POS je veřejné rozhraní na `/` a `/pos`. Administrace na `/admin` vyžaduje
[PIN](../../README.md#admin-pin). Rozhraní POS je přizpůsobené dotykovému ovládání.

## Běžný postup

1. Vyberte aktivní rezervaci nebo založte pojmenovaný rychlý účet bez rezervace.
2. Jediný otevřený nebo částečně zaplacený účet se otevře přímo. U více účtů nebo více hostů pokračujete
   na výběr `/pos/bookings/:booking_id/orders`; účet lze založit konkrétnímu hostu.
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
Barové účty jsou oddělené od [fakturace ubytování](BILLING.md).

## Implementace

- `lib/cozy_checkout/sales.ex`: rezervace s účty, tvorba účtů a položek, platby.
- `lib/cozy_checkout_web/live/pos_live/`: výběr rezervace, účtu a správa objednávky.
- `lib/cozy_checkout_web/live/order_item_grouper.ex`: seskupení pro zobrazení.
- `assets/js/app.js`: importy JavaScriptu a POS hooky včetně dotykového ovládání.
- `lib/cozy_checkout_web/router.ex`: veřejné POS a chráněné administrativní cesty.

Cesty ke zdrojům v dokumentaci jsou relativní ke kořeni repozitáře.

## Ověření

[Finanční sada](../development/FINANCIAL_TESTS.md) pokrývá ceny a platby.
Při ruční kontrole ověřte výběr rezervace i rychlý účet, přidání různých množství,
seskupení a odebrání položek, rozdělení platby, QR náhled a účtenku.
Dotyková gesta je potřeba ověřit na dotykovém zařízení.
