# Výběr produktu v ceníku

Při založení ceníku v `/admin/pricelists` vyhledejte produkt podle názvu nebo
kategorie a klikněte na výsledek. Vybraný produkt se zobrazí samostatně;
tlačítkem pro zrušení výběru lze vyhledat jiný. Při editaci existujícího ceníku
je změna produktu vypnutá.

Formulář přednačítá katalog a filtruje jej v paměti. Bez dotazu ukazuje prvních
20 produktů, s dotazem nejvýše 10 shod. Vyhledávání používá `String.downcase/1`
a `String.contains?/2`; není to hledání bez diakritiky. Vstup má debounce 300 ms.
Výsledky obsahují název, kategorii a případnou jednotku.

Implementace je v `lib/cozy_checkout_web/live/pricelist_live/form_component.ex`:

- `search_product` aktualizuje filtrované výsledky a dotaz.
- `select_product` nastaví produkt formuláře.
- `clear_product` zruší výběr.
- `filter_products/2` omezuje výsledky.

Stav komponenty obsahuje `all_products`, `filtered_products`, `selected_product`,
`search_query` a `show_dropdown`. Speciální ovládání výsledků šipkami a Enterem
není součástí popsané implementace.
