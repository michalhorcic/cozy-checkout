# Barové platby v POS

Tento návod popisuje platby barových účtů. Pobytové doklady a jejich úhrady mají
[samostatnou evidenci](BILLING.md).

## Platba a rozdělení účtu

Otevřete účet v POS a zvolte platbu celého účtu nebo rozdělení podle položek.
Platební akce vyžadují autorizaci PINem; nastavení `ADMIN_PIN_HASH` popisuje
[README](../../README.md#admin-pin).

- **Hotovost** zapíše platbu a přepočítá stav účtu.
- **QR platba** nejprve zobrazí náhled pro bankovní aplikaci. V této fázi nevzniká
  platba ani nové platební číslo. Teprve potvrzení obsluhou platbu zapíše.
- Dílčí platba ponechá účet jako `partially_paid`; doplatek pracuje se zbývající
  částkou. Účet je `paid` až po úplné úhradě.

QR není automatické ověření připsání peněz na účet. Bankovní párování není
součástí tohoto postupu. Změní-li se částka během QR náhledu, aplikace vyžádá nový
náhled místo potvrzení původní částky.

Při platbě celého účtu lze upravit slevu a spropitné. Sleva se ve finančních
výstupech rozděluje mezi původní sazby DPH; spropitné se vykazuje zvlášť bez DPH.
Účtenka zobrazuje také již provedené platby a případný zbývající doplatek.

## Platební čísla a souběh

Záznam platby má číslo `PAY-YYYYMMDD-NNNN`, například `PAY-20261023-0001`.
Nejde o číselnou řadu pobytových faktur. Vytvoření platby a přepočet stavu běží
v transakci; zámky a unikátní index chrání číslování a souběžné úhrady.
Platba nad zbývající částku a platba zrušeného účtu jsou odmítnuty.

Po úplném zaplacení se zařadí Oban úloha synchronizace barového účtu do ABRA.
Chyba účetní synchronizace neznamená zrušení lokálně zaznamenané platby.

## QR a konfigurace

Barový účet pro QR platby se čte z `:bank_account` aplikace `:cozy_checkout`
v `config/config.exs`. Není to účet z profilu dodavatele pobytové fakturace.
Před použitím zkontrolujte skutečný účet a částku v bankovní aplikaci.

`CozyCheckout.Payments.QrCode` generuje SPD data a SVG na serveru pomocí
závislosti `qr_code`; převádí český účet na IBAN. POS předává jako variabilní
symbol číslo objednávky; QR helper odstraní nečíselné znaky a ponechá posledních
10 číslic. Měna QR je CZK. Změna zobrazovaného symbolu v `CurrencyHelper`
nezavádí jinou měnu plateb.

## Implementace a ověření

- `lib/cozy_checkout/sales.ex`: `create_payment/1`,
  `create_payment_with_order_update/3`, `update_order_payment_status/1`.
- `lib/cozy_checkout/sales/payment.ex`: validace záznamů plateb.
- `lib/cozy_checkout/payments/qr_code.ex`: QR data, IBAN a SVG.
- `lib/cozy_checkout_web/live/pos_live/order_management.ex`: PIN, náhled a potvrzení.
- `test/cozy_checkout_web/live/financial/pos_payments_test.exs`: chování POS plateb.

[Finanční regresní testy](../development/FINANCIAL_TESTS.md) ověřují souběh,
částky, QR, účtenky a účetní exporty. Pro ruční kontrolu stačí vlastní testovací
účet a QR náhled; zobrazení QR nevyžaduje provést skutečný bankovní převod.
