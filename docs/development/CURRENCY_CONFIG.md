# Formátování peněz a čísel

`CozyCheckoutWeb.CurrencyHelper` v
`lib/cozy_checkout_web/helpers/currency_helper.ex` centralizuje zobrazení peněz
v POS a administraci. Je importovaný přes `cozy_checkout_web.ex` do LiveViews,
LiveComponents a HTML modulů.

- `format_currency/1` přijímá `Decimal` nebo `nil`, částku zaokrouhlí na dvě
  desetinná místa a přidá symbol CZK. Tisíce odděluje mezerou.
- `format_number/1` formátuje číslo bez symbolu měny.
- `format_number/2` umožňuje zvolit přesnost a desetinný oddělovač.
- `currency_symbol/0` vrací symbol z atributu `@currency_symbol`.

```elixir
format_currency(Decimal.new("1234.56")) # "1 234.56 CZK"
format_currency(nil)                    # "0 CZK"
format_number(1234)                      # "1 234"
format_number(Decimal.new("1234.56"), precision: 2, decimal_separator: ",")
# "1 234,56"
```

Změna `@currency_symbol` mění pouze text zobrazovaný helperem. Nepřevádí částky,
nemění uložené doklady, QR platby ani účetní integrace. Aplikace tím nezíská
podporu více měn; fakturace i POS QR používají CZK.

Výpočty částek patří do finančních kontextů s `Decimal`; zaokrouhlení a lokalizace
zobrazení nejsou náhradou za finanční pravidla. Viz [finanční testy](FINANCIAL_TESTS.md).
