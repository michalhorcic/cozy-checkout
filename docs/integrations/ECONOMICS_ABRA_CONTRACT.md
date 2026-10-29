# Economics: ověřený čtecí kontrakt ABRA Flexi

Ověřeno 29. 10. 2026 proti instanci určené lokálním `rel/env.sh.eex`, pouze
GET. Přístupové údaje a odpovědi s osobními údaji nejsou součástí repozitáře.
Toto ověření není potvrzení úplnosti účetnictví, licence všech funkcí ani
shody testovací firmy s produkcí.

## Evidence a pole

Všechny níže uvedené evidence odpověděly HTTP 200 a JSON obálkou
`{"winstrom":{"@version":"1.0","<evidence>":[...]}}`.
`@version` je verze formátu, nikoliv verze instalace ABRY.

| Evidence | Kontrakt pro Economics |
| --- | --- |
| `ucetni-obdobi` | `kod`, `platiOdData`, `platiDoData`; období `2026` je 1. 7. 2026–30. 6. 2027, `2025` je 1. 7. 2025–30. 6. 2026 |
| `ucet` (firemní účtový rozvrh) | `kod`, `nazev`, `typUctuK`, `druhUctuK`; druhy `druhUctu.naklady` a `druhUctu.vynosy` jsou rozhodující pro výsledovku |
| `pohyb-na-uctech` | `idUcetniDenik`, `idDokl`, `modul`, `ucet`, `protiUcet`, `datUcto`, `sumTuzMd`, `sumTuzDal`, `zuctovano`, `mena` |
| `ucetni-denik` | Dostupný alternativní zdroj, ale MD/Dal v jednom řádku; pro první verzi preferujeme pohyby na účtech |
| `obratova-predvaha`, `hlavni-kniha` | `ucet`, `ucetniObdobi`, `mena`, `pocatekMd`, `pocatekDal`, `pocatekMesic`, `obratMdVyb`, `obratDalVyb`, `zustatekMd`, `zustatekDal` |
| `stav-uctu` | Dostupná měsíční pole `obratMd01`…`obratMd23` a `obratDal01`…`obratDal23`; jejich indexování v hospodářském roce zatím nepoužíváme |
| `saldo-k-datu` | `idSaldoKdatu`, `idDokl`, `modul`, `datUcto`, `datSplat`, `sumCelkem`, `sumCelkemAkt`, `juhSumDat`, `mena`, `storno` |

Evidence `ucetni-osnova` také odpověděla, ale obsahuje obecnou osnovu
s třímístnými kódy. Pro firemní analytiky z pohybů se musí použít `ucet`.

Čísla jsou desetinné řetězce. Reference účtů/měn mají tvar `code:602001`,
`code:CZK`; datum například `2026-09-30+02:00`. `zuctovano` je řetězec
`"true"`. U některých tuzemských pohybů ABRA vrací prázdnou měnu: takový údaj
musí mít viditelné upozornění, nelze jej vydávat za potvrzenou měnu dokladu.
Částky `sumTuz*` jsou tuzemské částky; cizí měny se nikdy tiše nesčítají.

## Filtry, stránkování a kontrola

- `detail=custom:<pole>`, `limit` a `start` fungují. Ověřené sondy použily
  `limit=2` a pro kontrolní součty `limit=0`. Implementace používá omezené
  stránky a strop počtu stránek; `limit=0` není produkční strategie.
- `pohyb-na-uctech/(datUcto >= 2026-09-01 and datUcto <= 2026-09-30)`
  s `postingState=posted` vrátil 702 řádků, všechny v září a `zuctovano=true`.
  `unposted` v tomtéž rozsahu vrátil prázdný seznam, neplatný stav HTTP 400.
  Prázdné nezaúčtované období neověřuje chování neprázdného případu.
- Předvaha: `ucetniObdobi=code:2026`, `koncovyMesicRok=09/2026`,
  `pocetMesicu=3`. Bez filtru účtů, středisek či daňovosti.
- Saldo: `datum=2026-09-30`, `dleUcto=true`; neomezovat dolní datum, aby
  nevypadly starší neuhrazené položky. Moduly FAV/PHL jsou pohledávky,
  FAP/ZAV závazky. Identita musí zahrnout modul a zdrojový `idDokl`.
- Zakázány přepočty, párování a všechny HTTP zápisy. Přesměrování ani
  transportní retry klient neprovádí; retry importu řídí Oban.

### Kontrolní součty

| Období | Výnosy Dal − MD | Náklady MD − Dal |
| --- | --- | --- |
| 07/2026 | 159 584,06 | 75 591,72 |
| 08/2026 | 23 085,30 | 123 629,36 |
| 09/2026 | 42 890,58 | 444 045,69 |
| Součet / předvaha červenec–září | 225 559,94 | 643 266,77 |

Měsíční pohyby souhlasí s předvahou a agregáty v plánu. Rozdíl je
−417 706,83 Kč. Nejde o schválený konečný výsledek firmy.
Předvaha pro `211001` vrací počátek MD 5 150 Kč; další dvě sledované
analytiky mají počátky nula. Konečné stavy souhlasí s plánem. Význam
počátků, dvou pokladen a bankovního zůstatku musí stále potvrdit účetní.

### Historické saldo: důležitý rozdíl

Pole `zbyvaUhradit` je dnešní zbývající úhrada: v živé odpovědi může být
nula, i když `juhSumDat` (Uhrazeno k datu) je nula a doklad k historickému
konci uhrazený nebyl. Pro historický výpočet se nesmí použít dnešní zůstatek.
`sumCelkemAkt` je podle `/saldo-k-datu/properties.json` „Aktuální hodnota
faktury [Kč]“. Ve vzorku se shodovalo se `sumCelkem`, žádný rozdílný ani
částečně uhrazený případ neověřil dobropisy a opravy. Do potvrzení těchto
případů musí být historické saldo zřetelně označené jako předběžné; rozdílné
hodnoty nelze bez vysvětlení použít jako ověřený stav.

## Veřejné zdroje

- [Účetní výstupy REST API](https://podpora.flexibee.eu/cs/articles/4971496-ucetni-vystupy-v-rest-api)
- [Pohyby a postingState](https://demo.flexibee.eu/devdoc/pohyb-na-uctech)
- [Saldo k datu](https://demo.flexibee.eu/devdoc/saldo-k-datu)

Neznámé parametry mohou být ignorovány i při HTTP 200. Klient a import proto
ověřují obálku, data, stav zaúčtování a součty; dostupnost URL nestačí.

## Identifikační údaje (ověřeno 29. 10. 2026)

V obou evidencích lze ve stejném GET vyžádat `nazFirmy`, `firma`, `popis`,
`varSym` a `cisDosle`. Pohyby navíc vracejí lidské číslo v `doklad` a popisek
protiúčtu v `protiUcet@showAs`; saldo má lidské číslo v `kod`. Vzorky běžných
pohybů, pohybů na účtu 604001 a denního salda odpověděly HTTP 200; názvy,
čísla a popisy byly neprázdné. Soukromé hodnoty vzorků se neukládají do Gitu
ani logů. `firma@showAs` slouží jen jako záložní název firmy, nikoli klíč pro
sériové načítání adresáře. Žádné další GET pro jednotlivé doklady nevznikají.

Klient stále čte pouze výslovně vyjmenovaná pole. Volné poznámky, adresy,
kontaktní údaje ani kompletní doklad se kvůli identifikaci nepřebírají.
Chybějící identifikační pole nebrání finančnímu importu; požadavky na částky,
kontrolní součty, účetní typy a datumové filtry se nemění.
