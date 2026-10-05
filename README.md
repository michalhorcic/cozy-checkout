# CozyCheckout

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

## Admin PIN

The root URL opens the POS. All `/admin` pages require a PIN; the POS remains public. Generate a salted PBKDF2 hash with `mix admin.pin.hash` (the PIN is entered without echo) and configure the printed `ADMIN_PIN_HASH` value as an environment secret before starting the server. Do not commit the hash to the repository.

The PIN must contain 6 to 8 digits. Five incorrect attempts from the same client address trigger a one-minute lockout. An authenticated admin session expires after 12 hours and locks after 15 minutes without activity in an admin LiveView. Use **Lock Admin** on the dashboard to end the session immediately.

## Emaily hostům

Rozesílání hostům je dostupné v administraci v sekci **Email Guests**. Zprávy se řadí do Oban fronty; stránka po zařazení zobrazuje stav aktuální rozesílky. Každý příjemce obdrží samostatný email.

Produkční nasazení potřebuje následující proměnné:

* `RESEND_API_KEY` – tajný API klíč účtu Resend.
* `EMAIL_FROM_ADDRESS` – ověřená adresa odesílatele; výchozí hodnota je `jindrichuvdum@jindrichuvdum.cz`.

Před prvním odesláním přidejte doménu `jindrichuvdum.cz` do Resendu a nastavte DNS záznamy, které Resend pro ověření domény zobrazí. Bez platného API klíče je odesílání v produkci vypnuté; chybějící secret nebrání startu aplikace.

HTML těla šablon jsou verzovaná v `priv/email_templates/pre_arrival/`. Pro přidání další šablony přidejte HTML soubor vhodný pro emailové klienty a její metadata (identifikátor, popis, výchozí předmět, jazyk a sezónu) do `CozyCheckout.GuestEmails.TemplateCatalog`. Interaktivní náhled `priv/static/email_pred_prijezdem.html` slouží pouze jako zdroj obsahu a není přímo odesílán.

V administraci lze místo šablony napsat vlastní prostý text; v emailu se bezpečně převede do HTML a zároveň zůstane dostupný jako textová alternativa. Při zařazení do fronty se uloží přesný obsah zobrazený v náhledu, takže pozdější úprava souboru šablony již nezařazené emaily nezmění. V development prostředí se emaily zachytávají lokálně a lze je zobrazit na `/dev/mailbox`; skutečné odesílání přes Resend je nakonfigurované pouze v produkci.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix


How to setup sql server:
Steps to Configure PostgreSQL for Local Network Access
1. Locate and Edit pg_hba.conf
The file location varies by system:

Linux (Debian/Ubuntu): /etc/postgresql/17/main/pg_hba.conf
Linux (Red Hat/CentOS): /var/lib/pgsql/17/data/pg_hba.conf
macOS (Homebrew): pg_hba.conf or /usr/local/var/postgresql@17/pg_hba.conf
Docker: Inside the container at /var/lib/postgresql/data/pg_hba.conf
2. Add Configuration for Local Network
Add these lines to allow password authentication from your local network:

Replace 192.168.1.0/24 with your actual local network range. Common ranges:

192.168.0.0/24 (192.168.0.1 - 192.168.0.254)
192.168.1.0/24 (192.168.1.1 - 192.168.1.254)
10.0.0.0/8 (10.0.0.1 - 10.255.255.254)
3. Edit postgresql.conf to Listen on Network
Find and edit postgresql.conf (same directory as pg_hba.conf):

# Listen on all interfaces (default is localhost only)
listen_addresses = '*'

# Or specify your local network IP
listen_addresses = '192.168.1.100'  # Your server's IP


sudo systemctl restart postgresql