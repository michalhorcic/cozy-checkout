# Vizuální seskupování položek

POS i administrace zobrazují opakované položky souhrnně, ale záznamy
`order_items` v databázi neslučují. Každé přidání zůstává samostatné a zachovává
své množství, historickou cenu, DPH a čas vytvoření.

`CozyCheckoutWeb.OrderItemGrouper` v
`lib/cozy_checkout_web/live/order_item_grouper.ex` seskupuje nesmazané položky
podle **produktu, jednotkového množství a jednotkové ceny**. Rozdílné ceny se
proto zobrazí odděleně. Skupina obsahuje produkt, jednotku, `price_per_unit`,
`vat_rate` převzatou z první položky, součet množství a mezisoučtů, ID a původní
položky seřazené časem přidání a stav rozbalení.

Například dva záznamy stejného produktu 500 ml za stejnou cenu, s množstvím
1 a 2, vytvoří řádek s celkovým množstvím 3. Jiná velikost nebo cena vytvoří
další skupinu. Rozbalení zpřístupní jednotlivé záznamy; POS umožňuje jejich
odebrání tlačítkem nebo dotykovým gestem. Administrace nabízí i hromadné odebrání
skupiny s potvrzením.

Zobrazení není podkladem pro sloučení účetních sazeb: POHODA export má vlastní
seskupení, které zahrnuje i historickou DPH. Přesná pravidla částek ověřuje
[finanční sada](../development/FINANCIAL_TESTS.md).

Viz také [POS](POS_SYSTEM.md) a [platby](PAYMENT_FUNCTIONALITY.md).
