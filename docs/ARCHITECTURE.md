# VulnSentry architecture / “how it works”

VulnSentry is a Rails 8 app that watches **Ruby’s bundled/default gems list** (`ruby/ruby:gems/bundled_gems`), correlates it with vulnerability data (GHSA + OSV + ruby-lang announcements), and produces **human-reviewable** bump candidates. When approved, it can automatically open a PR against `ruby/ruby`, then continuously sync PR state + comments for visibility and cleanup.

This document explains the runtime behavior, the main building blocks, and how everything is orchestrated in production.

---

## Goals and safety model

- **Human-gated by default**: candidates are created automatically but PR creation is an explicit admin action (approve → enqueue PR job).
- **Minimal diffs**: PRs are intentionally limited to a **single-line change** in `gems/bundled_gems`.
- **Fail closed**: if parsing, version resolution, or diff validation is ambiguous, the candidate is blocked instead of “best guessing”.
- **Auditability**: errors and noteworthy events are recorded in `SystemEvent` and shown in the admin UI.

---

## Core domain objects (database)

These are the “stateful” entities that let the system be resumable and observable:

- **`Advisory`** (`app/models/advisory.rb`)
  - A normalized vulnerability record ingested from a source (`ghsa`, `osv`, `ruby_lang`).
  - Key fields: `gem_name`, `cve`, `advisory_url`, `fingerprint` (unique), `raw` (JSON blob).

- **`BranchTarget`** (`app/models/branch_target.rb`)
  - A Ruby branch we evaluate (e.g. `ruby_3_3`, `master`).
  - Tracks `maintenance_status` (`normal`, `security`, `eol`) and `enabled` (EOL branches are disabled).

- **`CandidateBump`** (`app/models/candidate_bump.rb`)
  - A proposed “bump gem X from A → B on branch Y”.
  - Has a state machine-ish `state`:
    - `ready_for_review` / `blocked_rate_limited` / `blocked_ambiguous`
    - `approved` / `rejected`
    - `submitted` (PR created) / `failed`
  - Stores the proposed 1-line diff (`proposed_diff`) and review notes.

- **`PullRequest`** (`app/models/pull_request.rb`)
  - Local record of a PR opened in `ruby/ruby`.
  - Tracks `status` (`open`/`closed`/`merged`), timestamps, fork branch name, and **comment snapshots** (`comments_snapshot`).

- **`BotConfig`** (`app/models/bot_config.rb`)
  - Singleton config for safety + targeting:
    - `require_human_approval`, `emergency_stop`
    - caps/cooldowns
    - `upstream_repo`, `fork_repo`, optional `fork_git_url`

- **`SystemEvent`** (`app/models/system_event.rb`)
  - Append-only events used for troubleshooting and audit (kinds like `create_pr`, `candidate_build`, `ghsa_ingest`, etc.).

---

## Main workflows (runtime behavior)

### 1) Branch target refresh (supported Ruby branches)
**Goal**: keep an up-to-date list of Ruby branches to evaluate, and disable EOL branches automatically.

- **Job**: `RefreshBranchTargetsJob` (`app/jobs/refresh_branch_targets_job.rb`)
- **Source**: ruby-lang maintenance branches HTML (`RubyLang::MaintenanceBranches`)
- **Behavior**:
  - Parses all branches including `eol`
  - Upserts `BranchTarget` rows and sets `enabled = false` for `eol`
  - Optional cross-check using AI (`Ai::MaintenanceBranchesCrossCheck`) when enabled; mismatch fails closed.

### 2) Vulnerability ingestion (GHSA + OSV → Advisory)
**Goal**: for a given `gem@version`, fetch vulnerability records and store/refresh `Advisory` rows.

- **Services**:
  - `Advisories::GhsaIngestor` (`app/services/advisories/ghsa_ingestor.rb`)
  - `Advisories::OsvIngestor` (`app/services/advisories/osv_ingestor.rb`)
- **Notes**:
  - GHSA parsing can be messy; parse errors are logged as **warning** `SystemEvent`s and do not abort ingestion.
  - Both ingestors try to attach a ruby-lang announcement URL when possible (via RSS helper).

### 3) Evaluation (branch → bundled gems → candidates)
**Goal**: for each enabled branch, read `gems/bundled_gems`, detect vulnerable entries, and build bump candidates.

- **Job**: `EvaluateOsvVulnerabilitiesJob` (`app/jobs/evaluate_osv_vulnerabilities_job.rb`)
  - (Despite the name, evaluation uses an advisory chain that can include GHSA/OSV.)
  - Explicitly excludes EOL branches.
- **Evaluator**: `Evaluation::BundledGemsVulnerabilityEvaluator` (`app/services/evaluation/bundled_gems_vulnerability_evaluator.rb`)
  - Fetches `gems/bundled_gems` from GitHub for each branch.
  - For each entry, asks the advisory chain for relevant advisories.
  - For each advisory, asks the candidate builder to build/update a `CandidateBump`.
- **Candidate builder**: `Evaluation::CandidateBumpBuilder` (`app/services/evaluation/candidate_bump_builder.rb`)
  - Determines a fixed version, resolves a conservative target version, validates the diff is one-line, enforces rate caps.
  - If anything is ambiguous/untrusted, it writes a candidate in `blocked_ambiguous` instead of proceeding.

### 4) Human review and PR creation (candidate → PR)
**Goal**: only create PRs once a human approves the candidate.

- **UI**: Admin panel candidate page triggers actions (`approve`, `reject`, `create_pr`).
  - Controller: `Admin::CandidateBumpsController` (`app/controllers/admin/candidate_bumps_controller.rb`)
- **Job**: `CreatePullRequestJob` (`app/jobs/create_pull_request_job.rb`)
  - Re-checks safety conditions under a DB lock:
    - `BotConfig.emergency_stop?` must be false
    - candidate must still be `approved`
    - candidate must not already have a `PullRequest`
  - Calls the PR creator service and then writes:
    - a `PullRequest` row (status `open`, URL/number/head_branch)
    - candidate transitions to `submitted`
  - On failure:
    - candidate transitions to `failed`
    - a `SystemEvent(kind: "create_pr")` is recorded with exception details

- **PR creator**: `Github::RubyCorePrCreator` (`app/services/github/ruby_core_pr_creator.rb`)
  - Clones upstream branch (`https://github.com/<upstream>.git`) into a temp directory
  - Creates a head branch named like `bump-<gem>-<version>-<branch>`
  - Applies the bump with strict constraints:
    - expected diff must match `candidate.proposed_diff` (or the candidate must not have one)
    - refuses if any file other than `gems/bundled_gems` changes
  - Pushes to the fork using SSH (`git@github.com:<fork>.git` by default)
  - Creates PR via `gh pr create` (supports draft PRs), and detects existing PRs via `gh pr list --head ...`

### 5) PR state + comments synchronization (GitHub → PullRequest)
**Goal**: keep local PR records accurate even if maintainers close/merge, and preserve comments for later review.

- **Job**: `SyncPullRequestsJob` (`app/jobs/sync_pull_requests_job.rb`)
- **Services**:
  - `Github::PullRequestStatusFetcher` (`app/services/github/pull_request_status_fetcher.rb`)
  - `Github::PullRequestCommentsFetcher` (`app/services/github/pull_request_comments_fetcher.rb`)
- **Behavior**:
  - Iterates PR records and updates:
    - `status` (`open`/`closed`/`merged`) + timestamps
    - `comments_snapshot` (issue comments, reviews, inline review comments)
    - `last_synced_at`, `comments_last_synced_at`
  - Errors for individual PRs are logged as `SystemEvent(kind: "sync_pull_requests", status: "warning")` (job continues).

### 6) Fork branch cleanup (hygiene)
**Goal**: delete old `bump-*` branches in the fork after PR is merged/closed.

- **Job**: `CleanupForkBranchesJob` (`app/jobs/cleanup_fork_branches_job.rb`)
- **Service**: `Github::ForkBranchCleaner` (`app/services/github/fork_branch_cleaner.rb`)
- **Behavior**:
  - For PRs with `status in (merged, closed)` and no `branch_deleted_at`, delete the fork branch via GitHub API.
  - Only deletes branches starting with `bump-` (safety guard).
  - Logs per-PR failures as warning `SystemEvent`s.

---

## GitHub integration: how commands are executed

Most GitHub API calls are done through the GitHub CLI so the runtime stays simple:

- Wrapper: `Github::GhCli` (`app/services/github/gh_cli.rb`)
  - Uses `Open3.capture3` to run `gh ...`
  - Raises `Github::GhCli::CommandError` with captured `cmd`, `stdout`, `stderr`, and `exit status`
  - Those details are persisted into `SystemEvent` in failure paths (notably PR creation).

---

## Orchestration: background jobs and schedules

### Solid Queue
The app uses **Solid Queue** for background jobs.

- Local: run `bin/jobs`
- Production: current deployment runs Solid Queue in Puma via `SOLID_QUEUE_IN_PUMA=true` (see `config/deploy.yml`).

### Recurring jobs
Recurring schedules are defined in `config/recurring.yml`. In production the important ones are:

- `RefreshBranchTargetsJob`: daily (2am)
- `EvaluateOsvVulnerabilitiesJob`: daily (3am)
- `SyncPullRequestsJob`: every 30 minutes (captures PR status + comments)
- `CleanupForkBranchesJob`: hourly (minute 25)
- periodic Solid Queue finished job cleanup: hourly (minute 12)

---

## Deployment orchestration (DigitalOcean + Kamal)

### Containers and SSL
Kamal builds and runs a Docker image of the Rails app.

- Config: `config/deploy.yml`
- SSL termination: `kamal-proxy` with Let’s Encrypt (`proxy.ssl: true`, `proxy.host: vulnsentry.com`)

### Environment and secrets
Kamal injects ENV vars into the container:

- Secrets are referenced in `config/deploy.yml` and provided via `.kamal/secrets`:
  - `RAILS_MASTER_KEY`
  - `GH_TOKEN` (for `gh api`, `gh pr create`, etc.)
  - `PGPASSWORD`
  - optional `DEEPSEEK_API_KEY`
- Non-secrets are set in `env.clear` (host, postgres host/port/user, db names, etc.)

### Database layout (multi-DB)
The app uses multiple Postgres databases (primary/cache/queue/cable). In production on DO Managed Postgres, you typically create 4 DBs and set:

- `PRIMARY_DB_NAME`, `CACHE_DB_NAME`, `QUEUE_DB_NAME`, `CABLE_DB_NAME`

This separation avoids Solid Queue schema collisions and keeps concerns clean.

### SSH for pushing fork branches
PR creation pushes branches to your fork over SSH from inside the container.

In `config/deploy.yml` the server mounts a host directory:

- `/opt/automatic_patch/ssh` → `/home/rails/.ssh:ro`

And `GIT_SSH_COMMAND` is set to accept host keys into a temporary known_hosts file.

### Automatic migrations on deploy
Kamal runs migrations before booting the new release via:

- Hook: `.kamal/hooks/pre-app-boot`

This uses `bin/kamal app exec ... bin/rails db:migrate` against the release being deployed.

---

## Where to look when debugging

- **Admin UI**: `app/controllers/admin/*`, `app/views/admin/*`
- **Job pipeline entrypoints**: `app/jobs/*`
- **Candidate creation logic**: `app/services/evaluation/*`
- **GitHub interactions**: `app/services/github/*`
- **External vulnerability ingestion**: `app/services/advisories/*`
- **System-level breadcrumbs**: `SystemEvent` records + `/admin/system_events`

