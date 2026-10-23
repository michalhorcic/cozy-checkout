# Servisní účty

Servisní účet označuje vlastní spotřebu, přátele a jiné nestandardní nákupy.
Používá stejnou tabulku `orders` a položky jako běžný účet; odlišuje jej příznak
`is_service_order`, který je ve výchozím stavu `false`.

## Použití v POS

1. Na `/pos` zapněte servisní režim v hlavičce.
2. Založte rychlý účet nebo vyberte rezervaci. Nový účet převezme servisní příznak.
3. Výběr účtů rezervace dostane režim parametrem `service_mode=true`.
4. V detailu nezaplaceného účtu lze přepnout mezi standardním a servisním účtem.
   U zaplaceného účtu je převod odmítnut.

Seznam rychlých účtů a výběr účtů rezervace filtrují standardní a servisní účty
odděleně. Seznam aktivních rezervací na úvodní stránce zůstává společný;
nejde o oddělenou evidenci rezervací.

Servisní příznak sám nezavádí jiný ceník ani osvobození od platby. Statistiky
nabízejí filtr standardních a servisních objednávek. Export POHODA používá
zaplacené objednávky a servisní příznak automaticky nevylučuje.
Přepnutí režimu v POS není oprávnění a nemá vlastní historii konverzí.

## Implementace

- Migrace `20260125130329_add_is_service_order_to_orders.exs` přidává příznak a index.
- `lib/cozy_checkout/sales/order.ex`: schéma a administrativní filtr Flop.
- `lib/cozy_checkout/sales.ex`: `toggle_service_order/1`,
  `get_or_create_booking_order/2`, `create_booking_order_for_guest/3` a statistiky.
- `lib/cozy_checkout_web/live/pos_live/`: přepínač, předávání režimu a označení účtu.

Viz [POS](POS_SYSTEM.md), [platby](PAYMENT_FUNCTIONALITY.md) a
[POHODA](../integrations/POHODA_EXPORT.md).
