# Administrace

## Admin PIN

Kořenová adresa `/` a `/pos` otevírá veřejný samoobslužný bar. Provozní stránky
na `/admin`, systémový přehled i stahování pobytových PDF vyžadují přihlášení.
PIN se používá také k autorizaci plateb a rozdělení účtu v POS.

### Nastavení

Z kořene repozitáře v interaktivním terminálu spusťte:

```sh
mix admin.pin.hash
```

Zadejte PIN o **6–8 číslicích**. Příkaz vytvoří solený PBKDF2 hash a vypíše
řádek `ADMIN_PIN_HASH=…`. Vstup je skrytý; pokud terminál skrytý vstup
nepodporuje, příkaz na viditelné zadání upozorní. Hodnotu nastavte jako tajnou
proměnnou prostředí `ADMIN_PIN_HASH` před startem serveru, lokálně i při nasazení.
PIN ani hash necommitujte do repozitáře. Po změně prostředí aplikaci restartujte.
Bez platného hashe není přihlášení do administrace dostupné; výchozí PIN neexistuje.

### Přihlášení a zamknutí

Otevřete `/admin` nebo `/admin/login`. Pět chybných pokusů ze stejné klientské
adresy v pětiminutovém okně vyvolá minutové zablokování. Adresu určuje
`conn.remote_ip`; za proxy může být společná více klientům.

Správní relace platí nejvýše **12 hodin** a po **15 minutách bez aktivity
v administrativním LiveView** se zamkne. Průběžný heartbeat čas neprodlužuje.
Tlačítkem **Zamknout** v hlavičce administrace nebo v navigaci stravování ji
ukončíte ihned. Sdílený PIN nerozlišuje konkrétní obsluhující osoby.

Implementace: [AdminAuth](../../lib/cozy_checkout_web/admin_auth.ex),
[omezování pokusů](../../lib/cozy_checkout_web/admin_auth_rate_limiter.ex),
[generátor hashe](../../lib/mix/tasks/admin.pin.hash.ex) a
[runtime konfigurace](../../config/runtime.exs).

## Provozní přehled administrace

Úvodní přehled zobrazuje dnešní příjezdy a odjezdy, obsazenost podle stejných
pobytových položek jako kalendář a dnešní porce podle plánovače. Seznam pobytů
zahrnuje probíhající pobyty i příjezdy ode dneška do stejného dne příštího měsíce
včetně (na konci měsíce se datum zkrátí na poslední platný den). Zrušené,
dokončené a smazané pobyty se v seznamu nezobrazují. Přehled se obnovuje každou minutu.

Sekce **Vyžaduje pozornost** ukazuje chybějící údaje o stravování a nepřiřazená
nebo neaktuální menu u těchto pobytů; odkazy vedou přímo k opravě. Obsazenost
lůžek a porce jsou nezávislé veličiny, například odjezdová snídaně se počítá do
porcí, ale odjíždějící skupina už do obsazenosti daného dne nevstupuje.

Hlavní navigace je dostupná napříč administrací a upřednostňuje rezervace,
stravování a barový sklad. Méně časté nástroje jsou seskupeny pod **Další agenda**,
technické nástroje pod **Systém**. Ve stravování zůstává jeho vlastní menu;
přechod do ostatních oblastí je pod **Přejít do jiné oblasti**.

Při zapnuté [Ekonomice firmy](ECONOMICS.md#úvodní-přehled-úkoly-a-grafy) obsahuje
přehled také účetní ukazatele a upozornění na splatnosti a stav importu.
Chybějící podklady se zobrazují jako nedostupné, nikoli nulové.
Nasazení, prostředí a migrace popisuje [provozní návod](../development/DEPLOYMENT.md).
