# OpenEbook build

Source is hosted in the private GitHub repository `Hthancder/OpenEbook`. The internal Xcode target and artifact retain the name `BookReader`.

Run **Actions > iOS Reader > Run workflow** on `main`. The existing workflow generates the project, resolves packages, runs core and simulator tests, then builds the unsigned arm64 application. A successful run uploads `BookReader-ios15-unsigned`, containing the IPA and its SHA-256 file. Signing and installation on the device remain the owner's responsibility.

## Checks

```sh
swift test --package-path .
xcodegen generate --spec project.yml
xcodebuild -project BookReader.xcodeproj -scheme BookReader -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO test
```

Windows cannot run the Apple toolchain locally. Hosted run `44795104641` at revision `f20d8a6` passed 7 portable core tests, 14 iOS unit tests and the empty-library/file-picker UI smoke test, then built and uploaded an unsigned arm64 IPA for iOS 15.0. The downloaded IPA passed ZIP integrity, SHA-256, bundle metadata and Mach-O architecture checks. Its SHA-256 is `96202b18e8bdabf02b7939a2545f7e3ee02e5a96a3782d02dc12dfbda2412b42`.

Actual PDF/TXT reading, search, bookmarks and reopening are being checked separately; the earlier picker smoke does not establish these behaviors. EPUB import remains deliberately blocked with a network-policy message because first-load network isolation is unverified. Do not describe offline EPUB acceptance as met. iOS 15 device operation, VoiceOver, rotation and memory pressure remain unverified.

