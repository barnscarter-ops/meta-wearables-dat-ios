# 🚀 Deployment Checklist: Cloud Mac to Physical iPhone

This guide outlines the exact steps to get the CameraAccess app from a Cloud Mac instance onto your physical iPhone using TestFlight.

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
