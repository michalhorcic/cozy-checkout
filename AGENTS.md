# Cozy Checkout — agent instructions

Self-service POS and guesthouse management for Jindřichův dům.
Stack: Elixir, Phoenix 1.8 / LiveView, PostgreSQL, Oban, Tailwind CSS v4
and daisyUI; Docker deployment through Coolify.

## Maintaining instructions

- `AGENTS.md` owns repository-wide agent instructions; `.github/copilot-instructions.md` points here.
- Before adding any new instruction, show the user its proposed wording and ask for explicit approval. Wait for approval before writing it, including additions to existing bullets or sections. Development changes do not automatically authorize additions.
- Keep this file concise. Do not duplicate behaviour evident from code, tests or feature documentation, or record individual UI decisions and feature history. Remove obsolete or contradictory guidance.

## Development

- Before starting work, fetch the latest `origin/main` and base new work on its latest commit. When continuing an existing branch, first compare it with the freshly fetched `origin/main` and reconcile relevant changes.

- Inspect the relevant implementation, schemas, migrations and tests first. Follow existing patterns, keep business logic in contexts, and prefer simple solutions. Ask when a material business requirement cannot be resolved from the repository.
- V příštích pracích si hlídej N+1 problém. Vždy na něj upozorni a nech si schválit efektivnější řešení.
- Keep guest-facing POS flows simple, touch-friendly and short; administrative complexity belongs in admin screens.
- Preserve existing admin PIN authentication for admin routes, LiveViews and billing downloads; POS stays public. Do not assume generated Phoenix account authentication exists.
- Use Ecto migrations for schema changes; preserve UUID keys, timestamps, database constraints and soft deletes on business records.
- Use existing helpers and dependencies, including `Req` for HTTP and Oban for retryable background work. External operations must tolerate failures and retries. Never hardcode secrets, credentials or production URLs.
- Follow the existing light theme, shared layouts and components (`Layouts.app`, `.input`, `.icon`). Keep JavaScript in `assets/js`, imported through `app.js`, rather than adding inline scripts; preserve the existing theme-bootstrap exception.
- V UI musí být select s více než 30 položkami vyhledávatelný; používej existující sdílenou komponentu, pokud je vhodná.

## Financial integrity

- Use `Decimal` and existing financial helpers; format money and numbers with `CozyCheckoutWeb.CurrencyHelper`.
- Preserve historical prices, quantities and VAT snapshots. Catalog changes must not rewrite past purchases; issued documents and stored PDFs remain immutable.
- Preserve transaction locks, unique numbering and idempotency for payments, billing and accounting synchronization. Keep bar accounting separate from accommodation billing.
- Stay calculations and their legacy states are not issued documents or proof of payment. Derive financial states from issued documents and recorded payments/refunds. Preserve gross/net distinctions and the existing VAT, discount and tip rules.
- Test HTTP integrations through `Req.Test`; tests must not create real accounting documents or send real guest emails.

## Validation and delivery

- Use the Elixir and Erlang versions pinned in `.tool-versions`, matching CI. After code changes, run `MIX_ENV=test mix format <changed files>` from the repository root with dependencies installed, so `.formatter.exs`, dependency rules and the HEEx plugin apply. Before committing, run `MIX_ENV=test mix format --check-formatted` across the project and fix all reported differences. Formatting checks are required even when local tests are left to CI; `git diff --check` and manual whitespace edits do not replace the formatter. If the pinned toolchain is unavailable, report that limitation instead of claiming CI-compatible formatting was verified.
- Add or update tests for business-logic changes. By default, leave test execution to GitHub CI; do not run local tests or `mix precommit`, wait for CI completion, or poll its status. Run local tests only when explicitly requested or necessary to reproduce and fix the issue being addressed. State in the PR and final response that local tests were not run and the user will verify CI results, or report any local tests actually run.
- Local PostgreSQL uses the `elixir` role: `PGUSER=elixir PGPASSWORD='' mix test` (or `mix precommit` with the same environment).
- Create a feature branch, commit, push and open a pull request without additional confirmation unless the user requests otherwise. Include checks and verification limits in the PR.
- Explain the result and validation; mention migrations, configuration changes and breaking changes when applicable.

## References

- `README.md`: setup and feature workflows.
- `docs/features/BILLING.md`: accommodation billing, configuration and operational limits.
- `docs/development/FINANCIAL_TESTS.md`: financial regression coverage and commands.
- `docs/integrations/ICAL_IMPORT.md`, `docs/integrations/POHODA_EXPORT.md`: integration details.
- For feature details and framework usage, consult the relevant code, tests and documentation rather than expanding these instructions.
