# Finanční regresní testy POS

Sada ověřuje finanční pravidla pro objednávky, platby, cenotvorbu, účtenky a
účetní exporty. Testuje výsledné částky a chování veřejných rozhraní aplikace.

Účetní pravidlo ověřované při slevách: sleva se rozděluje poměrně mezi původní
sazby DPH a dobrovolné spropitné se vykazuje samostatně bez DPH.

## Spuštění

Finanční testy:

```sh
mix test test/cozy_checkout/financial test/cozy_checkout_web/live/financial
```

Celá projektová kontrola včetně kompilace, formátování a všech testů:

```sh
mix precommit
```

Všech devět finančních testovacích modulů má značku `financial`. V současnosti
nejsou žádné finanční testy označené `known_bug`; není proto třeba tuto značku
vylučovat ani spouštět samostatně.

## Pokrytí

Finanční sada je rozdělena do těchto testovacích modulů:

- `sales_money_test.exs` — přepočet objednávek, slevy a spropitné, historické
  ceny a sazby DPH, stavy plateb, storna a validace částek.
- `sales_concurrency_test.exs` — souběžné platby a přidělování čísel dokladů
  při oddělených databázových spojeních.
- `catalog_pricing_test.exs` — platnost ceníků, cenové úrovně a zachování ceny
  a DPH při vytvoření položky.
- `pos_payments_test.exs` — hotovostní a QR platby, náhled a potvrzení platby,
  doplatky, autorizace a opakované události.
- `receipt_amounts_test.exs` — částky a rozpis DPH na účtence včetně slev,
  spropitného a smazaných záznamů.
- `accounting_amounts_test.exs` — soulad položek, součtů, DPH a úhrad v exportech
  ABRA a POHODA, včetně smíšených sazeb a historické DPH.
- `qr_code_test.exs` — částka, IBAN, platební údaje a výstup QR kódu.
- `abra_client_test.exs` — HTTP požadavek, autentizace, zpracování chyb, timeoutů
  a validace úspěšné odpovědi ABRA.
- `abra_sync_test.exs` — synchronizace zaplacených objednávek, opakování po
  chybě, idempotence při ztracené odpovědi a chování Oban workeru.

## Izolace a omezení

ABRA HTTP požadavky jsou v testech směrovány přes `Req.Test`; testy neodesílají
skutečné doklady. Oban je nakonfigurován tak, aby testovací joby neprováděly
produkční síťové ani background operace. Souběžné testy používají testovací
databázi a vlastní databázová spojení.

Test ztracené odpovědi ABRA simuluje situaci, kdy vzdálený systém doklad uloží,
ale klient obdrží timeout. Ověřuje idempotentní identitu požadavku; nepotvrzuje
chování konkrétní instance ABRA Flexi.

Při posledním ověření po finančních opravách prošel `mix precommit`:
**108 testů, 0 selhání**.
