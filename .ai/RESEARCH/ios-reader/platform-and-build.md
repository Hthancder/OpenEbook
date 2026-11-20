
Ngày tra cứu: 2026-11-19. Phạm vi: thiết kế trước triển khai, không có app/build/runtime evidence.

## Bottom line

Đề xuất app Swift/SwiftUI iOS 15, Readium 3.11.1 cho EPUB, PDFKit cho PDF và reader native nhỏ cho TXT. Build arm64 bằng GitHub Actions macOS, đóng gói IPA chưa ký; người dùng tự xử lý cài máy jailbreak. Đây là phương án thiết kế cần duyệt, không phải dependency đã cài.

## Hiện trạng và so sánh

Thư mục dự án ban đầu trống: không có code hoặc pattern sản phẩm để tái dùng.

| Phương án | Bằng chứng | Quyết định |
|---|---|---|
| Readium Swift 3.11.1 | Manifest tag khai báo iOS 15.0, Swift tools 5.10; guide có local FileURL, opener, SwiftUI navigator; BSD-3-Clause | Đề xuất dùng cho EPUB, pin đúng tag và dependency graph đã resolve thực |
| FolioReaderKit | GitHub repo API trả archived=true, pushed_at 2020-09-22T23:49:02Z | Không chọn cho nền tảng mới |
| Tự dựng EPUB từ WKWebView + ZIP | Phải tự sở hữu parsing/spine, layout, locator, search và security | Không chọn thay toolkit; chỉ thêm policy/preflight còn thiếu nếu thật sự cần |
| PDFKit | Framework Apple có PDFView hỗ trợ hiển thị, zoom, điều hướng, chọn nội dung; PDFPage.string đọc text layer | Dùng cho PDF, không kỳ vọng OCR/reflow tự động |

## Nguồn và reference implementations

1. Readium package pinned: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/Package.swift
2. Readium local-file opener: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Guides/Open%20Publication.md
3. Readium SwiftUI wrapper: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Guides/Navigator/SwiftUI.md
4. Official reference reader: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/TestApp/README.md (EPUB2/3 reflow/fixed, PDF, mục lục, styles; không sao chép project setup/DRM không cần thiết).
5. Readium search reference: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Guides/Search.md (kiểm tra isSearchable, SearchIterator, options thực hỗ trợ).
6. Readium migration: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Migration%20Guide.md (3.8 bỏ server cho EPUB; 3.9 bỏ server cho PDF, nên không mang dependency GCDWebServer cũ vào app).
7. Readium license: https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/LICENSE (BSD-3-Clause, phải giữ copyright/conditions/disclaimer trong source/binary notices).
8. PDFKit reference: https://developer.apple.com/documentation/pdfkit/pdfview ; https://developer.apple.com/documentation/pdfkit/pdfpage/string
9. WebKit content filtering: https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:)
10. Runner image source: https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-15-Readme.md (đọc danh sách có Xcode 16.4; image thay đổi, phải kiểm tra lúc job chạy).
11. Actions cost source: https://docs.github.com/en/billing/concepts/product-billing/github-actions (standard public-repo compute miễn phí; không suy ra storage/private-repo miễn phí vô hạn).
12. Speech API: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer ; https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice (liệt kê voice thực có trên device, không hứa mọi iOS15 đều có giọng Việt offline).
13. Alternative metadata: https://api.github.com/repos/FolioReader/FolioReaderKit

## Pitfalls và quyết định liên quan

- Readium HTTP URL có thể stream thay vì copy: nhập phải dùng bản sao local sau khi hoàn tất, nếu muốn offline thật.
- Chế độ máy bay chỉ chứng minh không bắt buộc mạng ở kịch bản đó, không chứng minh EPUB không rò request khi mạng bật. Cần policy cho tất cả WKWebView và native-resource loads, fixture remote CSS/font/image/script và quan sát request.
- ZIP header size có thể không đáng tin: phải giới hạn số entry, đường dẫn, bytes thực đọc/giải nén và có test fixture độc hại. Không tự viết parser ZIP lớn khi có library thực sự đáp ứng; xác minh API trước khi chọn.
- Catalog và filesystem không transaction chung: staging, commit và recovery phải chỉ động vào dữ liệu của thao tác đó, không reset thư viện khi lỗi.
- Readium sample có tính năng/DRM/dependency ngoài phạm vi. Chỉ dùng product phục vụ EPUB và giữ notices của graph thực tế.
- Xcode/simulator mới build target iOS15 không phải evidence chạy trên runtime iOS15. Cần thử máy người dùng cho claim real-device.
- Unsigned device IPA không phải App Store export và không đảm bảo mọi cách cài jailbreak. Quy trình cài nằm phía người dùng.

## CAVN

- Claim: Readium 3.11.1 khai báo nền tảng iOS 15. Authority: Package.swift của tag. Validation: đọc manifest, KHÔNG compile. Next: resolve graph và xcodebuild qua Actions.
- Claim: EPUB navigator không cần local HTTP server. Authority: migration guide 3.8/3.9. Validation: đọc tài liệu cùng tag. Next: dùng scheme handler và xác minh assets thực chạy.
- Claim: PDFKit cung cấp chức năng PDF native. Authority: Apple PDFView/PDFPage docs. Validation: đọc tài liệu. Next: smoke PDF có chữ/scan trên simulator và device.
- Claim: standard public repo compute được miễn phí. Authority: GitHub billing docs. Validation: đọc tài liệu. Next: giữ retention/cost guard, không tự chọn tài khoản/visibility hay runner tính phí.
- Claim: có thể chặn mọi network của nội dung EPUB trong tổ hợp chọn. Authority: chưa có đầy đủ bằng chứng hook của Readium. Validation: UNVERIFIED. Next: spike có mục tiêu, không coi content-rule API tồn tại là enforcement đã hoạt động.

## Giới hạn bằng chứng

UNVERIFIED: graph version/license cuối cùng, build Readium + Xcode, điều khiển tất cả web view/native loaders để chặn mạng, archive preflight enforcement, RAM/độ mượt trên iOS15, chạy IPA trên thiết bị. Không có app, CI run, remote repository hoặc quyền push được tạo ra trong bước nghiên cứu này.

Một đường dẫn guide ban đầu không đúng trả HTTP 404; đã chuyển sang guide `Open Publication.md` tìm từ directory listing. Hai lần thử parse JSON của GitHub tree/directory qua output rút gọn không thành công; không dùng chúng làm bằng chứng tìm hook an toàn. Các kết luận ở trên dựa vào tài liệu đã đọc riêng, không dựa vào những parse lỗi đó.

## Actions build findings, 2026-11-20

- The pinned Readium ZIPFoundation 3.0.1 `Entry` exposes `path`, `type`, `compressedSize`, `uncompressedSize`, and `isCompressed`; its encryption bit is internal to `CentralDirectoryStructure`, not a public `Entry.isEncrypted` member. Build failure on that assumed property was fixed by using only public `Entry` APIs. Source: [Entry.swift at 3.0.1](https://raw.githubusercontent.com/readium/ZIPFoundation/3.0.1/Sources/ZIPFoundation/Entry.swift).
- Shared `CoreTests.swift` compiles in two modules: select `@testable import BookReaderCore` under `SWIFT_PACKAGE`, otherwise `@testable import BookReader`. Both retain `ReadiumZIPFoundation` for archive fixtures. UI tests launch `XCUIApplication` and must not import the app module merely to drive it.
- Readium Swift Toolkit 3.11.1's `NavigatorDelegate` requires `presentError`; the EPUB delegate must implement it. `EPUBNavigatorViewController` is provided by the `ReadiumNavigator` product. Source: [Navigator.swift](https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/Sources/Navigator/Navigator.swift) and [EPUBNavigatorViewController.swift](https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift).
- SwiftSoup `parseXML` returns a `Document`, not the OPF `package` element. Validate the actual child root before reading `version`. XML tag names preserve prefixes; metadata traversal handles local names. Namespace CSS selector support was not disproven by the earlier failed runs: those runs threw at the document-tag guard before reaching selectors. Sources: [XmlTreeBuilder.swift](https://raw.githubusercontent.com/scinfu/SwiftSoup/2.13.5/Sources/XmlTreeBuilder.swift), [Element.swift](https://raw.githubusercontent.com/scinfu/SwiftSoup/2.13.5/Sources/Element.swift).
- Superseding hosted evidence: run `44822095576`, revision `2958437`, completed successfully. Portable core 7/7, iOS unit 15/15 and actual UI 3/3 passed, including PDF/TXT search, bookmark navigation and terminate/relaunch persistence. The unsigned device IPA was built, uploaded, downloaded and checked for ZIP integrity, matching SHA-256, arm64 device Mach-O/minimum iOS 15.0, native launch metadata and absence of debug simulator fixture markers. See README for the exact artifact and checksum. Physical iOS 15 use remains unverified.

UNVERIFIED: EPUB first-load network isolation on iOS remains a release gate. This build failure/fix sequence does not establish EPUB privacy or device behavior.
