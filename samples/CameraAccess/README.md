# Camera Access App

A sample iOS application demonstrating integration with Meta Wearables Device Access Toolkit. This app showcases streaming video from Meta AI glasses, capturing photos, and managing connection states.

## Features

- Connect to Meta AI glasses
- Stream camera feed from the device
- Capture photos from glasses
- Send captured photos to ChatGPT for image analysis
- Share captured photos
- Open firmware and glasses app update flows when required

## Prerequisites

- iOS 17.0+
- Xcode 14.0+
- Swift 5.0+
- Meta Wearables Device Access Toolkit (included as a dependency)
- A Meta AI glasses device for testing (optional for development)

## Building the app

### Using Xcode

1. Clone this repository
1. Open the project in Xcode
1. Select your target device
1. Click the "Build" button or press `Cmd+B` to build the project
1. To run the app, click the "Run" button (▶️) or press `Cmd+R`

## Running the app

1. Turn 'Developer Mode' on in the Meta AI app.
1. Launch the app.
1. Press the "Connect" button to complete app registration.
1. Once connected, the camera stream from the device will be displayed
1. Use the on-screen controls to:
   - Capture photos
   - Ask ChatGPT to analyze the captured photo
   - View and save captured photos
   - Disconnect from the device
1. If a firmware update is required, tap "Update firmware" from the connection screen.
1. If session start reports that the app on the glasses is outdated, tap "Update app on glasses" from the connection screen.

## ChatGPT photo analysis

The photo preview includes an **Ask ChatGPT** panel. Capture a photo from the glasses, enter an OpenAI API key, adjust the prompt if needed, and tap the sparkle button to send the JPEG to the OpenAI Responses API for image analysis.

For simulator-only development, you can pass the API key through the app launch environment as `OPENAI_API_KEY`. Do not commit API keys to source control or ship a production app with a user-visible project API key. For production, proxy requests through your own backend or use an ephemeral-token flow appropriate for your security model.

The sample uses `gpt-4.1-mini` by default and sends the captured image as a base64 `data:image/jpeg` URL.

## Troubleshooting

For issues related to the Meta Wearables Device Access Toolkit, please refer to the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or visit our [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions)

## License

This source code is licensed under the license found in the LICENSE file in the root directory of this source tree.
