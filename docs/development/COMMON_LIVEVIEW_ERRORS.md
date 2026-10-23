# Diagnostika LiveView

## Neshodné parametry události

Chyba `no function clause matching in handle_event/3` obvykle znamená, že jméno
události nebo tvar parametrů nesouhlasí s handlerem. Nejprve porovnejte konkrétní
HEEx prvek a jeho `phx-target` s příslušným `handle_event/3`.

Formulář posílá parametry podle názvů polí, například `name="pricelist[price]"`
vytvoří mapu `%{"pricelist" => %{"price" => value}}`. Kliknutí s
`phx-value-id={id}` předává parametr `"id"`. Jednotlivé `phx-change` na vstupu
má své použití; záleží na skutečném tvaru odeslaných dat.

Automatický catch-all, který ignoruje všechny neznámé události, může chybu
skrýt. Oprava má cílit na konkrétní kontrakt události a při změně chování ověřit
formulář přes LiveView test. Při diagnostice nelogujte PINy ani osobní údaje.

## Chybějící assigns

Hodnoty používané v šabloně musí existovat už při prvním renderu. Pro LiveView
zkontrolujte `mount/3`, pro LiveComponent `update/2`. Při opakovaném `update/2`
pozor na nechtěné přepsání rozpracovaného stavu komponenty.

## Formuláře a streamy

Projekt používá `<.form>` a sdílenou komponentu `<.input>`; dostupné komponenty
jsou v `lib/cozy_checkout_web/components/core_components.ex`.
U kontejneru s `phx-update="stream"` musí mít jednotlivé položky stabilní DOM ID:

```heex
<div id="products" phx-update="stream">
  <div :for={{id, product} <- @streams.products} id={id}>
    {product.name}
  </div>
</div>
```

Příklady konkrétních formulářů jsou v `lib/cozy_checkout_web/live/pricelist_live/`
a související testy v `test/cozy_checkout_web/`.
