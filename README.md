# OpenEbook build

Source is hosted in the private GitHub repository `Hthancder/OpenEbook`. The internal Xcode target and artifact retain the name `BookReader`.

Run **Actions > iOS Reader > Run workflow** on `main`. The existing workflow generates the project, resolves packages, runs core and simulator tests, then builds the unsigned arm64 application. A successful run uploads `BookReader-ios15-unsigned`, containing the IPA and its SHA-256 file. Signing and installation on the device remain the owner's responsibility.

## Checks

```sh
swift test --package-path .
xcodegen generate --spec project.yml
xcodebuild -project BookReader.xcodeproj -scheme BookReader -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO test
```

Windows cannot run the Apple toolchain locally. Hosted run `44781153112` at revision `aee1c58` passed the portable core tests and compiled the iOS app, but the app crashed at startup while Core Data installed uniqueness constraints before its properties. The constraint-order fix still needs a hosted run; there is no verified IPA yet. EPUB import remains deliberately blocked with a network-policy message because first-load network isolation is unverified. Do not describe offline EPUB acceptance as met. Simulator UI, device IPA, iOS 15 device operation, VoiceOver, rotation and memory pressure remain unverified.

