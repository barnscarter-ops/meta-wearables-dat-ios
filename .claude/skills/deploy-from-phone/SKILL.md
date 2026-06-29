---
name: deploy-from-phone
description: Trigger a TestFlight deploy of this app from the Claude mobile app (or any cloud session) by publishing to the secret ntfy command topic that the MacInCloud build listener watches.
---

# Deploy to TestFlight from the phone

This repo's iOS app is built and shipped to TestFlight by a generic deploy engine
on a MacInCloud Mac. That Mac runs a small **ntfy listener**: when an authorized
message lands on a secret command topic, the Mac clones this repo and runs the full
build → archive → TestFlight upload, then pushes a notification back to the phone.

This skill sends that authorized message. It does **not** build anything itself —
it just rings the Mac's doorbell. Use it from the Claude mobile app (a cloud
session that has cloned this repo) or any session that can reach ntfy.

## Required environment (one-time, per cloud environment)

The command topic and token are secrets, so they are **not** stored in this public
repo. Set them as environment variables on the cloud session / environment
(claude.ai/code → environment settings → secrets):

- `DEPLOY_CMD_TOPIC`  — the secret ntfy command topic name
- `DEPLOY_CMD_TOKEN`  — the shared trigger token
- `NTFY_SERVER` *(optional)* — defaults to `https://ntfy.sh`

Also, cloud sessions default to "Trusted" network mode, which **blocks ntfy.sh**.
Allow `ntfy.sh` in the environment's network access list (or use Unrestricted),
or the POST below will fail with a network error.

## Steps

1. **Pick the app key.** Default is `camerai` (this repo's app). The user may name
   another allowlisted app, and may optionally pass a branch with `--ref BRANCH`
   (defaults to the app's configured branch on the Mac).

2. **Check config is present.** If `DEPLOY_CMD_TOPIC` or `DEPLOY_CMD_TOKEN` is
   unset, stop and tell the user to set them as environment secrets (see above) —
   do not guess or hardcode them.

3. **Publish the trigger** (JSON body; `ref` is optional):

   ```bash
   curl -fsS -o /dev/null \
     -d "{\"app\":\"camerai\",\"token\":\"$DEPLOY_CMD_TOKEN\"}" \
     "${NTFY_SERVER:-https://ntfy.sh}/$DEPLOY_CMD_TOPIC"
   ```

   To deploy a specific branch, add it to the body:
   `{"app":"camerai","token":"$DEPLOY_CMD_TOKEN","ref":"my-branch"}`

4. **Report back.** On a successful POST, tell the user the deploy was triggered on
   the Mac and that they'll get an ntfy push (topic `barns-ios-deploy-k7m2qx8w`) when
   the build uploads — typically a couple of minutes to build + a few more for
   TestFlight processing (~10 min total). The result does **not** come back through
   this session, since the build runs on the Mac.

## Rules

- **Never** print `DEPLOY_CMD_TOKEN` or paste it into the repo. Read it only from the
  environment. If `curl` fails, report the HTTP/network error, not the token.
- The Mac only deploys apps on its server-side allowlist, so an unknown `app` key
  comes back as a failure notification. To add an app, add it to
  `~/deploy-secrets/command-apps.tsv` on the Mac (key, repo URL, default branch).
