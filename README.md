# AutomaticPatch — Ruby bundled gem CVE auto-PR bot

Rails 8 app that detects vulnerabilities affecting Ruby default/bundled gems
(`ruby/ruby:gems/bundled_gems`) and prepares **human-reviewable** bump candidates.

PR creation is designed to be conservative and **human-gated**.

## Requirements

- **Ruby**: `3.4.7` (see `.ruby-version`)
- **PostgreSQL**: required for development/test/production
- **Docker**: optional (handy for running Postgres locally)
- **GitHub CLI (`gh`)**: required for GHSA ingestion and PR syncing (and later PR creation)

## Setup (local)

Install gems and prepare the DB:

```bash
bin/setup
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=
bin/rails db:prepare
```

Run the dev server + Tailwind watcher:

```bash
bin/dev
```

Admin UI is under:
- `GET /admin` (requires sign-in)
- `GET /sign_in`

## Tests and lint

```bash
bin/rubocop
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=
bin/rails db:test:prepare
bundle exec rspec
```

## Background jobs (Solid Queue)

- **Local**: run the worker:

```bash
bin/jobs
```

- **Recurring schedules**: defined in `config/recurring.yml` (branch refresh, GH sync, evaluation, cleanup).

## Environment variables

### Admin UI
Admin auth is **session-based** (single operator). Create the user via console:

```bash
bin/rails console
AdminUser.create!(username: "dan1d", password: "change-me", password_confirmation: "change-me")
```

### PostgreSQL
This app uses multiple DBs (primary/cache/queue/cable) in `config/database.yml`.

Common vars:
- **`PGHOST`**, **`PGPORT`**, **`PGUSER`**, **`PGPASSWORD`**

Optional per-DB overrides:
- **`PRIMARY_DB_NAME`**, **`CACHE_DB_NAME`**, **`QUEUE_DB_NAME`**, **`CABLE_DB_NAME`**

### GitHub (required)
Used for GHSA ingestion (`gh api graphql`) and PR sync (`gh api`).

- **`GH_TOKEN`**: token used by `gh` inside the app container/process

Notes:
- The token must correspond to **`dan1d`** if you want PRs authored by `dan1d`.
- For PR creation, the token must be able to open PRs to `ruby/ruby` (and read the fork branch).

### Git (SSH for pushing fork branches)
PR creation pushes a head branch to the fork via **SSH** (e.g. `git@github.com:dan1d/ruby.git`).

- Ensure the runtime has an SSH key that can push to `dan1d/ruby`.
- Optional: **`GIT_SSH_COMMAND`** to force a specific key / host key policy.

### DeepSeek (optional, best-practice cross-check)
- **`DEEPSEEK_API_KEY`**: enables DeepSeek features when set
- **`DEEPSEEK_API_URL`**: optional override (default: `https://api.deepseek.com/chat/completions`)
- **`ENABLE_DEEPSEEK_RUBYLANG_FALLBACK`**: set to `true` to allow AI fallback for parsing ruby-lang announcement pages when deterministic parsing fails

DeepSeek is **never authoritative**; outputs are validated and the system fails closed.

## Deployment (DigitalOcean) with Kamal

This repo includes a Kamal config at `config/deploy.yml`.

### 1) Configure servers and registry
- Update `servers.web` in `config/deploy.yml` to your Droplet IP(s).
- Configure an image registry (recommended: `ghcr.io` or Docker Hub) in `config/deploy.yml`.

### 2) Configure secrets
Kamal reads secrets from `.kamal/secrets` (do not commit real tokens).

Required:
- `RAILS_MASTER_KEY`
- `GH_TOKEN`
- Postgres vars (`PGHOST`, `PGUSER`, `PGPASSWORD`, etc.)

Optional:
- `DEEPSEEK_API_KEY`
- `ENABLE_DEEPSEEK_RUBYLANG_FALLBACK=true`

### 3) Database
Provision Postgres yourself (managed DB or self-hosted) and set the `PG*` env vars.

### 4) Deploy

```bash
bin/kamal setup
bin/kamal deploy
```

### 5) Jobs in production
`config/deploy.yml` currently runs Solid Queue in Puma (`SOLID_QUEUE_IN_PUMA: true`).
For higher volume, split jobs into a separate role and run `bin/jobs` on job servers.

## Repo targeting defaults
- **Upstream**: `ruby/ruby`
- **Fork**: `dan1d/ruby` (SSH: `git@github.com:dan1d/ruby.git`)

## Safety model
- Minimal diffs only (1-line change to `gems/bundled_gems`)
- Rate caps and cooldowns enforced via `BotConfig`
- Fail-closed on ambiguity/outages; errors are logged to `SystemEvent` and shown on the admin dashboard
