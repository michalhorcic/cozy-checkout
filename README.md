# CozyCheckout

## Elixir and Erlang versions

Use the versions pinned in `.tool-versions` (Elixir 1.20.4 / Erlang/OTP 29.1).
CI reads this file; keep the `ELIXIR_VERSION` and `OTP_VERSION` arguments in
`Dockerfile` aligned with it. The application supports the Elixir 1.20 patch line.

On macOS, Homebrew can manage mise while mise manages the project's runtimes:

```sh
brew install mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
exec zsh
cd /path/to/cozy-checkout
mise install
elixir --version
```

Activate mise once in your shell. It reads `.tool-versions` automatically; asdf
can use the same file. `brew upgrade` can then update Homebrew packages without
selecting a different runtime for this project. Check `which elixir` if the
Homebrew installation still takes precedence.

Review dependencies every 2–4 weeks with `mix hex.outdated` and `mix hex.audit`.
Prioritize security fixes and read release notes before selecting updates with
`mix deps.update PACKAGE ...`. Commit both `mix.exs` and `mix.lock` when they
change. Review Elixir/OTP support and larger dependency upgrades quarterly;
update runtime pins, Docker and CI together in a dedicated PR when practical.
Validate with `mix precommit`, `mix hex.audit`, `MIX_ENV=prod mix assets.deploy`
and `MIX_ENV=prod mix release`, including real Chromium PDF tests. Test a release
on staging before production and retain the previous image for rollback; database
migrations need their own compatibility and backup review.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

## Admin PIN

The root URL opens the POS. All `/admin` pages require a PIN; the POS remains public. Generate a salted PBKDF2 hash with `mix admin.pin.hash` (the PIN is entered without echo) and configure the printed `ADMIN_PIN_HASH` value as an environment secret before starting the server. Do not commit the hash to the repository.

The PIN must contain 6 to 8 digits. Five incorrect attempts from the same client address trigger a one-minute lockout. An authenticated admin session expires after 12 hours and locks after 15 minutes without activity in an admin LiveView. Use **Zamknout** in the admin header (or food navigation) to end the session immediately.

## Dokumentace

Dokumentaci lze procházet také jako [HTML web s menu a vyhledáváním](docs/development/DOCUMENTATION_WEB.md).

[Rozcestník dokumentace](docs/README.md) obsahuje provozní návody, technické
podklady a [plány nových funkcí](docs/plans/README.md).

- [Administrace a provozní přehled](docs/features/ADMINISTRATION.md)
- [Grafické postupy práce s aplikací](docs/features/WORKFLOWS.md)
- [Samoobslužný bar / POS](docs/features/POS_SYSTEM.md) a [platby](docs/features/PAYMENT_FUNCTIONALITY.md)
- [Fakturace pobytů](docs/features/BILLING.md)
- [Stravování, receptury a nákup](docs/features/CATERING.md)
- [Emaily hostům](docs/features/GUEST_EMAILS.md)
- [Kalendář rezervací](docs/features/CALENDAR_VIEW.md)
- [Import iCal](docs/integrations/ICAL_IMPORT.md) a [export POHODA](docs/integrations/POHODA_EXPORT.md)
- [Integrace s ABRA Flexi](docs/integrations/ABRA_INTEGRATION.md)
- [Finanční regresní testy](docs/development/FINANCIAL_TESTS.md)

## Ověření změn

Lokální testy používají PostgreSQL roli `elixir`:

```sh
PGUSER=elixir PGPASSWORD='' mix precommit
```

Pro testy skutečných PDF je potřeba Chrome nebo Chromium; nastavení popisuje
[návod k fakturaci](docs/features/BILLING.md#lokální-spuštění-pdf-a-mailboxu).

Aplikace běží na [localhost:4000](http://localhost:4000), lokální emaily jsou
v [development mailboxu](http://localhost:4000/dev/mailbox).

Repozitářové instrukce pro agenty zůstávají v [AGENTS.md](AGENTS.md).
