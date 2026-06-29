# iOS Deploy Service — Design Spec

**Date:** 2026-06-28
**Status:** Approved (design), pending implementation plan
**Sub-project:** #1 of the "iOS deploy agent" vision (see Context)

---

## Context

This is the **first** of four sub-projects in a larger goal: a hybrid (chat-to-start,
autonomous-after) agent that can take any of the user's GitHub app repos, turn it into
an iPhone app, ship it to TestFlight, and notify the user when it's live. The full
decomposition:

| # | Sub-project | Status |
|---|---|---|
| **1** | **iOS Deploy Service** — point at any Xcode-project GitHub repo → build → TestFlight → notify. **(this spec)** | designing |
| 2 | iOS-ifier — detect a repo's stack; web apps → Capacitor wrap + native plugins (push, reminders, etc.) → Xcode project → hand to #1 | later |
| 3 | Orchestrator integration — wire #1 + #2 into the user's existing OpenRouter multi-model orchestrator; add hybrid flow + callback | later |
| 4 | Create-from-scratch — orchestrator generates a new app, routes through #2/#1 | later |

Each sub-project gets its own spec → plan → build cycle. This document covers **#1 only.**

The existing pipeline (in this repo) deploys one hardcoded app (CameraAccess) to
TestFlight via a self-hosted GitHub Actions runner on a shared MacInCloud Mac. It works,
but it is wired to one app and one repo, and its hardest-won complexity (the
runner/watchdog/`screen` session hack) exists *only* to work around a problem that
architecture B below eliminates.

### Decisions locked during brainstorming

- **Runtime:** hybrid — chat to start, can detach and run autonomously.
- **Source apps:** a mix of stacks; WebView-wrapped web apps are acceptable as long as
  they get native iPhone integration (push, reminders, etc.). *(That conversion is
  sub-project #2; #1 only assumes a buildable Xcode project exists.)*
- **Repo location:** always GitHub.
- **Architecture:** **B — a generic deploy engine on the Mac, driven over SSH.**
- **Notification:** phone push via **ntfy** (self-hostable on the user's Proxmox later).

---

## The key insight (why B)

Every signing failure in the original build traced to the GitHub Actions runner being
**sessionless** (cron-spawned, no macOS security/audit session), so `security
find-identity` / `codesign` saw zero signing identities.

When the deploy is invoked **over SSH** instead, the SSH login *is* a real PAM session
with an audit session — so code signing works with no runner, no watchdog, and no
detached `screen`. **Architecture B deletes the most fragile part of the current
system.** The GitHub Actions runner, `~/runner-watchdog.sh`, the cron entries, and the
localhost-SSH keypair all become redundant and are retired.

---

## Architecture

```
/deploy <github-url>      (PC skill, now)        ┐
orchestrator (#3, later) ─────────── SSH ────────┤──►  MacInCloud
                                                 ┘         │
                                          ~/ios-deploy-engine/   (generic, app-agnostic)
                                                 │
                                deploy.sh <github-url> [--ref] [--dry-run]
                                                 │
       ┌────────────┬───────────────┬───────────┴────────┬──────────────┬───────────┐
   clone/pull   auto-detect      load secrets        produce          build+sign    ntfy
   into         project          from Mac store      (create ASC      (reuse        push on
   workspace    (scheme,         + inject per        app record if    hardened      success/
                bundle IDs,      ios-deploy.json     missing)         keychain      failure
                targets, team)                                        block)
                                                                      → archive
                                                                      → IPA
                                                                      → altool upload
                                                                      → TestFlight
```

Nothing is committed into the target app repos except an **optional** `ios-deploy.json`
(config-as-code, no secrets). The engine, all logic, and all secret *values* live on the
Mac.

---

## Components

All on the Mac unless noted.

### 1. `~/ios-deploy-engine/` — the generic engine
A fastlane setup (Fastfile + Gemfile) parameterized entirely by env/config. The hardened
keychain/signing block from the current Fastfile is **account-level, not app-level**, and
is reused verbatim (it imports the shared distribution cert, sets the live keychain
search list with bare `-s`, and runs `set-key-partition-list`). Everything app-specific
(scheme, bundle IDs, profiles, secret injection, ASC app id) becomes a parameter.

### 2. `deploy.sh <github-url> [--ref main] [--dry-run]` — the entry point
1. Clone or pull the repo into `~/deploy-workspace/<owner>-<repo>` (clean checkout of the
   requested ref; default `main`).
2. Auto-detect the project (component 3).
3. Load global + per-app secrets from the Mac store; merge with `ios-deploy.json` to know
   what to inject and where.
4. Run the generic fastlane `deploy` lane.
5. Fire an ntfy push on success **or** failure (via a `trap` so failures are never
   silent).

`--dry-run` runs steps 1–3 plus validation (config parse, required secrets present, ASC
API key authenticates) and **stops before building/uploading**.

### 3. Project auto-detection
Reads the `.xcodeproj` via `xcodebuild -list -json` (schemes) and
`xcodebuild -showBuildSettings` (bundle IDs, team, targets) to determine: the shared
scheme, the app target's bundle ID, any Watch/extension target + its bundle ID, and the
team. Removes per-app configuration for the common case.

> ponytail: detection assumes one primary app scheme and at most one Watch/extension
> target (the shapes the user actually ships). Ceiling: multi-app-target projects or
> projects without a shared scheme. Upgrade path: declare `scheme`/`targets` explicitly
> in `ios-deploy.json`, which always overrides detection.

### 4. Per-app config — `ios-deploy.json` (optional, committed in the app repo)
Declares only the un-inferable bits. Contains **no secret values** — only the names of
env vars to inject and where to write them. Example:

```json
{
  "appName": "Camera AI",
  "scheme": "CameraAccess",
  "secrets": [
    {
      "env": "OPENAI_API_KEY",
      "dest": "samples/CameraAccess/CameraAccess/Secrets.plist",
      "key": "OPENAI_API_KEY"
    }
  ]
}
```

If absent, the engine assumes "no secret injection, infer everything," preserving B's
"point at any URL and go" promise. In sub-project #3 the orchestrator generates this file
automatically.

### 5. Secrets store — `~/deploy-secrets/` (chmod 600, never committed, never logged)
- **Global (shared by all apps):** distribution cert `.p12` + password; ASC API `.p8`,
  key id, issuer id. *(Already present on the Mac.)*
- **Per-app:** `~/deploy-secrets/<bundle-id>.env` holding that app's secret *values*. The
  repo's `ios-deploy.json` names which vars to inject; this file supplies the values.
  Clean split: **names in git, values on the Mac.**
- **Notify:** `~/deploy-secrets/notify.env` — ntfy server URL + topic (and auth token if
  the self-hosted instance requires one).

### 6. App Store Connect record auto-create
Before signing, run fastlane `produce` with the ASC API key to create the app record and
register the bundle ID **if they don't already exist** (idempotent — skips when present).
This makes "point at a brand-new app and it ships" real. Existing apps (like CameraAccess)
are unaffected.

### 7. Build number strategy (reused)
`latest_testflight_build_number + 1`, applied via `CURRENT_PROJECT_VERSION` so it's
generic across apps and unique regardless of manual uploads.

### 8. Notification module — ntfy
A small helper posts to ntfy via `curl` using `notify.env`. Success message includes app
name + build number + duration; failure message includes the failing step + last error
lines. Default server is `ntfy.sh/<topic>`; switching to the Proxmox-hosted instance is a
one-line change in `notify.env`.

### 9. `/deploy` skill (PC) — the human front door
`/deploy <github-url> [--ref main] [--dry-run]`. Reads `macincloud.env` creds, SSHes into
the Mac (the SSH login provides the signing session), runs `deploy.sh`, streams output
into the session, and reports the result. The ntfy push fires independently, so a
detached/autonomous run still notifies. In #3 the orchestrator invokes the same
`deploy.sh` over SSH — one engine, two front doors.

---

## Data flow (happy path)

1. User: `/deploy https://github.com/<owner>/<repo>`
2. Skill SSHes into Mac → `deploy.sh <url>`
3. Clone ref → `~/deploy-workspace/<owner>-<repo>`
4. Auto-detect scheme / bundle IDs / targets / team
5. Load global secrets + `<bundle-id>.env`; read `ios-deploy.json`; inject declared
   secrets (e.g. write `Secrets.plist`)
6. `produce` (create ASC app if missing) → `sigh` (per-app profile) → set build number
7. `xcodebuild archive` (manual signing, distribution cert) → `gym` export (app-store) →
   `altool` upload
8. ntfy push: "live on TestFlight" → skill reports success in-session

---

## Error handling

- **Fail loud, fail early:** missing required secret, failed ASC auth, or a dead injected
  API key (authenticated before build, as the current Fastfile already does) aborts
  before building.
- **Never silent:** a `trap` in `deploy.sh` fires a failure ntfy push from any exit point,
  including the failing step name and last error lines.
- **Idempotent setup:** keychain is deleted-then-created each run; `produce` skips
  existing apps; workspace is refreshed to a clean checkout per run.
- **`altool` exit-0-on-error** is handled as today: capture output and require "No errors
  uploading", else fail explicitly.

---

## Testing / verification

1. **`--dry-run` (the shipped self-check):** clone + detect + validate config + confirm
   required secrets exist + ASC API key authenticates, without building/uploading. The
   smallest runnable check that fails if the engine's detection/config/secret wiring
   breaks.
2. **End-to-end on the known-good app:** run the generic engine against the CameraAccess
   repo and confirm a build reaches TestFlight. Because CameraAccess already deploys
   today, a green run through the *generic* path proves the parameterization preserved a
   working deploy.

---

## What gets retired

With B in place, these (currently on the Mac, not in git) become redundant and are
decommissioned: the GitHub Actions self-hosted runner, `~/runner-watchdog.sh`, its cron
entries (`@reboot` + every-minute), and the `~/.ssh/localhost_runner` keypair. This also
shrinks the attack surface tied to the exposed MacInCloud password (still flagged for
rotation).

The current repo's `.github/workflows/testflight-deploy.yml`, `fastlane/Fastfile`,
`Gemfile` either move into the generic engine (Fastfile/Gemfile, generalized) or are
removed (the workflow). CameraAccess keeps an `ios-deploy.json` so it deploys through the
generic engine like any other app.

---

## Out of scope (future sub-projects)

- Converting non-Xcode repos to iOS apps (Capacitor wrap, native plugins) — **#2**.
- Multi-model orchestration, hybrid chat→autonomous flow, generating `ios-deploy.json`
  automatically — **#3**.
- Generating brand-new apps from scratch — **#4**.
- Push-to-`main` auto-deploy (option C, an org-level GitHub Actions caller) — additive
  later if wanted; not part of #1.
