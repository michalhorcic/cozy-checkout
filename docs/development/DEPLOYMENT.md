# Nasazení a provoz

## Docker release a migrace

Projekt se nasazuje přes Coolify pomocí kořenového [Dockerfile](../../Dockerfile).
Build sestaví produkční assets a Elixir release; runtime obsahuje Chromium
a fonty DejaVu pro PDF a běží jako uživatel `nobody`.

Výchozí příkaz `/app/bin/start.sh` nejprve spustí všechny čekající Ecto migrace
a pak Phoenix server. Postup je v [start.sh](../../rel/overlays/bin/start.sh),
[migrate](../../rel/overlays/bin/migrate), [server](../../rel/overlays/bin/server)
a [Release](../../lib/cozy_checkout/release.ex). Při vlastním příkazu kontejneru
nevynechte migrace; samotné `bin/cozy_checkout start` je neprovádí.
Produkční start nespouští development seed.

## Prostředí nasazení

Hodnoty nastavte v prostředí aplikace v Coolify. Runtime čte
[config/runtime.exs](../../config/runtime.exs); změna vyžaduje restart aplikace.
Přístupové údaje a hashe necommitujte.

| Proměnná | Účel |
| --- | --- |
| `DATABASE_URL` | Povinné produkční připojení PostgreSQL; bez něj aplikace nenastartuje. |
| `SECRET_KEY_BASE` | Povinné tajemství pro relace; generuje `mix phx.gen.secret`. |
| `PHX_HOST` | Skutečný hostname nasazení, používaný také pro kontrolu originu LiveView; výchozí `example.com` nahraďte. |
| `PORT` | Interní HTTP port, výchozí `4000`; nastavte odpovídající cíl proxy. |
| `PHX_SERVER` | Zapíná endpoint při přímém startu release; dodaný `bin/server` ho nastavuje sám. |
| `ADMIN_PIN_HASH` | Přístup do administrace a autorizace barových plateb; [vygenerování a relace](../features/ADMINISTRATION.md#admin-pin). |
| `POOL_SIZE`, `ECTO_IPV6`, `DNS_CLUSTER_QUERY` | Volitelné nastavení DB poolu, IPv6 databázového spojení a DNS clusteru. |
| `CHROME_EXECUTABLE` | Volitelná explicitní cesta k Chrome/Chromiu pro PDF. |

Endpoint v současné konfiguraci obsluhuje HTTP. TLS řeší proxy nasazení;
zkontrolujte doménu, HTTPS a spojení LiveView přes WebSocket. Nastavení
generovaných URL a originů je v `config/runtime.exs`.

## Integrace a první nastavení

| Oblast | Nastavení a provozní postup |
| --- | --- |
| Přihlášení a orientace | [Administrace a Admin PIN](../features/ADMINISTRATION.md) |
| Pobytové doklady | [Profil dodavatele, číselné řady a ceník](../features/BILLING.md#první-spuštění) |
| Pošta | `RESEND_API_KEY` a `EMAIL_FROM_ADDRESS`; [Emaily hostům](../features/GUEST_EMAILS.md) a [odesílání dokladů](../features/BILLING.md#pdf-pošta-a-provoz) |
| ABRA bar | `ABRA_*`; [konfigurace](../integrations/ABRA_INTEGRATION.md#konfigurace). Nemá vlastní vypínač; zaplacený účet zařazuje export. |
| ABRA ubytování a banka | `ABRA_ACCOMMODATION_ENABLED` a platné `ABRA_ACCOMMODATION_ENABLED_FROM`, připojení a účetní mapování; [celý postup](../integrations/ABRA_INTEGRATION.md). Výchozí stav vypnuto. |
| PDF přílohy v ABRA | `ABRA_PDF_ENABLED`; [samostatný návod](../integrations/ABRA_PDF_ATTACHMENTS.md). Výchozí stav vypnuto; zapnutí zahrnuje i historické synchronizované faktury. |
| Ekonomika firmy | `ECONOMICS_ENABLED` a vlastní `ECONOMICS_ABRA_*`; [konfigurace a první import](../features/ECONOMICS.md#konfigurace-a-první-import). Výchozí stav vypnuto. |
| iCal odběr | `BOOKING_ICAL_TOKEN`; [odběr kalendáře](../features/CALENDAR_VIEW.md#odběr-ical) |
| Barové QR a POHODA | Účet a identita v `config/config.exs`; [barové platby](../features/PAYMENT_FUNCTIONALITY.md#qr-a-konfigurace) a [POHODA](../integrations/POHODA_EXPORT.md#konfigurace-a-omezení) |

## Kontrola po nasazení a obnova

Ověřte start a migrace, veřejný POS, přihlášení do administrace, vytvoření
a stažení PDF a fronty Oban v `/admin/system`. Chyby účetních přenosů jsou také
v `/admin/billing/transfers`; přílohy PDF mají samostatný stav v detailu dokladu.
Poštu a účetní přenosy ověřujte na vlastních testovacích údajích a v testovací firmě.

Zálohujte PostgreSQL včetně tabulek `billing_*` s uloženými PDF a kontrolními
součty. [Uchování a kontrolu obnovy dokladů](../features/BILLING.md#pdf-pošta-a-provoz)
řešte spolu s databázovou zálohou; kopie Docker obrazu nenahrazuje data.
Před nasazením zachovejte předchozí obraz a ověřte zálohu. Návrat ke starému
obrazu vyžaduje posouzení kompatibility migrací a nově uložených dat;
nejde automaticky o rollback databáze.
