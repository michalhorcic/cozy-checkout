# Finanční testy POS

Přidáno 78 scénářů nad stávajícími rozhraními aplikace. Aplikační kód,
konfigurace, migrace a závislosti zůstávají beze změn. Dělení účtu se netestuje.

Potvrzené účetní pravidlo: sleva se rozpočítává poměrně mezi původní sazby DPH;
dobrovolné spropitné se vykazuje samostatně bez DPH. Testy kontrolují výsledné
částky, nikoli konkrétní implementaci budoucí opravy.

## Spuštění

Celá nová sada, včetně regresních testů odhalujících současné chyby:

```sh
mix test test/cozy_checkout/financial test/cozy_checkout_web/live/financial
```

Pouze dosud funkční scénáře:

```sh
mix test test/cozy_checkout/financial test/cozy_checkout_web/live/financial --exclude known_bug
```

Jen regresní scénáře:

```sh
mix test test/cozy_checkout/financial test/cozy_checkout_web/live/financial --only known_bug
```

Všechny nové testovací moduly mají značku `financial`. Značka `known_bug` označuje
ověřená selhání současné aplikace; nezpůsobuje automatické přeskočení. Běžné
`mix test` provede i tyto testy. Po opravě je vhodné odstranit příslušnou značku.

## Ověřený výsledek

- Nová sada: **78 testů, 39 úspěšných a 39 selhávajících**.
- Nová sada s `--exclude known_bug`: **39 spuštěných testů, 0 selhání**.
- Celý projekt přes `mix precommit`: **90 testů, 42 selhání**; kromě 39 nových
  regresí selhávají také tři původní testy (domovská stránka, kalendářový feed,
  formátování skladového pohybu).
- Testovací soubory jsou zformátované. `mix precommit` proto není zelený;
  aplikační chyby nebyly opravovány.

## Pokrytí a nalezené problémy

| Soubor | Pokrytí a reprodukované problémy |
| --- | --- |
| `cozy_checkout/financial/sales_money_test.exs` | Přepočet, sleva, spropitné, historické ceny a DPH, platební stavy, storno, vstupy, čísla dokladů a zařazení ABRA jobu. Přepočet vynechává spropitné a neaktualizuje stav úhrady; kontext přijímá přeplatky, další platbu zaplaceného účtu i platbu zrušeného účtu. Částka s třemi desetinnými místy projde, příliš vysoká částka skončí databázovou výjimkou. Chybějící ceník lze obejít vlastní cenou a změna jednotkové ceny nemusí přepočítat mezisoučet. |
| `cozy_checkout/financial/sales_concurrency_test.exs` | Samostatná skutečná databázová spojení pro souběžné platby. Dvě platby stejného zůstatku mohou obě uspět; generovaná čísla různých plateb kolidují. |
| `cozy_checkout_web/live/financial/pos_payments_test.exs` | Hotovost, QR náhled a potvrzení, doplatek, PIN, opakované události, chyba ukládání a ruční přepočet. Účet 300 Kč s uhrazenými 100 Kč inkasuje další platbu 300 Kč místo 200 Kč. QR náhled ukládá úpravy před potvrzením; potvrzení přijme zastaralou částku. Neúspěšná platba ponechá změněné finanční údaje. Ruční přepočet ztrácí slevu i spropitné. |
| `cozy_checkout/financial/catalog_pricing_test.exs` | Platnost cen na hranicích období, neaktivní a smazané ceny, cenové úrovně, historická cena a DPH. Chybějící cenová úroveň může použít neodpovídající starou jednotnou cenu. |
| `cozy_checkout_web/live/financial/receipt_amounts_test.exs` | Shoda součtu základů a DPH s účtenkou a platbami; smazané položky a platby. Rekapitulace DPH nezohledňuje slevu a spropitné. |
| `cozy_checkout/financial/accounting_amounts_test.exs` | Shoda řádků ABRA a POHODA, hlavičky, rekapitulace a skutečných úhrad; poměrná sleva, spropitné, haléřové zaokrouhlení, smíšené platby a historické DPH. Exporty vynechávají finanční úpravy, seskupování slučuje rozdílné sazby a chybí odmítnutí nesouhlasících částek. Nepodporovaná sazba DPH se v ABRA vykáže jako osvobozená. |
| `cozy_checkout/financial/qr_code_test.exs` | Přesná částka, známý IBAN, SPD, shoda variabilního symbolu s ABRA a SVG. Český účet s předčíslím způsobí výjimku při převodu na IBAN. |
| `cozy_checkout/financial/abra_client_test.exs` | JSON požadavek, autentizace, cesta API, HTTP chyby, timeout a odpověď. HTTP 200 s importní chybou nebo bez platného ID dokladu se může považovat za úspěch. |
| `cozy_checkout/financial/abra_sync_test.exs` | Uložení ID a stavu synchronizace, opakování, ztracená odpověď, pokusy a konečné selhání workeru. Chybí odmítnutí nezaplaceného/zrušeného účtu a nesouhlasící částky před odesláním; retry po ztracené úspěšné odpovědi může vytvořit druhý doklad. |

Konkrétní příklad shody částek v exportech: položky 100 Kč při 0 %, 112 Kč při
12 % a 121 Kč při 21 %, sleva 33,30 Kč a spropitné 20 Kč. Celková částka,
součet řádků i úhrada musí být **319,70 Kč**. Sleva se rozdělí na 10 Kč,
11,20 Kč a 12,10 Kč; výsledná DPH činí 10,80 Kč a 18,90 Kč. Současné exporty
ponechávají řádky v hodnotě 333 Kč.

## Izolace a omezení

`test_helper.exs` směruje Req požadavky na `Req.Test`, takže se nikdy neodesílají
skutečné doklady. Testovací instance Oban běží bez front, pluginů, stagingu a
síťových notifikací; joby se pouze ukládají a worker se v testech volá explicitně.
Nejde o změnu produkční konfigurace ani aktualizaci databázového schématu.

Souběžné testy používají `Sandbox.unboxed_run` nad testovací databází a vlastní
spojení. Vytvořená data a joby po sobě uklidí. Výsledek závodu při přidělování
čísel může záviset na plánování procesů; chyba byla reprodukována při více
spuštěních s různými seedy. Test dvojího zaplacení používá rozdílná explicitní
čísla dokladů, aby kolize čísel nezakryla přeplacení.

První odpojené vykreslení POS aktuálně padá na `@order == nil`. Jeden test to
ověřuje přes skutečnou cestu `live/2`. Ostatní finanční testy POS nezávisle volají
veřejný připojený `mount/3` a skutečné `handle_event/3`, včetně autorizace PINem.
Tím nevydáváme testy handlerů za kompletní ověření funkčního uživatelského toku.
Účtenky se ověřují přes skutečné LiveView a DOM selektory.

ABRA komunikace je simulovaná na úrovni Req. Test ztracené odpovědi simuluje
vzdálený systém, který doklad uloží, ale vrátí timeout. Ověřuje požadavek na
idempotenci; nepotvrzuje chování konkrétního nasazeného ABRA serveru.
