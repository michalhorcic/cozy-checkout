# Vývojové prostředí

## Runtime a závislosti

Používejte verze z [.tool-versions](../../.tool-versions): Elixir 1.20.4 a
Erlang/OTP 29.1. CI tento soubor čte přímo. Build argumenty `ELIXIR_VERSION`
a `OTP_VERSION` v [Dockerfile](../../Dockerfile) musí odpovídat stejným verzím;
[mix.exs](../../mix.exs) podporuje patch řadu Elixiru 1.20.

Na macOS může Homebrew spravovat mise a mise runtime projektu:

```sh
brew install mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
exec zsh
cd /path/to/cozy-checkout
mise install
elixir --version
```

Aktivaci mise stačí přidat do shellu jednou. `.tool-versions` umí číst také
asdf. Pokud přednost stále dostává runtime z Homebrew, zkontrolujte `which elixir`.

## PostgreSQL a první spuštění

Spusťte lokální PostgreSQL. [config/dev.exs](../../config/dev.exs) používá
`localhost`, roli `elixir` bez nakonfigurovaného hesla a databázi
`cozy_checkout_dev`. Role musí umět vytvářet databáze; pokud ještě neexistuje,
lze ji založit pod lokálním PostgreSQL administrátorem:

```sh
createuser --createdb elixir
```

Lokální autentizace PostgreSQL musí tomuto nastavení odpovídat; při použití
hesla upravte lokální konfiguraci. Proměnné `PGUSER` a `PGPASSWORD` níže se čtou
v testovací konfiguraci, nikoli v `config/dev.exs`.

Z kořene repozitáře:

```sh
mix setup
mix phx.server
```

`mix setup` provede `deps.get`, `ecto.setup`, `assets.setup` a `assets.build`.
`ecto.setup` vytvoří databázi, spustí migrace a `priv/repo/seeds.exs`.
Při dalším stažení změn podle potřeby spusťte `mix deps.get` a `mix ecto.migrate`.
Interaktivní server spustíte pomocí `iex -S mix phx.server`.

Výchozí adresa je `http://localhost:4000`, port lze změnit přes `PORT`.
Development server naslouchá na všech IPv4 rozhraních; berte to v úvahu
v lokální síti. Nastavení přístupu do administrace popisuje
[Admin PIN](../features/ADMINISTRATION.md#admin-pin).
Konfigurace v `runtime.exs` čte prostředí procesu; běžný `mix phx.server`
sám nenačítá soubor `.env`.

## PDF a lokální pošta

Pro skutečné PDF nainstalujte Chrome nebo Chromium a fonty s českou diakritikou.
Pokud prohlížeč není nalezen automaticky, nastavte `CHROME_EXECUTABLE`.
[Podrobný postup a řešení chyb](../features/BILLING.md#lokální-spuštění-pdf-a-mailboxu).
Pošta v developmentu používá Swoosh Local a je dostupná na `/dev/mailbox`;
nepotřebuje Resend klíč. PDF příloha se musí úspěšně připravit i pro lokální e-mail.

Barové platby mohou zařazovat export do ABRA i v developmentu; bar nemá
samostatný vypínač integrace. Používejte výslovně testovací cíl a přístupy podle
[návodu ABRA](../integrations/ABRA_INTEGRATION.md#konfigurace).
Pobytová integrace, PDF přílohy v ABRA a Economics jsou ve výchozím stavu vypnuté.

## Ověření změn

[config/test.exs](../../config/test.exs) čte `PGUSER`, `PGPASSWORD` a `PGHOST`
(výchozí hodnoty `postgres`, `postgres`, `localhost`). Pro lokální roli `elixir`:

```sh
MIX_ENV=test mix format --check-formatted
PGUSER=elixir PGPASSWORD='' mix test
PGUSER=elixir PGPASSWORD='' mix precommit
```

Test alias vytvoří databázi `cozy_checkout_test` a provede migrace.
`mix precommit` navíc kompiluje s `--warnings-as-errors`, kontroluje nepoužité
závislosti a formátuje projekt. Pro skutečné PDF potřebují testy stejný prohlížeč
jako aplikace. [Finanční sady a jejich hranice](FINANCIAL_TESTS.md).
[CI](../../.github/workflows/tests.yml) kontroluje bezpečnost závislostí,
formátování, kompilaci i celou testovací sadu s Chrome a PostgreSQL 17.
Pravidla, kdy mají agenti spouštět lokální testy, jsou v [AGENTS.md](../../AGENTS.md).

Dokumentace má samostatnou kontrolu `mkdocs build --strict`, bez databáze a Phoenixu;
[instalace a HTML náhled](DOCUMENTATION_WEB.md).

## Údržba závislostí

Každé 2–4 týdny projděte `mix hex.outdated` a `mix hex.audit`, přednostně
bezpečnostní opravy. Před cíleným `mix deps.update PACKAGE ...` přečtěte release notes;
změny `mix.exs` a `mix.lock` commitujte společně. Větší aktualizace a podporu
Elixiru/OTP kontrolujte čtvrtletně; runtime, Docker a CI aktualizujte společně.

Ověření aktualizace zahrnuje `mix precommit`, `mix hex.audit`,
`MIX_ENV=prod mix assets.deploy`, `MIX_ENV=prod mix release` a skutečné Chromium PDF.
Release před produkcí vyzkoušejte na stagingu. Návrat k obrazu a kompatibilitu
migrací popisuje [nasazení](DEPLOYMENT.md).
