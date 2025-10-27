# CozyCheckout

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

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