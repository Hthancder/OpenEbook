## Checks

```sh
swift test --package-path .
xcodegen generate --spec project.yml
xcodebuild -project BookReader.xcodeproj -scheme BookReader -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO test
```

These checks have not run in the current Windows workspace because Swift, XcodeGen and Xcode are unavailable here. EPUB first-load network isolation is not verified: Readium 3.11.1 invokes its script-setup delegate after constructing/loading the initial spread, so the existing callback cannot prove the required first-load behavior. Do not describe the EPUB offline-security acceptance as met. Simulator UI, generated device IPA, iOS 15 device operation, VoiceOver, rotation and memory pressure also await a macOS workflow/device run.

