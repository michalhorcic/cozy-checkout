# Ekonomika firmy

Economics je samostatný kontext pro čtení firemního účetnictví ABRA Flexi.
Nezávisí na Sales, Billing, bankovním zrcadle ani kalkulacích KitchenCosts.
Do ABRY provádí výhradně GET; nemění účetnictví, doklady ani platby.

## Konfigurace a první import

Výchozí stav je vypnuto. Nastavte explicitně:

```sh
ECONOMICS_ENABLED=true
ECONOMICS_ABRA_BASE_URL=https://vas-server.example
ECONOMICS_ABRA_COMPANY_ID=identifikator_firmy
ECONOMICS_ABRA_USERNAME=uzivatel_pro_cteni
ECONOMICS_ABRA_PASSWORD=heslo_z_bezpecneho_uloziste
```

Žádná hodnota se automaticky nepřebírá z provozní ABRY. Pro lokální ověření
lze výslovně namapovat již načtené `ABRA_*` z `rel/env.sh.eex` na stejnojmenné
`ECONOMICS_ABRA_*`; soubor s lokálními tajnými hodnotami necommitovat.
Použít API účet s právy číst účetní období, `ucet`, pohyby, předvahu a saldo.
Vyžadováno HTTPS. Před zapnutím aplikujte novou migraci; vznikají pouze
`economics_sources`, `economics_import_runs`, `economics_snapshots` a
`economics_confirmations`. Žádná existující obchodní tabulka se nemění.

`Economics.request_sync()` zařadí aktuální hospodářský rok podle skutečných
hranic v ABŘE; volitelné argumenty jsou kódy období. Počátek podpory je
1. 7. 2026; dřívější a budoucí období nelze importovat. Jednotlivý import
čte celý vybraný rok do konce aktuálního měsíce. Pozdější změny starších měsíců
se tak projeví při opakovaném importu.

Samostatná Oban fronta `economics_sync` má souběžnost 1, nejvýše 5 pokusů a
30minutový timeout. Cron ve 04:00 UTC obnovuje aktuální a dříve importovaná
období. Vypnutý modul neprovádí HTTP. Při změně cíle se staré ruční joby
zruší, nové importy a dotazy používají oddělený zdroj. Starší souběžný import
nesmí přepsat novější; zveřejnění chrání generační číslo a databázový zámek.

## Význam dat a kontrol

Čtecí kontrakt a živé kontrolní agregáty popisuje
[ECONOMICS_ABRA_CONTRACT.md](../integrations/ECONOMICS_ABRA_CONTRACT.md).
Pohyby se načítají měsíčně, `posted` a `unposted` zvlášť. Náklady jsou
MD − Dal nákladových účtů a výnosy Dal − MD výnosových účtů z firemního rozvrhu.
Nedaňové účty se nevylučují. Kategorizační mapování verze 1 je v
`Economics.AccountMapping`; neznámé kategorie jsou Nezařazeno a zůstávají
v součtech. Neznámý druh účtu, cizí měna, chybné datum, neúplná stránka,
ignorovaný filtr či nesoulad s předvahou zastaví publikaci nového snapshotu.
Prázdná měna u tuzemského pohybu se zobrazuje jako upozornění. Nezaúčtované
řádky nevstupují do výsledku; pokud nemají účet nebo úplná pole, nelze
jejich předběžné součty určit a nejsou vydávané za nulu.

Každý měsíc se kontroluje proti předvaze (`pocetMesicu=1`) po účtech a obou
stranách. Počátek předvahy se v tomto případě vztahuje k vybranému měsíci,
nikoliv automaticky k začátku roku. Kontroluje se počátek + MD − Dal = konec.
Zdroje nemají zaručený společný okamžik: časový rozsah importu je uložen,
kontroly snižují riziko souběžných změn, ale nedokazují vzdálenou atomicitu.

Banka a hotovost jsou účetní zůstatky analytik `221*` a `211*` z předvahy.
Nejde o potvrzení skutečné banky ani fyzické hotovosti; záporné hodnoty se
zachovávají. Podkladové analytiky a počátky jsou součástí reportu. Vztah
pokladen, počáteční stavy a bankovní výpis čekají na účetní ověření.

Historické pohledávky/závazky jsou předběžné: `sumCelkem − juhSumDat`, pouze
pokud `sumCelkemAkt` souhlasí s `sumCelkem`. Při rozdílu není celkový ukazatel
dostupný. Dnešní `zbyvaUhradit` se nepoužívá. Dobropisy jsou oddělené záporné
položky, nesnižují nesouvisející dluhy. Starší otevřené doklady se čtou bez
spodního omezení data. Částečné úhrady, dobropisy a import starších dluhů
vyžadují další nezávislé účetní srovnání před ostrým zapnutím.

## Obsluha v administraci

Po zapnutí je v navigaci Finance a přehledy položka **Ekonomika firmy**
(`/admin/economics`). Přehled, `/admin/economics/settings` i detail účtu
`/admin/economics/accounts/:account` chrání existující admin PIN a LiveView
session. Vypnutý modul přesměruje přímé otevření na admin přehled.

1. Na stránce Zdroj a úplnost zkontrolujte server a identifikátor firmy.
   Tlačítkem Načíst celé období zařaďte `current` nebo skutečný kód období
   z ABRY. Hesla se ve formulářích nezadávají ani nezobrazují.
2. Po dokončení jobu klikněte na Obnovit přehled. Obrazovka čte pouze místní
   snapshot a nespouští síťové dotazy. Chyba importu je viditelná i vedle
   posledních úspěšných dat.
3. Vyberte hospodářský rok a jeden či více měsíců; prázdné od/do znamená
   celý dostupný rozsah. Změna roku použije skutečné hranice jeho snapshotu.
4. Detail čísla účtu ukáže data účtování, strany MD/Dal a reference zápisů
   a dokladů ABRA, bez osobních popisů. Tabulka salda řadí položky podle
   splatnosti; dobropisy jsou oddělené od kladných pohledávek a závazků.
5. Na stránce Zdroj a úplnost lze po dohodě s účetní potvrdit jednotlivý
   ukončený měsíc a uvést podklad. Výchozí stav všech měsíců je Neověřeno.

Graf měsíčního vývoje se vykresluje serverově, bez nového JavaScriptu.
Peníze formátuje existující CurrencyHelper. Chybějící bankovní/pokladní
účty nebo nepodporované saldo se zobrazují jako Nedostupné, nikoli nula.

## Verze a úplnost

Nový snapshot vzniká bokem a publikuje se atomicky až po všech kontrolách.
Neúspěch ponechá poslední úspěšnou verzi. Identický import obnoví jen čas
kontroly, nevytvoří duplicitní report. Starší verze zůstávají zachované;
automatické mazání není zapnuté. Retenci a velikost reálných importů je nutné
stanovit před produkčním nasazením. Ukládají se jen finanční pole a reference,
nikoli adresy, osobní/mzdové popisy nebo celé původní HTTP odpovědi.

Technická čerstvost, shoda s předvahou a účetní úplnost jsou oddělené.
Potvrzení úplnosti vyžaduje uzavřený kalendářní měsíc a text podkladu
(minimálně 10 znaků). Jde o místní záznam po dohodě s účetní, nikoli uzamčení
ABRY. Změna dat měsíce jeho potvrzení zneplatní; záznam zůstane pro dohledání.
Potvrzení úplnosti neověřuje banku, fyzickou hotovost ani kontrakt salda.

Deaktivace přepínačem zastaví nové importy a skryje navigaci. Data zůstanou
uložená. Návrat ke starší aplikaci nevyžaduje mazání nových tabulek.
