# Ověření fakturace ubytování s účetní

Tento postup slouží ke společnému ověření fakturace s účetní. Export konečné
faktury používá stejné připojení jako ostatní doklady ubytování. Účetní mapování
je stále potřeba ověřit; číslování, snapshoty a uložená PDF vycházejí z místních
dokladů.

## Co již vychází z podkladů a co je pracovní předpoklad

| Oblast | Podklad a stav |
| --- | --- |
| Výzva, ZDD, bankovní příjem | Navazuje na zkušebně ověřený předchozí cyklus. Každá platba má svůj ZDD. |
| Celá cena pobytu a částky odpočtů | Neměnné místní doklady; export je nepřepočítává podle dnešního ceníku. |
| Výnos ubytování a rekreační poplatek | Účty na položkách převzaté z dodané výzvy: ubytování 602001, poplatek 345100. Přenos na konečnou fakturu musí posoudit účetní. |
| Typ konečné faktury | Pracovní výchozí kód `FAKTURA`. Musí existovat v testovací firmě; lze ho změnit konfigurací. Nejde o odvození z účetního vzoru finální faktury. |
| Účet pohledávky, předpis a daňové účty finální faktury | Přebírají se z typu dokladu ABRA. Zatím nejsou doložené vzorem; účetní musí zkontrolovat jejich správnost. |
| Řádky DPH a KH | Pracovní výchozí hodnoty podle ZDD pro zdaněné ubytování; poplatek používá členění bez vlivu na DPH podle výzvy. Posoudit na vyúčtování a odpočtech. |
| Odpočty | Po jednotlivých ZDD, s explicitními základy, stabilními externími ID a režimem převzetí původních sazeb. Tvar požadavku a chování konkrétní verze API se zde dosud živě neověřily. |
| Zaokrouhlení | Haléřové částky místních dokladů, bez automatického přijímání doporučených změn nebo zaokrouhlení na koruny. |

## Zapnutí exportu

Spusťte přidávací migraci `20261026180000_add_accommodation_export_verification.exs`
a migraci `20261026180100_normalize_final_export_kind.exs`, která sjednotí
interní označení existujících exportů bez změny jejich účetních podkladů.
Pro zapnutí doplňte ke stávajícímu nastavení ubytování:

```sh
ABRA_ACCOMMODATION_FINAL_ENABLED=true
```

URL, firma a přístupy se přebírají ze stávající konfigurace ABRA pro ubytování;
znovu se nezadávají. Typ faktury lze případně upravit pomocí
`ABRA_ACCOMMODATION_FINAL_TYPE_CODE` (výchozí `FAKTURA`). Musí být odlišný
od výzvy a ZDD. Již uložený export zůstává vázaný na původní URL a firmu,
takže jej změna připojení nepřesměruje.

Při přechodu ze starší konfigurace přejmenujte případné vlastní parametry
na aktuální prefix uvedený níže. Samostatné nastavení cíle pro konečné faktury
se již nepoužívá.

Další proměnné s prefixem `ABRA_ACCOMMODATION_FINAL_`:
`VAT_CODE`, `VAT_REPORT_CODE`, `SERVICE_ACCOUNT`, `FEE_ACCOUNT`,
`OUTSIDE_VAT_CODE`, `OUTSIDE_VAT_REPORT_CODE`. Výchozí hodnoty jsou pracovní
mapování popsané výše a v `config/runtime.exs`.

## Doporučený průchod

1. V aplikaci vytvořte nový testovací pobyt. Použijte snadno kontrolovatelnou
   kalkulaci: ubytování 11 200 Kč včetně 12% DPH a poplatek mimo DPH 200 Kč.
   Celkem 11 400 Kč.
2. Vystavte a exportujte výzvu na 11 400 Kč. V testovací ABRA připravte dva
   samostatné bankovní příjmy se stejným VS: 5 700 Kč a 2 850 Kč. Všechny platby
   musí být před dokončením pobytu; DUZP konečné faktury jim nesmí předcházet.
3. Oba příjmy načtěte a postupně potvrďte. Vyčkejte dokončení účetního přenosu
   každého ZDD. Zkontrolujte bankovní úhrady výzvy a vazby obou ZDD.
4. Vystavte místní konečnou fakturu. V náhledu musí být celá cena pobytu
   11 400 Kč, odpočty obou ZDD a částka k doplacení 2 850 Kč.
5. V detailu konečné faktury použijte **Exportovat do ABRA** v sekci
   **ABRA · ubytování**. **Obnovit stav exportu** načte výsledek.
6. V ABRA zkontrolujte fakturu, jednotlivé odpočty, zdrojové ZDD i jejich
   zbývající částky k odpočtu. Uložte XML faktury včetně položek a vazeb pro
   další doladění. Úspěch aplikace znamená shodu kontrolovaných dat, nikoli
   schválení účtování účetní.

Orientační částky pro tento jednoduchý případ:

| Doklad | Základ 12 % | DPH 12 % | Poplatek mimo DPH | Celkem |
| --- | ---: | ---: | ---: | ---: |
| Celý pobyt | 10 000 Kč | 1 200 Kč | 200 Kč | 11 400 Kč |
| První ZDD | 5 000 Kč | 600 Kč | 100 Kč | 5 700 Kč |
| Druhý ZDD | 2 500 Kč | 300 Kč | 50 Kč | 2 850 Kč |
| Zůstatek po odpočtech | 2 500 Kč | 300 Kč | 50 Kč | 2 850 Kč |

V konečné faktuře musí být první dva ZDD skutečnými odpočty, nikoli novým
příjmem, obyčejnými slevami nebo samostatnými zápornými položkami bez vazby.

## Případy pro společné ověření

- **Základní:** jedna záloha, dvě samostatné zálohy, žádná záloha,
  celá cena pokrytá zálohami a nulový doplatek.
- **Částky:** haléře, několik sazeb, rekreační poplatek mimo DPH,
  rozdílný rozpis aktuální služby a již zdaněných záloh. Ověřit původní
  základy a DPH, nejen konečný součet.
- **Účetnictví:** účet pohledávky, výnosy, poplatek, DPH, KH, datum vystavení,
  DUZP, splatnost, správná čísla a VS i zůstatky saldokonta.
- **Odolnost:** opakovaný export, ztracená odpověď, ZDD již odečtené jinde,
  změněné ZDD, nesprávná vazba a odlišná daň v odpovědi. Přenos se při
  neshodě zastaví, nevytváří opravnou platbu ani automaticky nepřepisuje doklad.
- **Zatím nepodporované:** přeplatek nad cenu pobytu, místní vratky a opravy,
  zdrojové ZDD bez dokončeného bankovního přenosu, zdanitelná nula a další
  sazby. Tyto případy mají skončit vysvětlením a pro další implementaci
  potřebujeme účetní postup/vzor.

Tento blok nezahrnuje potvrzení a export doplatku konečné faktury. Na přenesené
faktuře je ponechána částka k úhradě; její potvrzení bude další samostatná etapa.
Fakturu s již místně zaznamenaným doplatkem export odmítne.
Před zapnutím pro ostrou firmu je nutné schválit mapování a ověřit celý
finanční cyklus včetně doplatků, oprav a vratek.

## Omezení automatického ověření

Kontrola porovnává číslo, VS, termíny, zákazníka, měnu, celkové i daňové
zůstatky, původní položky s výnosovými účty, součty odpočtových položek a
vazbu/částku ke každému zdrojovému ZDD. Ověření úplného konkrétního účtování
odpočtových položek a rozdělení jejich DPH po jednotlivých zdrojích je úkolem
společného testu s účetní; součtová kontrola ho nenahrazuje.

HTTP probíhá mimo místní transakce. Před vytvořením se kontrolují zbývající
částky ZDD; ABRA může být mezi čtením a zápisem změněna jiným uživatelem.
Následná kontrola proto může skončit chybou i po vytvoření dokladu. V takovém
případě nepřidávejte nový export ani nepřepisujte vydaný doklad, ale dohledáme
konkrétní rozdíl. Opakování nejprve vyhledá existující fakturu podle externího ID.
Projektové testy nebyly lokálně spuštěny podle AGENTS.md; výsledky CI ověří
uživatel. Živé API cílové firmy ověří uživatel s účetní na lokálu.
