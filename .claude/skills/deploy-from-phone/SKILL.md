---
name: deploy-from-phone
description: Trigger a TestFlight deploy of any public GitHub iOS repo from the Claude mobile app (or any cloud session) by publishing to the secret ntfy command topic that the MacInCloud build listener watches.
---

# Deploy to TestFlight from the phone

The MacInCloud Mac runs a **deploy listener**: when an authorized message lands on
a secret command topic, the Mac clones the target repo and runs the full
build → archive → TestFlight upload, then pushes an ntfy notification back.

This skill sends that authorized message. It works exactly like the desktop
`/deploy` skill — point it at any public GitHub iOS repo. Use it from the Claude
mobile app (a cloud session that has cloned a repo) or any session that can reach
ntfy.

## Required environment (one-time, per cloud environment)

The command topic and token are secrets — set them as environment variables on the
cloud session (claude.ai/code → environment settings → secrets):

- `DEPLOY_CMD_TOPIC`  — the secret ntfy command topic name
- `DEPLOY_CMD_TOKEN`  — the shared trigger token
- `NTFY_SERVER` *(optional)* — defaults to `https://ntfy.sh`

Also, cloud sessions default to "Trusted" network mode, which **blocks ntfy.sh**.
Allow `ntfy.sh` in the environment's network access list (or use Unrestricted).

## Steps

1. **Determine the target repo URL.**
   - Default: run `git remote get-url origin` to get the current repo's URL. Strip
     any trailing `.git`.
   - If the user specified a different GitHub URL, use that instead.
   - The Mac can only clone **public** repos (it has no GitHub auth). If the repo
     is private, stop and tell the user.

2. **Determine the branch/ref.**
   - Default: `main` (or whatever the user specifies with `--ref BRANCH`).

3. **Check config is present.** If `DEPLOY_CMD_TOPIC` or `DEPLOY_CMD_TOKEN` is
   unset, stop and tell the user to set them as environment secrets (see above).

4. **Publish the trigger:**

   ```bash
   curl -fsS -o /dev/null \
     -d "{\"url\":\"$REPO_URL\",\"token\":\"$DEPLOY_CMD_TOKEN\",\"ref\":\"$REF\"}" \
     "${NTFY_SERVER:-https://ntfy.sh}/$DEPLOY_CMD_TOPIC"
   ```

5. **Report back.** On a successful POST, tell the user the deploy was triggered on
   the Mac and that they'll get an ntfy push (topic `barns-ios-deploy-k7m2qx8w`)
   when the build uploads — typically a couple of minutes to build + a few more for
   TestFlight processing (~10 min total). The result does **not** come back through
   this session.

## Rules

- **Never** print `DEPLOY_CMD_TOKEN` or paste it anywhere. Read it only from the
  environment. If `curl` fails, report the HTTP/network error, not the token.
- The target repo must be **public** — the Mac has no GitHub credentials.
- The Mac's `deploy.sh` auto-detects the project inside the cloned repo. If it
  reports a missing per-app secret (e.g. `OPENAI_API_KEY`), tell the user which
  file to add on the Mac: `~/deploy-secrets/<bundle-id>.env`.
