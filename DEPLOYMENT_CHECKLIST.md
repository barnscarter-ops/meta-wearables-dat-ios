# 🚀 Deployment Checklist: Cloud Mac to Physical iPhone

This guide outlines the exact steps to get the CameraAccess app from a Cloud Mac instance onto your physical iPhone using TestFlight.

> **Note:** Phases 2–3 below (manual Xcode archive + Organizer upload) are superseded by the automated `/deploy` engine, which clones `main`, injects secrets, signs, archives, and uploads to TestFlight over SSH. The manual steps are kept for reference / fallback only.

## ✅ Keeping builds green (so `/deploy` is clean every time)

`/deploy` builds a release **archive** of `main`; if `main` doesn't compile, the deploy fails. The **CameraAccess iOS Simulator** GitHub Actions workflow compiles + unit-tests on every push to `main`, so build breakage is caught at push time *before* you deploy. If that workflow is red, fix it before pressing `/deploy`.

Three things have broken the build before — avoid reintroducing them:

1. **Swift 6 main-actor isolation.** A `@MainActor` class that conforms to a delegate protocol (e.g. `WCSessionDelegate`) must mark those delegate methods `nonisolated` — the protocol requirements are nonisolated and a main-actor method can't satisfy them under Swift 6. Likewise, a `static` helper that only reads `ProcessInfo`/`Bundle` (e.g. `GeminiImageService.loadKey()`) should be `nonisolated` so nonisolated code can call it. Bodies that touch main-actor state hop via `Task { @MainActor in … }`.
2. **`Secrets.plist` is gitignored but is a required build input.** It holds API keys, so it's never committed. The deploy engine injects the real keys from `~/deploy-secrets/<bundle-id>.env`; CI copies `Secrets.plist.example` (placeholder values that `loadKey()` rejects, falling back to sample analysis). Never commit real keys.
3. **AI model names get retired.** Keep model strings current. Gemini uses `gemini-2.5-flash` (`gemini-2.0-flash` now returns HTTP 404). OpenAI uses `gpt-4o` / `gpt-4.1-mini`.

## 🛠 Phase 1: Account Setup
- [ ] **Apple Developer Program**: Enroll at [developer.apple.com](https://developer.apple.com/). (Required for TestFlight).
- [ ] **Cloud Mac Instance**: Set up your MacinCloud or AWS Mac instance.
- [ ] **Git Clone**: Clone the repository to the Cloud Mac.
- [ ] **Secrets Setup**: Create `Secrets.plist` on the Cloud Mac and add your `OPENAI_API_KEY`.

##  Xcode Configuration
- [ ] **Open Project**: Open `samples/CameraAccess/CameraAccess.xcodeproj`.
- [ ] **Signing & Capabilities**:
    - [ ] Select the **CameraAccess** target.
    - [ ] Set **Team** to your Apple ID.
    - [ ] Ensure **Bundle Identifier** is unique (e.g., `com.yourname.CameraAccess`).
- [ ] **Permissions Audit**: Verify `Info.plist` contains:
    - [ ] `NSCameraUsageDescription`
    - [ ] `NSMicrophoneUsageDescription`
    - [ ] `NSBluetoothAlwaysUsageDescription`
    - [ ] `NSLocalNetworkUsageDescription`

## 📦 Phase 2: Distribution (The Archive Process)
- [ ] **Build Target**: Change the target device from a simulator to **"Any iOS Device (arm64)"**.
- [ ] **Clean Build**: `Product` $\rightarrow$ `Clean Build Folder` (`Cmd + Shift + K`).
- [ ] **Archive**: `Product` $\rightarrow$ `Archive`.
- [ ] **Upload**: 
    - [ ] In the Organizer window, click **Distribute App**.
    - [ ] Select **App Store Connect** $\rightarrow$ **Upload**.
    - [ ] Follow the prompts to upload the build to Apple's servers.

## 📱 Phase 3: iPhone Installation (TestFlight)
- [ ] **App Store Connect**: Log into [appstoreconnect.apple.com](https://appstoreconnect.apple.com/).
- [ ] **App Setup**: Create a new app record if this is the first time.
- [ ] **Internal Testing**: 
    - [ ] Go to the **TestFlight** tab.
    - [ ] Create an "Internal Testing" group.
    - [ ] Add your own email address as a tester.
- [ ] **Install**: 
    - [ ] Download the **TestFlight app** from the App Store on your iPhone.
    - [ ] Accept the invitation email.
    - [ ] Tap **Install** on the CameraAccess app.

## 👓 Phase 4: Hardware Testing
- [ ] **Developer Mode**: On iPhone, go to `Settings` $\rightarrow$ `Privacy & Security` $\rightarrow$ `Developer Mode` $\rightarrow$ **ON**.
- [ ] **Glasses Pairing**: Ensure glasses are paired with the Meta View app.
- [ ] **Run App**: Open CameraAccess $\rightarrow$ Connect $\rightarrow$ Start Streaming $\rightarrow$ Test "Ask AI".
