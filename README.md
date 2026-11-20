# OpenEbook build

Source is hosted in the private GitHub repository `Hthancder/OpenEbook`. The internal Xcode target and artifact retain the name `BookReader`.

Run **Actions > iOS Reader > Run workflow** on `main`. The existing workflow generates the project, resolves packages, runs core and simulator tests, then builds the unsigned arm64 application. A successful run uploads `BookReader-ios15-unsigned`, containing the IPA and its SHA-256 file. Signing and installation on the device remain the owner's responsibility.

## Checks

```sh
swift test --package-path .
xcodegen generate --spec project.yml
xcodebuild -project BookReader.xcodeproj -scheme BookReader -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO test
```

Hosted run `44822095576` at revision `2958437` passed 7 portable core tests, 15 iOS unit tests and 3 simulator UI tests, then built and uploaded `BookReader-ios15-unsigned`. The UI tests opened actual imported PDF/TXT files, searched and selected results, navigated bookmarks, terminated the app and verified the saved reading position and bookmarks after relaunch. The picker opening/cancellation smoke also passed. Screenshots are retained in the `simulator-evidence` artifact.

The downloaded IPA is 5,290,460 bytes. ZIP integrity and SHA-256 match; the executable is arm64 for iOS devices with a Mach-O minimum OS of 15.0, matching the app metadata. Bundle ID: `app.bookreader.ios`; version/build: `1.0` / `1`. The generated native launch screen and third-party notices are present. Debug simulator fixture markers are absent from the Release binary. SHA-256: `66998c898651c50220041d809e55f55f1e286d7a1d30e3c94aa72489e2968578`.

Local artifact: `build/artifacts/run-44822095576/BookReader-ios15-unsigned.ipa`. In GitHub, open run `44822095576` and download artifact `BookReader-ios15-unsigned` (artifact ID `14672907566`). Artifact retention is 3 days; keep the local copy. Screenshots and the retrieved run log are saved under `build/evidence/run-44822095576/`.

EPUB import remains deliberately blocked: a structurally complete EPUB fixture is rejected with `.networkPolicy`, with no catalog or staged book data left behind. This verifies the fail-closed boundary, not offline EPUB reading or first-load network isolation. Physical iOS 15 installation/use, VoiceOver, rotation and memory pressure remain unverified. The simulator ran a newer iOS runtime; a deployment target of 15.0 is not proof of real-device iOS 15 operation. Signing and device installation are outside this build's verification.

