# iOS Deploy Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a generic, app-agnostic iOS deploy engine on the MacInCloud Mac that, given any GitHub Xcode-project repo, clones it, auto-detects the project, injects secrets, signs, builds, uploads to TestFlight, and pushes an ntfy notification — driven over SSH from a `/deploy` skill (and later the orchestrator).

**Architecture:** A standalone git repo (`ios-deploy-engine`) cloned to `~/ios-deploy-engine` on the Mac. A bash entry script (`deploy.sh`) handles cloning + notification; a generic fastlane `deploy` lane orchestrates signing/build/upload; four small Ruby modules (`ProjectDetector`, `AppConfig`, `SecretInjector`, `Notifier`) hold the testable logic. Invoked over SSH, so the login session provides the macOS security session for code signing (no GitHub Actions runner needed). App-specific *values* live in a `~/deploy-secrets/` store on the Mac; app-specific *config* (names only) lives in an optional `ios-deploy.json` per repo.

**Tech Stack:** Bash, Ruby (fastlane 2.236.x, `xcodeproj` gem, `minitest` from stdlib), ntfy, `xcodebuild`/`altool`, SSH.

---

## Development model (read first)

- The engine is authored **locally on the PC** with normal tools and version-controlled in its own repo.
- Ruby unit tests and all integration steps **run on the Mac over SSH** (Ruby/fastlane/Xcode live there). The inner loop syncs source to the Mac with `scp` (fast, no commit noise), and commits happen at the end of each task.
- An SSH host alias `macdeploy` is configured in Task 0 so every remote command is short. Credentials come from the existing `C:\Users\carte\.claude\macincloud.env`.
- "Run on Mac" steps are literally `ssh macdeploy '<cmd>'` from the PC's Bash tool.

**Secrets discipline (non-negotiable, per global rules):** no secret *values* ever enter the engine repo or git. Only secret *names/paths* appear in `ios-deploy.json`. All values live in `~/deploy-secrets/` on the Mac, `chmod 600`.

---

## File structure

Engine repo (`ios-deploy-engine`, new):

```
ios-deploy-engine/
  Gemfile                      # fastlane, xcodeproj
  deploy.sh                    # entry: parse args, clone, run fastlane, notify (Task 6)
  sync.sh                      # dev helper: scp source -> Mac (Task 0)
  fastlane/
    Fastfile                   # generic deploy lane (Task 5)
  lib/
    notifier.rb                # ntfy message build + send (Task 1)
    project_detector.rb        # parse .xcodeproj -> scheme/bundle ids/targets/team (Task 2)
    app_config.rb              # merge ios-deploy.json over detected defaults (Task 3)
    secret_injector.rb         # read ~/deploy-secrets/<bundle>.env, write Secrets.plist (Task 4)
  bin/
    notify.rb                  # CLI around Notifier, callable from bash (Task 1)
  test/
    engine_test.rb             # minitest for the 4 lib modules (Tasks 1-4)
  README.md
```

On the Mac, NOT in git (Task 7):

```
~/deploy-secrets/
  cert.p12                     # distribution cert (Apple Distribution: Carter Barns)
  AuthKey_<KEYID>.p8           # App Store Connect API key
  global.env                   # ASC ids, cert password, paths, team
  notify.env                   # NTFY_SERVER + NTFY_TOPIC
  com.carter.camerai.env       # per-app secret values (OPENAI_API_KEY)
~/deploy-workspace/<owner>-<repo>/   # cloned target repos (created at runtime)
~/ios-deploy-engine/                 # the engine checkout
```

---

## Task 0: Bootstrap engine repo + Mac access

**Files:**
- Create (local): `ios-deploy-engine/Gemfile`
- Create (local): `ios-deploy-engine/sync.sh`
- Create (local): `ios-deploy-engine/.gitignore`
- Create (local): `ios-deploy-engine/README.md`
- Modify: `~/.ssh/config` (PC) — add `macdeploy` host

- [ ] **Step 1: Read MacInCloud creds and add an SSH host alias**

Read host/user/key from `C:\Users\carte\.claude\macincloud.env`, then append to `C:\Users\carte\.ssh\config` (create if missing):

```
Host macdeploy
    HostName TX185.macincloud.com
    User user943340
    IdentityFile C:/Users/carte/.ssh/macincloud_key
    StrictHostKeyChecking accept-new
```

Run: `ssh macdeploy 'echo connected && sw_vers -productVersion && ruby -v'`
Expected: prints `connected`, a macOS version, and a Ruby version.

- [ ] **Step 2: Create the engine repo locally**

Create the directory `C:\Workspace\Active\ios-deploy-engine`, then:

`ios-deploy-engine/Gemfile`:
```ruby
source "https://rubygems.org"

gem "fastlane", "~> 2.236"
gem "xcodeproj"
```

`ios-deploy-engine/.gitignore`:
```
build/
*.log
.DS_Store
Gemfile.lock
vendor/
```

`ios-deploy-engine/README.md`:
```markdown
# ios-deploy-engine

Generic iOS TestFlight deploy engine. Point it at any GitHub Xcode-project repo:

    ./deploy.sh https://github.com/<owner>/<repo> [--ref main] [--dry-run]

Runs on the MacInCloud Mac, invoked over SSH. App secrets live in
`~/deploy-secrets/` (never in this repo). See
`docs/superpowers/specs/2026-06-28-ios-deploy-service-design.md` in the
meta-wearables-dat-ios repo for the full design.
```

`ios-deploy-engine/sync.sh` (dev helper — push working tree to the Mac without a commit):
```bash
#!/usr/bin/env bash
set -euo pipefail
ssh macdeploy 'mkdir -p ~/ios-deploy-engine'
scp -q -r Gemfile deploy.sh sync.sh fastlane lib bin test macdeploy:~/ios-deploy-engine/ 2>/dev/null || true
# bin/test/deploy.sh may not exist yet on first runs; copy whatever is present
for p in Gemfile deploy.sh fastlane lib bin test; do
  [ -e "$p" ] && scp -q -r "$p" macdeploy:~/ios-deploy-engine/
done
echo "synced"
```

- [ ] **Step 3: Initialize git, create the GitHub repo, push**

Run (local, in `ios-deploy-engine`):
```bash
git init -b main
git add .
git commit -m "chore: scaffold ios-deploy-engine"
gh repo create ios-deploy-engine --private --source=. --remote=origin --push
```
Expected: repo created and pushed; `gh repo view` shows it.

- [ ] **Step 4: Clone on the Mac and install gems**

Run: `ssh macdeploy 'git clone https://github.com/<owner>/ios-deploy-engine.git ~/ios-deploy-engine && cd ~/ios-deploy-engine && bundle install'`
Expected: `bundle install` completes; `ssh macdeploy 'cd ~/ios-deploy-engine && bundle exec ruby -e "require \"xcodeproj\"; puts :ok"'` prints `ok`.

- [ ] **Step 5: Commit** (already committed in Step 3; nothing further)

---

## Task 1: Notifier + notify CLI

Build the ntfy path first so the phone push can be verified immediately and reused everywhere.

**Files:**
- Create: `ios-deploy-engine/lib/notifier.rb`
- Create: `ios-deploy-engine/bin/notify.rb`
- Test: `ios-deploy-engine/test/engine_test.rb`

- [ ] **Step 1: Write the failing test**

`test/engine_test.rb`:
```ruby
require "minitest/autorun"
require_relative "../lib/notifier"

class NotifierTest < Minitest::Test
  def setup
    @n = Notifier.new(server: "https://ntfy.sh", topic: "test-topic")
  end

  def test_success_message_with_build
    msg = @n.message(ok: true, app: "Camera AI", build: "43")
    assert_includes msg[:title], "Camera AI"
    assert_includes msg[:body], "43"
    assert_includes msg[:body].downcase, "testflight"
  end

  def test_success_message_dry_run
    msg = @n.message(ok: true, app: "Camera AI", text: "dry-run OK")
    assert_includes msg[:body], "dry-run OK"
  end

  def test_failure_message_includes_error_tail
    msg = @n.message(ok: false, app: "Camera AI", error: "boom: no profile")
    assert_includes msg[:title].downcase, "fail"
    assert_includes msg[:body], "boom: no profile"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: FAIL — `cannot load such file -- ../lib/notifier`.

- [ ] **Step 3: Implement Notifier**

`lib/notifier.rb`:
```ruby
require "shellwords"

# Builds and sends ntfy notifications. Message building is pure (testable);
# send shells out to curl so it works identically from Ruby and from bash.
class Notifier
  def initialize(server:, topic:)
    @server = server.chomp("/")
    @topic = topic
  end

  # Returns { title:, body:, priority: } — no I/O, so it's unit-testable.
  def message(ok:, app:, build: nil, text: nil, error: nil)
    if ok
      body = text || "Build #{build} is live on TestFlight."
      { title: "#{app} ✅", body: body, priority: "default" }
    else
      body = ["#{app} deploy FAILED.", error].compact.join("\n\n")
      { title: "#{app} ❌ FAILED", body: body, priority: "high" }
    end
  end

  def send(**kwargs)
    m = message(**kwargs)
    url = "#{@server}/#{@topic}"
    cmd = [
      "curl", "-s", "-o", "/dev/null",
      "-H", "Title: #{m[:title]}",
      "-H", "Priority: #{m[:priority]}",
      "-d", m[:body], url
    ]
    system(*cmd)
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: PASS (3 runs, 0 failures).

- [ ] **Step 5: Implement the notify CLI**

`bin/notify.rb`:
```ruby
#!/usr/bin/env ruby
require "optparse"
require_relative "../lib/notifier"

opts = { ok: true }
OptionParser.new do |o|
  o.on("--ok") { opts[:ok] = true }
  o.on("--fail") { opts[:ok] = false }
  o.on("--app APP") { |v| opts[:app] = v }
  o.on("--build B") { |v| opts[:build] = v }
  o.on("--message M") { |v| opts[:text] = v }
  o.on("--error E") { |v| opts[:error] = v }
end.parse!

server = ENV.fetch("NTFY_SERVER")
topic  = ENV.fetch("NTFY_TOPIC")
Notifier.new(server: server, topic: topic).send(
  ok: opts[:ok], app: opts[:app] || "app",
  build: opts[:build], text: opts[:text], error: opts[:error]
)
```

- [ ] **Step 6: Verify the real phone push**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && NTFY_SERVER=https://ntfy.sh NTFY_TOPIC=barns-ios-deploy-k7m2qx8w ruby bin/notify.rb --ok --app "Engine test" --build 1'`
Expected: a notification "Engine test ✅ / Build 1 is live on TestFlight." appears on the user's phone.

- [ ] **Step 7: Commit**

```bash
git add lib/notifier.rb bin/notify.rb test/engine_test.rb
git commit -m "feat: ntfy notifier + notify CLI"
git push
```

---

## Task 2: ProjectDetector

**Files:**
- Create: `ios-deploy-engine/lib/project_detector.rb`
- Test: `ios-deploy-engine/test/engine_test.rb` (append)

- [ ] **Step 1: Write the failing test** (append to `test/engine_test.rb`)

```ruby
require "xcodeproj"
require "tmpdir"
require_relative "../lib/project_detector"

class ProjectDetectorTest < Minitest::Test
  # Build a throwaway project with an iOS app target + a watchOS app target,
  # so detection logic can be exercised without a real Xcode workspace.
  def make_project(dir)
    proj = Xcodeproj::Project.new(File.join(dir, "Sample.xcodeproj"))
    ios = proj.new_target(:application, "Sample", :ios)
    ios.build_configurations.each do |c|
      c.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.acme.sample"
      c.build_settings["DEVELOPMENT_TEAM"] = "ABCDE12345"
    end
    watch = proj.new_target(:application, "Sample Watch App", :watchos)
    watch.build_configurations.each do |c|
      c.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.acme.sample.watchkitapp"
      c.build_settings["SDKROOT"] = "watchos"
    end
    scheme = Xcodeproj::XCScheme.new
    scheme.add_build_target(ios)
    proj.save
    scheme.save_as(proj.path, "Sample", true)
    proj.path
  end

  def test_detects_app_bundle_team_and_extra_targets
    Dir.mktmpdir do |dir|
      path = make_project(dir)
      d = ProjectDetector.detect(path)
      assert_equal "com.acme.sample", d[:app_bundle_id]
      assert_equal "ABCDE12345", d[:team_id]
      assert_equal "Sample", d[:scheme]
      watch = d[:extra_targets].find { |t| t[:bundle_id] == "com.acme.sample.watchkitapp" }
      refute_nil watch
    end
  end

  def test_find_project_locates_nested_xcodeproj
    Dir.mktmpdir do |dir|
      nested = File.join(dir, "a", "b")
      FileUtils.mkdir_p(nested)
      make_project(nested)
      found = ProjectDetector.find_project(dir)
      assert found.end_with?("Sample.xcodeproj")
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: FAIL — cannot load `project_detector`.

- [ ] **Step 3: Implement ProjectDetector**

`lib/project_detector.rb`:
```ruby
require "xcodeproj"

# Reads an .xcodeproj and returns the facts the deploy lane needs.
# Ceiling (ponytail): assumes one primary iOS app scheme and that bundle IDs are
# literal (not $(VAR)). Projects without a shared scheme, or with computed bundle
# IDs, must declare `scheme`/`bundleId` in ios-deploy.json, which overrides this.
module ProjectDetector
  PROVISIONABLE = /application|app-extension|watchapp|watchkit/.freeze

  module_function

  # Find the first .xcodeproj under repo_dir (shallowest wins).
  def find_project(repo_dir)
    Dir.glob(File.join(repo_dir, "**", "*.xcodeproj"))
       .reject { |p| p.include?("/Pods/") }
       .min_by { |p| p.count("/") }
  end

  def detect(project_path)
    proj = Xcodeproj::Project.open(project_path)
    apps = proj.targets.select { |t| t.product_type&.include?("application") }
    ios_app = apps.find { |t| sdkroot(t) != "watchos" } || apps.first
    raise "no application target found in #{project_path}" unless ios_app

    extras = proj.targets.reject { |t| t == ios_app }.filter_map do |t|
      bid = bundle_id(t)
      next nil unless bid && t.product_type&.match?(PROVISIONABLE)
      { name: t.name, bundle_id: bid }
    end

    {
      project_path: project_path,
      scheme: pick_scheme(project_path, ios_app.name),
      app_bundle_id: bundle_id(ios_app),
      team_id: setting(ios_app, "DEVELOPMENT_TEAM"),
      extra_targets: extras
    }
  end

  def bundle_id(target)
    setting(target, "PRODUCT_BUNDLE_IDENTIFIER")
  end

  def sdkroot(target)
    setting(target, "SDKROOT")
  end

  # Read a build setting from the Release config, falling back to Debug.
  def setting(target, key)
    cfg = target.build_configurations.find { |c| c.name == "Release" } ||
          target.build_configurations.first
    cfg&.build_settings&.[](key)
  end

  def pick_scheme(project_path, app_name)
    schemes = Xcodeproj::Project.schemes(project_path)
    schemes.include?(app_name) ? app_name : schemes.first
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: PASS (all tests so far, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add lib/project_detector.rb test/engine_test.rb
git commit -m "feat: xcodeproj-based project detection"
git push
```

---

## Task 3: AppConfig

**Files:**
- Create: `ios-deploy-engine/lib/app_config.rb`
- Test: `ios-deploy-engine/test/engine_test.rb` (append)

- [ ] **Step 1: Write the failing test** (append)

```ruby
require "json"
require_relative "../lib/app_config"

class AppConfigTest < Minitest::Test
  DETECTED = {
    project_path: "/x/Sample.xcodeproj",
    scheme: "Sample",
    app_bundle_id: "com.acme.sample",
    team_id: "ABCDE12345",
    extra_targets: [{ name: "Sample Watch App", bundle_id: "com.acme.sample.watchkitapp" }]
  }.freeze

  def test_defaults_when_no_json
    Dir.mktmpdir do |dir|
      c = AppConfig.load(dir, DETECTED)
      assert_equal "Sample", c.scheme
      assert_equal "com.acme.sample", c.app_bundle_id
      assert_equal "com.acme.sample", c.app_name   # falls back to bundle id
      assert_empty c.secrets
    end
  end

  def test_json_overrides_and_secrets
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ios-deploy.json"), JSON.dump(
        "appName" => "Camera AI",
        "scheme" => "CustomScheme",
        "secrets" => [{ "env" => "OPENAI_API_KEY", "dest" => "App/Secrets.plist", "key" => "OPENAI_API_KEY" }]
      ))
      c = AppConfig.load(dir, DETECTED)
      assert_equal "Camera AI", c.app_name
      assert_equal "CustomScheme", c.scheme
      assert_equal 1, c.secrets.size
      assert_equal "OPENAI_API_KEY", c.secrets.first[:env]
      assert_equal "App/Secrets.plist", c.secrets.first[:dest]
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: FAIL — cannot load `app_config`.

- [ ] **Step 3: Implement AppConfig**

`lib/app_config.rb`:
```ruby
require "json"

# Merges an optional repo-level ios-deploy.json over auto-detected defaults.
# The JSON contains only names/paths — never secret values.
class AppConfig
  attr_reader :project_path, :scheme, :app_bundle_id, :app_name, :team_id,
              :extra_targets, :secrets

  def self.load(repo_dir, detected)
    path = File.join(repo_dir, "ios-deploy.json")
    json = File.exist?(path) ? JSON.parse(File.read(path)) : {}
    new(repo_dir, detected, json)
  end

  def initialize(repo_dir, detected, json)
    @project_path  = abs(repo_dir, json["projectPath"]) || detected[:project_path]
    @scheme        = json["scheme"]   || detected[:scheme]
    @app_bundle_id = json["bundleId"] || detected[:app_bundle_id]
    @team_id       = json["teamId"]   || detected[:team_id]
    @app_name      = json["appName"]  || @app_bundle_id
    @extra_targets = detected[:extra_targets] || []
    @secrets = (json["secrets"] || []).map do |s|
      { env: s["env"], dest: s["dest"], key: s["key"] || s["env"] }
    end
  end

  private

  def abs(repo_dir, rel)
    rel && File.expand_path(rel, repo_dir)
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app_config.rb test/engine_test.rb
git commit -m "feat: app config merge (ios-deploy.json over detected)"
git push
```

---

## Task 4: SecretInjector

**Files:**
- Create: `ios-deploy-engine/lib/secret_injector.rb`
- Test: `ios-deploy-engine/test/engine_test.rb` (append)

- [ ] **Step 1: Write the failing test** (append)

```ruby
require_relative "../lib/secret_injector"

class SecretInjectorTest < Minitest::Test
  Cfg = Struct.new(:app_bundle_id, :secrets)

  def test_writes_plist_from_secrets_env
    Dir.mktmpdir do |repo|
      Dir.mktmpdir do |secrets_dir|
        File.write(File.join(secrets_dir, "com.acme.sample.env"), "OPENAI_API_KEY=sk-test123\n")
        cfg = Cfg.new("com.acme.sample",
                      [{ env: "OPENAI_API_KEY", dest: "App/Secrets.plist", key: "OPENAI_API_KEY" }])
        SecretInjector.inject(cfg, repo, secrets_dir)
        plist = File.read(File.join(repo, "App", "Secrets.plist"))
        assert_includes plist, "<key>OPENAI_API_KEY</key>"
        assert_includes plist, "<string>sk-test123</string>"
      end
    end
  end

  def test_missing_value_raises
    Dir.mktmpdir do |repo|
      Dir.mktmpdir do |secrets_dir|
        File.write(File.join(secrets_dir, "com.acme.sample.env"), "OTHER=x\n")
        cfg = Cfg.new("com.acme.sample",
                      [{ env: "OPENAI_API_KEY", dest: "App/Secrets.plist", key: "OPENAI_API_KEY" }])
        err = assert_raises(RuntimeError) { SecretInjector.inject(cfg, repo, secrets_dir) }
        assert_includes err.message, "OPENAI_API_KEY"
      end
    end
  end

  def test_validate_does_not_write
    Dir.mktmpdir do |repo|
      Dir.mktmpdir do |secrets_dir|
        File.write(File.join(secrets_dir, "com.acme.sample.env"), "OPENAI_API_KEY=sk-test123\n")
        cfg = Cfg.new("com.acme.sample",
                      [{ env: "OPENAI_API_KEY", dest: "App/Secrets.plist", key: "OPENAI_API_KEY" }])
        SecretInjector.validate(cfg, secrets_dir)   # must not raise
        refute File.exist?(File.join(repo, "App", "Secrets.plist"))
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: FAIL — cannot load `secret_injector`.

- [ ] **Step 3: Implement SecretInjector**

`lib/secret_injector.rb`:
```ruby
require "fileutils"
require "cgi"

# Materializes app secrets from ~/deploy-secrets/<bundle-id>.env into the repo
# (currently as .plist files) per the config's `secrets` declarations.
module SecretInjector
  module_function

  def inject(config, repo_dir, secrets_dir)
    return if config.secrets.nil? || config.secrets.empty?
    env = load_env(env_file(config, secrets_dir))
    config.secrets.each do |s|
      value = env[s[:env]] or
        raise "secret #{s[:env]} not found in #{env_file(config, secrets_dir)}"
      write_plist(File.join(repo_dir, s[:dest]), s[:key] => value)
    end
  end

  # Dry-run check: every declared secret has a value, without writing anything.
  def validate(config, secrets_dir)
    return if config.secrets.nil? || config.secrets.empty?
    env = load_env(env_file(config, secrets_dir))
    missing = config.secrets.map { |s| s[:env] }.reject { |k| env.key?(k) }
    raise "missing secrets #{missing.join(', ')} in #{env_file(config, secrets_dir)}" unless missing.empty?
  end

  def env_file(config, secrets_dir)
    File.join(secrets_dir, "#{config.app_bundle_id}.env")
  end

  def load_env(path)
    raise "secrets file not found: #{path}" unless File.exist?(path)
    File.readlines(path).each_with_object({}) do |line, h|
      line = line.strip
      next if line.empty? || line.start_with?("#")
      k, v = line.split("=", 2)
      h[k] = v if k && v
    end
  end

  def write_plist(dest, pairs)
    FileUtils.mkdir_p(File.dirname(dest))
    entries = pairs.map do |k, v|
      "    <key>#{CGI.escapeHTML(k)}</key>\n    <string>#{CGI.escapeHTML(v)}</string>"
    end.join("\n")
    File.write(dest, <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      #{entries}
      </dict>
      </plist>
    PLIST
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && ruby -Ilib test/engine_test.rb'`
Expected: PASS (all four modules green).

- [ ] **Step 5: Commit**

```bash
git add lib/secret_injector.rb test/engine_test.rb
git commit -m "feat: secret injection from Mac secrets store"
git push
```

---

## Task 5: Generic Fastfile deploy lane

This is the orchestration. It has two paths: `--dry-run` (validate only) and full deploy. The keychain/signing block is reused verbatim from the working CameraAccess Fastfile (it is account-level, not app-level).

**Files:**
- Create: `ios-deploy-engine/fastlane/Fastfile`

- [ ] **Step 1: Implement the Fastfile**

`ios-deploy-engine/fastlane/Fastfile`:
```ruby
require "base64"
require "shellwords"
require "etc"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "project_detector"
require "app_config"
require "secret_injector"

default_platform(:ios)

platform :ios do
  desc "Generic: detect, sign, build, upload any iOS repo to TestFlight"
  lane :deploy do
    repo_dir    = ENV.fetch("REPO_DIR")
    secrets_dir = ENV.fetch("SECRETS_DIR")
    dry_run     = ENV["DRY_RUN"] == "1"
    result_path = ENV["RESULT"]

    # --- detect + config ---
    project_path = ProjectDetector.find_project(repo_dir) or
      UI.user_error!("no .xcodeproj found under #{repo_dir}")
    detected = ProjectDetector.detect(project_path)
    config = AppConfig.load(repo_dir, detected)
    UI.message("App: #{config.app_name} (#{config.app_bundle_id}) scheme=#{config.scheme} team=#{config.team_id}")
    config.extra_targets.each { |t| UI.message("Extra target: #{t[:name]} (#{t[:bundle_id]})") }

    api_key = app_store_connect_api_key(
      key_id: ENV.fetch("ASC_KEY_ID"),
      issuer_id: ENV.fetch("ASC_ISSUER_ID"),
      key_filepath: ENV.fetch("ASC_KEY_P8_PATH")
    )

    # --- dry-run: validate everything, build nothing ---
    if dry_run
      SecretInjector.validate(config, secrets_dir)
      latest_testflight_build_number(
        api_key: api_key, app_identifier: config.app_bundle_id,
        platform: "ios", initial_build_number: 0
      )
      UI.success("DRY RUN OK — project detected, secrets present, ASC auth works.")
      File.write(result_path, "APP_NAME=#{config.app_name}\n") if result_path
      next
    end

    # --- keychain / signing (account-level; reused from CameraAccess) ---
    keychain_name = "ci_keychain"
    keychain_pass = "ci_temp_pass"
    keychain_path = File.join(Etc.getpwuid.dir, "Library", "Keychains", keychain_name)
    kc = keychain_path.shellescape
    sh("security delete-keychain #{kc} 2>/dev/null || true")
    sh("security create-keychain -p #{keychain_pass} #{kc}")
    sh("security set-keychain-settings -t 21600 #{kc}")
    sh("security unlock-keychain -p #{keychain_pass} #{kc}")
    existing = sh("security list-keychains", log: false)
               .split("\n").map { |l| l.strip.delete('"') }
               .reject(&:empty?).reject { |k| k.include?("ci_keychain") }
    sh("security list-keychains -s #{kc} #{existing.shelljoin}")
    import_certificate(
      certificate_path: ENV.fetch("DIST_CERT_P12_PATH"),
      certificate_password: ENV.fetch("DIST_CERT_P12_PASSWORD"),
      keychain_name: keychain_name,
      keychain_path: keychain_path,
      keychain_password: keychain_pass
    )
    sh("security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k #{keychain_pass} #{kc}")
    sh("security find-identity -v -p codesigning || true")

    # --- ensure ASC app records exist (idempotent) ---
    team_id = config.team_id || ENV["DEV_TEAM"]
    all_ids = [config.app_bundle_id] + config.extra_targets.map { |t| t[:bundle_id] }
    all_ids.each do |bid|
      begin
        produce(
          app_identifier: bid,
          app_name: bid == config.app_bundle_id ? config.app_name : "#{config.app_name} #{bid.split('.').last}",
          api_key: api_key,
          skip_itc: false, skip_devcenter: false
        )
      rescue => e
        UI.message("produce(#{bid}): #{e.message} (continuing — likely already exists)")
      end
    end

    # --- provisioning profiles per target ---
    # sigh exposes both the downloaded path and the ASC profile NAME via
    # lane_context, so we capture the name directly instead of parsing the
    # signed .mobileprovision. SIGH_NAME reflects the most recent sigh call,
    # so read it inside the loop right after each call.
    profile_dir = File.expand_path("~/Library/MobileDevice/Provisioning Profiles")
    FileUtils.mkdir_p(profile_dir)
    profiles = {}
    export_profiles = {}   # bundle_id => ASC profile name (for gym export_options)
    all_ids.each do |bid|
      sigh(api_key: api_key, app_identifier: bid, output_path: profile_dir)
      profiles[bid] = Actions.lane_context[SharedValues::SIGH_PROFILE_PATH]
      export_profiles[bid] = Actions.lane_context[SharedValues::SIGH_NAME]
    end

    if config.extra_targets.empty?
      update_project_provisioning(
        xcodeproj: config.project_path, profile: profiles[config.app_bundle_id],
        build_configuration: "Release"
      )
    else
      # Apply the app profile to all targets first, then override each extra
      # target with its own profile (later calls win).
      update_project_provisioning(
        xcodeproj: config.project_path, profile: profiles[config.app_bundle_id],
        target_filter: ".*", build_configuration: "Release"
      )
      config.extra_targets.each do |t|
        update_project_provisioning(
          xcodeproj: config.project_path, profile: profiles[t[:bundle_id]],
          target_filter: Regexp.escape(t[:name]), build_configuration: "Release"
        )
      end
    end

    # --- build number ---
    build_number = latest_testflight_build_number(
      api_key: api_key, app_identifier: config.app_bundle_id,
      platform: "ios", initial_build_number: 0
    ) + 1

    # --- inject app secrets (e.g. OPENAI_API_KEY -> Secrets.plist) ---
    SecretInjector.inject(config, repo_dir, secrets_dir)

    # --- archive + export + upload ---
    archive_path = "/tmp/#{config.scheme}.xcarchive"
    sh(
      "xcodebuild -scheme #{config.scheme.shellescape} -project '#{config.project_path}' " \
      "-configuration Release -destination 'generic/platform=iOS' " \
      "-archivePath '#{archive_path}' CODE_SIGN_STYLE=Manual " \
      "CURRENT_PROJECT_VERSION=#{build_number} DEVELOPMENT_TEAM=#{team_id} " \
      "\"CODE_SIGN_IDENTITY=Apple Distribution\" archive"
    )

    gym(
      project: config.project_path, scheme: config.scheme,
      skip_build_archive: true, archive_path: archive_path,
      export_method: "app-store", output_directory: "#{repo_dir}/build",
      output_name: "#{config.scheme}.ipa",
      export_options: {
        method: "app-store", signingStyle: "manual",
        provisioningProfiles: export_profiles
      }
    )

    ipa_path = "#{repo_dir}/build/#{config.scheme}.ipa"
    upload_out = sh(
      "xcrun altool --upload-app -f '#{ipa_path}' --platform ios " \
      "--apiKey #{ENV.fetch('ASC_KEY_ID')} --apiIssuer #{ENV.fetch('ASC_ISSUER_ID')} 2>&1",
      log: true
    )
    UI.user_error!("altool upload failed:\n#{upload_out}") unless upload_out.include?("No errors uploading")

    File.write(result_path, "APP_NAME=#{config.app_name}\nBUILD_NUMBER=#{build_number}\n") if result_path
    UI.success("#{config.app_name} build #{build_number} uploaded to TestFlight.")
  end
end
```

> Note: `ASC_KEY_CONTENT` is no longer passed inline; `app_store_connect_api_key` reads the `.p8` from `ASC_KEY_P8_PATH`. The OpenAI key auth-check (HTTP 200) now lives in the app's own secret handling — see Task 8's `ios-deploy.json`; if you want a hard pre-build check, add a `curl` against `https://api.openai.com/v1/models` here gated on a `secrets` entry named `OPENAI_API_KEY`.

- [ ] **Step 2: Syntax check on the Mac**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && bundle exec ruby -c fastlane/Fastfile'`
Expected: `Syntax OK`.

- [ ] **Step 3: Commit**

```bash
git add fastlane/Fastfile
git commit -m "feat: generic fastlane deploy lane (dry-run + full)"
git push
```

---

## Task 6: deploy.sh entry script

**Files:**
- Create: `ios-deploy-engine/deploy.sh`

- [ ] **Step 1: Implement deploy.sh**

`ios-deploy-engine/deploy.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_DIR="$HOME/deploy-secrets"

URL=""; REF="main"; DRY_RUN="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)     REF="$2"; shift 2;;
    --dry-run) DRY_RUN="1"; shift;;
    -*)        echo "unknown flag: $1" >&2; exit 2;;
    *)         URL="$1"; shift;;
  esac
done
[[ -n "$URL" ]] || { echo "usage: deploy.sh <github-url> [--ref REF] [--dry-run]" >&2; exit 2; }

# Load notify + global secrets into the environment.
set -a
# shellcheck disable=SC1090
source "$SECRETS_DIR/notify.env"
source "$SECRETS_DIR/global.env"
set +a

slug="$(echo "$URL" | sed -E 's#(\.git)?$##; s#.*/([^/]+/[^/]+)$#\1#' | tr '/' '-')"
WORKSPACE="$HOME/deploy-workspace/$slug"
LOG="/tmp/deploy-$slug.log"
RESULT="/tmp/deploy-$slug.result.env"
rm -f "$RESULT" "$LOG"

notify_fail() {
  local err; err="$(tail -n 20 "$LOG" 2>/dev/null || true)"
  ruby "$ENGINE_DIR/bin/notify.rb" --fail --app "$slug" --error "$err" || true
}

# Trap covers the clone/setup phase; the fastlane run is checked explicitly below.
trap 'notify_fail' ERR

mkdir -p "$HOME/deploy-workspace"
if [[ -d "$WORKSPACE/.git" ]]; then
  git -C "$WORKSPACE" fetch --depth 1 origin "$REF"
  git -C "$WORKSPACE" reset --hard FETCH_HEAD
  git -C "$WORKSPACE" clean -fdx
else
  rm -rf "$WORKSPACE"
  git clone --depth 1 --branch "$REF" "$URL" "$WORKSPACE"
fi

trap - ERR   # from here we manage failure notification ourselves

export REPO_DIR="$WORKSPACE" DRY_RUN RESULT SECRETS_DIR
set +e
( cd "$ENGINE_DIR" && bundle exec fastlane deploy ) 2>&1 | tee "$LOG"
status="${PIPESTATUS[0]}"
set -e

if [[ "$status" -ne 0 ]]; then
  notify_fail
  exit "$status"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  # shellcheck disable=SC1090
  [[ -f "$RESULT" ]] && { set -a; source "$RESULT"; set +a; }
  ruby "$ENGINE_DIR/bin/notify.rb" --ok --app "${APP_NAME:-$slug}" --message "dry-run OK"
else
  set -a; source "$RESULT"; set +a
  ruby "$ENGINE_DIR/bin/notify.rb" --ok --app "${APP_NAME:-$slug}" --build "${BUILD_NUMBER:-?}"
fi
```

- [ ] **Step 2: Make it executable and shellcheck it**

Run: `bash sync.sh && ssh macdeploy 'cd ~/ios-deploy-engine && chmod +x deploy.sh bin/notify.rb && bash -n deploy.sh && echo "syntax ok"'`
Expected: prints `syntax ok`.

- [ ] **Step 3: Commit**

```bash
git update-index --chmod=+x deploy.sh bin/notify.rb 2>/dev/null || true
git add deploy.sh
git commit -m "feat: deploy.sh entry script with clone + notify"
git push
```

---

## Task 7: Secrets store on the Mac

No code; this provisions `~/deploy-secrets/`. Values come from the user's existing cert/key (the same ones the current pipeline uses).

**Files (on Mac, not in git):**
- Create: `~/deploy-secrets/global.env`, `~/deploy-secrets/notify.env`, `~/deploy-secrets/cert.p12`, `~/deploy-secrets/AuthKey_<KEYID>.p8`, `~/deploy-secrets/com.carter.camerai.env`

- [ ] **Step 1: Create the store and lock it down**

Run: `ssh macdeploy 'mkdir -p ~/deploy-secrets && chmod 700 ~/deploy-secrets'`

- [ ] **Step 2: Place the distribution cert and ASC key**

The `.p12` and `.p8` already exist (used by the current GitHub Actions secrets). Copy them into the store. From the PC, if you have the local `.p12`/`.p8`:
```bash
scp /path/to/dist_cert.p12 macdeploy:~/deploy-secrets/cert.p12
scp /path/to/AuthKey_<KEYID>.p8 macdeploy:~/deploy-secrets/AuthKey_<KEYID>.p8
```
Then: `ssh macdeploy 'chmod 600 ~/deploy-secrets/cert.p12 ~/deploy-secrets/AuthKey_*.p8'`

- [ ] **Step 3: Write global.env**

Run (substitute real values; `<KEYID>` is the ASC key id):
```bash
ssh macdeploy 'cat > ~/deploy-secrets/global.env <<EOF
ASC_KEY_ID=<KEYID>
ASC_ISSUER_ID=<ISSUER>
ASC_KEY_P8_PATH=$HOME/deploy-secrets/AuthKey_<KEYID>.p8
DIST_CERT_P12_PATH=$HOME/deploy-secrets/cert.p12
DIST_CERT_P12_PASSWORD=<P12_PASSWORD>
DEV_TEAM=R9DLFUKL26
EOF
chmod 600 ~/deploy-secrets/global.env'
```

- [ ] **Step 4: Write notify.env**

```bash
ssh macdeploy 'cat > ~/deploy-secrets/notify.env <<EOF
NTFY_SERVER=https://ntfy.sh
NTFY_TOPIC=barns-ios-deploy-k7m2qx8w
EOF
chmod 600 ~/deploy-secrets/notify.env'
```

- [ ] **Step 5: Write the per-app secret values for CameraAccess**

```bash
ssh macdeploy 'cat > ~/deploy-secrets/com.carter.camerai.env <<EOF
OPENAI_API_KEY=<THE_REAL_OPENAI_KEY>
EOF
chmod 600 ~/deploy-secrets/com.carter.camerai.env'
```

- [ ] **Step 6: Verify ASC auth works through the store**

Run: `ssh macdeploy 'cd ~/ios-deploy-engine && set -a && source ~/deploy-secrets/global.env && set +a && bundle exec fastlane run app_store_connect_api_key key_id:$ASC_KEY_ID issuer_id:$ASC_ISSUER_ID key_filepath:$ASC_KEY_P8_PATH'`
Expected: fastlane reports the API key was created (no auth error).

---

## Task 8: CameraAccess config + dry-run end-to-end

**Files:**
- Create: `samples/CameraAccess/ios-deploy.json` in the **meta-wearables-dat-ios** repo (the app being deployed)

Wait — the engine clones the target repo fresh, so `ios-deploy.json` must be committed to the **CameraAccess repo on GitHub**, at the repo root the engine clones. Place it at the repo root.

- [ ] **Step 1: Add ios-deploy.json to the CameraAccess repo root**

Create `ios-deploy.json` at the root of the meta-wearables-dat-ios repo:
```json
{
  "appName": "Camera AI",
  "scheme": "CameraAccess",
  "projectPath": "samples/CameraAccess/CameraAccess.xcodeproj",
  "secrets": [
    {
      "env": "OPENAI_API_KEY",
      "dest": "samples/CameraAccess/CameraAccess/Secrets.plist",
      "key": "OPENAI_API_KEY"
    }
  ]
}
```

- [ ] **Step 2: Commit and push it to the CameraAccess repo**

```bash
git add ios-deploy.json
git commit -m "chore: add ios-deploy.json for generic deploy engine"
git push
```

- [ ] **Step 3: Run a dry-run through the engine**

Run: `ssh macdeploy 'cd ~/ios-deploy-engine && git pull -q && bundle install -q && ./deploy.sh https://github.com/<owner>/meta-wearables-dat-ios --dry-run'`
Expected: log shows `App: Camera AI (com.carter.camerai) scheme=CameraAccess`, the watch target detected, `DRY RUN OK`, and a `dry-run OK` ntfy push lands on the phone.

---

## Task 9: Full end-to-end deploy of CameraAccess

- [ ] **Step 1: Run the real deploy through the generic engine**

Run: `ssh macdeploy 'cd ~/ios-deploy-engine && ./deploy.sh https://github.com/<owner>/meta-wearables-dat-ios'`
Expected: archive succeeds, `gym` exports a signed IPA, `altool` prints "No errors uploading", the lane writes `BUILD_NUMBER`, and a "Camera AI ✅ / Build N is live on TestFlight" push lands on the phone.

- [ ] **Step 2: Confirm in App Store Connect / TestFlight**

The new build number appears in TestFlight processing within ~10 minutes. (User confirms on phone.)

- [ ] **Step 3: Trigger a known failure to prove the failure push works**

Run: `ssh macdeploy 'cd ~/ios-deploy-engine && ./deploy.sh https://github.com/<owner>/this-repo-does-not-exist || true'`
Expected: clone fails, an "❌ FAILED" push lands on the phone with the git error tail.

---

## Task 10: `/deploy` skill (PC)

**Files:**
- Modify: `C:\Users\carte\.claude\plugins\skills\deploy.md`

- [ ] **Step 1: Rewrite the skill to be repo-agnostic**

`C:\Users\carte\.claude\plugins\skills\deploy.md`:
```markdown
---
name: deploy
description: Build any GitHub iOS repo and upload it to TestFlight via the MacInCloud deploy engine
---

Deploy a GitHub iOS repo to TestFlight using the generic engine on MacInCloud.

Usage the user will give you: `/deploy <github-url> [--ref BRANCH] [--dry-run]`

Steps:
1. If no URL was given, ask which GitHub repo to deploy.
2. SSH to the Mac and run the engine, streaming output:
   `ssh macdeploy "cd ~/ios-deploy-engine && git pull -q && ./deploy.sh <github-url> [flags]"`
   (The `macdeploy` host alias is in ~/.ssh/config. The SSH login provides the
   macOS security session that code signing needs.)
3. Watch the streamed output. On success report the app name + build number and
   tell the user it'll appear in TestFlight within ~10 minutes. On failure report
   the exact failing step and error.
4. The engine also sends an ntfy push to the user's phone independently, so a
   detached run still notifies.

Never echo secret values. The engine reads all secrets from ~/deploy-secrets on
the Mac; do not pass keys on the command line.
```

- [ ] **Step 2: Smoke-test the skill**

In a Claude session run `/deploy <owner>/meta-wearables-dat-ios --dry-run` and confirm it SSHes in, streams the dry-run, and reports success.

- [ ] **Step 3: Commit** (the skill lives outside the repo; no repo commit. Note completion in the session.)

---

## Task 11: Retire the GitHub Actions runner + old pipeline

With the engine working, the sessionless-runner workaround is obsolete.

**Files:**
- Delete (Mac): `~/runner-watchdog.sh`, runner cron entries, `~/.ssh/localhost_runner*`, `~/actions-runner`
- Delete (repo): `.github/workflows/testflight-deploy.yml`
- Keep but note: `fastlane/Fastfile`, `Gemfile` in the meta-wearables repo are superseded by the engine

- [ ] **Step 1: Stop and remove the runner**

Run:
```bash
ssh macdeploy 'crontab -l | grep -v runner-watchdog | crontab - || true'
ssh macdeploy 'pkill -f actions-runner/bin/Runner.Listener || true'
ssh macdeploy 'cd ~/actions-runner 2>/dev/null && ./config.sh remove --token <RUNNER_REMOVE_TOKEN> || true'
```
(Get `<RUNNER_REMOVE_TOKEN>` from GitHub repo Settings → Actions → Runners → the runner → Remove.)

- [ ] **Step 2: Clean up runner files and localhost key**

Run: `ssh macdeploy 'rm -rf ~/actions-runner ~/runner-watchdog.sh ~/.ssh/localhost_runner ~/.ssh/localhost_runner.pub; rmdir /tmp/runner-watchdog.lock 2>/dev/null || true'`

- [ ] **Step 3: Remove the workflow from the repo**

Run (in meta-wearables-dat-ios):
```bash
git rm .github/workflows/testflight-deploy.yml
git commit -m "chore: retire GitHub Actions deploy in favor of SSH-driven engine"
git push
```

- [ ] **Step 4: Update the memory note**

Update `C:\Users\carte\.claude\projects\C--Workspace-Active-meta-wearables-dat-ios\memory\testflight-runner-session.md` to record that the runner was retired on completion of the iOS Deploy Service, and that deploys now run via `~/ios-deploy-engine/deploy.sh` over SSH (the SSH login supplies the security session, so the screen/cron workaround is no longer needed).

---

## Self-review notes

- **Spec coverage:** generic engine (Tasks 1–6), auto-detect (T2), config (T3), secrets store + names-in-git/values-on-Mac (T4, T7, T8), produce auto-create (T5), ntfy push success+fail (T1, T6, T9), `--dry-run` self-check (T5, T6, T8), `/deploy` skill (T10), end-to-end on CameraAccess (T9), runner retirement (T11). All spec sections map to tasks.
- **Known ceiling (ponytail):** detection assumes one iOS app target + literal bundle IDs + at most a watch/extension set; `ios-deploy.json` overrides cover the rest. Profile names for the export step come from `SharedValues::SIGH_NAME` captured per sigh call (verify on the first real run in Task 9 that each target's name resolved correctly).
- **Secrets:** no values in git anywhere; all reads go through `~/deploy-secrets`.
