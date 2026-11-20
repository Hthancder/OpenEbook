# Thiết kế ứng dụng đọc sách iOS 15

Trạng thái: CHỜ DUYỆT THIẾT KẾ. Không phải báo cáo ứng dụng hoạt động.

## 1. Hợp đồng sản phẩm

- Người dùng: chủ iPhone chạy iOS 15, muốn nhập sách cá nhân và đọc thuận tiện, không trả phí dịch vụ.
- acceptance_mode: real-use cho phạm vi đọc sách của bản đầu; không coi ảnh giao diện hay dữ liệu mẫu là sản phẩm đạt yêu cầu.
- Điểm vào tích hợp: mở ứng dụng trên iPhone > Nhập sách > chọn file trong ứng dụng Tệp > mở sách trong thư viện.
- Kênh build: GitHub Actions trên runner macOS; tạo ứng dụng arm64 cho thiết bị thật và artifact IPA chưa ký để người dùng xử lý cài trên máy jailbreak.
- Việc ký đặc thù jailbreak, công cụ cài và phát hành App Store nằm ngoài phạm vi. Không yêu cầu người dùng sở hữu Mac.
- Thành công: nhập một EPUB tiếng Việt có mục lục, đọc chương 2, thay cỡ chữ, đóng và mở lại ứng dụng khi bật chế độ máy bay, tiếp tục tại cùng đoạn; PDF và TXT có kịch bản tương đương ở mục 11.
- Thất bại phải xử lý: chọn EPUB hỏng hoặc có DRM; ứng dụng nêu rõ lý do và giữ nguyên các sách đang có, không hiện sách rỗng như thể nhập thành công.

## 2. Yêu cầu đã có và lựa chọn của người thiết kế

Đã có từ người dùng: iOS 15, build bằng GitHub Actions, người dùng tự xử lý cài đặt trên máy jailbreak; trước mắt tập trung xem/đọc ebook và giao diện trực quan; mong muốn TTS miễn phí, offline trong hướng phát triển tiếp theo.

Lựa chọn đề xuất, cần duyệt cùng tài liệu: Swift + SwiftUI, giao diện tiếng Việt, không tài khoản/server, PDF + EPUB không DRM + TXT cho bản đầu; thêm dấu trang và tìm kiếm để đọc thực tế. Tên target nội bộ dự kiến `BookReader`, không phải tên thương hiệu đã được người dùng chọn.

Không suy diễn 'etc đủ tính năng' thành cam kết hỗ trợ mọi định dạng, OCR, AI hoặc TTS ngay bản đầu.

## 3. Phạm vi bản đầu

### Có

- Nhập một hoặc nhiều file qua bộ chọn Tệp; có tiến độ, kết quả từng file và khả năng hủy hàng đợi.
- Sao chép sách vào vùng dữ liệu riêng để đọc offline sau khi nhập thành công.
- Thư viện có bìa/ảnh thay thế, tiêu đề, tác giả nếu có, loại file, tiến độ đọc; tìm theo tiêu đề/tác giả; sắp xếp theo đọc gần đây, tên hoặc ngày thêm.
- Khu vực 'Đọc tiếp' trên đầu thư viện, không phải một tab lặp lại thư viện.
- Đọc PDF, EPUB và TXT; mở mục lục nếu tài liệu có; điều hướng, tìm trong văn bản khi định dạng cung cấp văn bản; đánh dấu trang; tự lưu vị trí.
- Sáng/tối theo hệ thống hoặc chọn tay; EPUB reflow/TXT có nền giấy, cỡ chữ, giãn dòng; PDF và EPUB fixed-layout giữ bố cục gốc.
- Chi tiết sách: thông tin sẵn có, tên file nguồn, loại, kích thước, thời điểm thêm, trạng thái đọc; thiếu metadata thì dùng tên file, không tự chế tác giả.
- Xóa bản sao trong ứng dụng sau xác nhận có nêu tên sách; không xóa file nguồn trong Tệp.
- Hướng dẫn, phiên bản ứng dụng và thông báo giấy phép trong Cài đặt.

### Chưa có trong bản đầu

- TTS, nghe nền, điều khiển màn hình khóa, OCR, đồng bộ nhiều máy, dịch/tóm tắt, tải sách từ website, cửa hàng sách.
- MOBI/AZW/AZW3, FB2, DOCX, DJVU, CBR/CBZ, audiobook và giải mã DRM. Các loại này báo chưa hỗ trợ, không mở qua một màn hình giả.
- Highlight/ghi chú, xuất dữ liệu, sửa metadata, chỉnh sửa PDF và chuyển đổi định dạng.
- Không hiện nút TTS hay tab tính năng chưa hoạt động. Việc thêm tính năng ngoài danh sách phải đổi phạm vi có chủ ý.

## 4. Hợp đồng định dạng

| Loại | Đọc/điều hướng | Tùy chỉnh và tìm kiếm | Giới hạn rõ ràng |
|---|---|---|---|
| PDF | PDFKit, cuộn dọc, zoom, số trang, thumbnail theo nhu cầu, outline nếu có | Tìm trên lớp chữ sẵn có, dấu trang theo trang | PDF scan vẫn xem được; không có lớp chữ thì không OCR/tìm nội dung; không reflow hoặc giả đổi cỡ chữ |
| EPUB 2/3 không DRM | Readium, reflow hoặc fixed-layout, mục lục, chuyển chương, phân trang | Reflow có cỡ chữ/nền/giãn dòng; tìm theo khả năng publication; fixed-layout dùng điều khiển phù hợp | Không tải tài nguyên ngoài mạng; EPUB chỉ có ảnh vẫn xem ảnh nhưng không giả hỗ trợ tìm chữ; không hứa hiển thị tuyệt đối mọi CSS/font của nhà xuất bản |
| TXT | Bộ đọc văn bản native, chia thành các khối/đoạn để không dựng cả sách trong một view | UTF-8, UTF-8 BOM, UTF-16 có BOM; tìm, cỡ chữ/nền/giãn dòng; không có mục lục giả | Không đoán mã hóa legacy khi giải mã thất bại; báo cần chuyển sang UTF-8, không thay ký tự âm thầm |

PDF khóa bằng mật khẩu: phát hiện và báo chưa hỗ trợ ở bản đầu; không thử phá khóa. File có đuôi đúng nhưng nội dung sai phải bị từ chối sau kiểm tra thực chất.

## 5. Màn hình và hành vi

### Thư viện

- Thanh trên: tiêu đề 'Thư viện', nút Nhập sách, nút Cài đặt; ô tìm kiếm có nhãn rõ.
- Thư viện trống: thông báo chưa có sách và một hành động Nhập sách thực sự mở bộ chọn.
- Khi có sách: một thẻ Đọc tiếp, bên dưới là danh sách hoặc lưới có lựa chọn chuyển cách xem, không trưng cùng một danh sách hai lần.
- Card sách có bìa, tên, loại file và tiến độ có nhãn chữ; thiếu bìa dùng biểu tượng sách và tên, không dùng bìa giả.
- Đang nhập: tiến độ dạng số file đã xử lý/tổng số, không dùng phần trăm bịa cho bước chưa đo được; lỗi từng file không che kết quả các file khác.
- Tìm không có kết quả: phân biệt với thư viện trống; cho phép xóa từ khóa.

### Màn hình đọc

- Thanh trên: quay lại thư viện, tên sách rút gọn, mục lục nếu có, tìm kiếm nếu có chữ, dấu trang; không nhồi tất cả thành nút bé.
- Thanh dưới: vị trí và điều hướng; EPUB reflow/TXT có nút kiểu chữ; PDF có số trang/thumbnail và zoom native.
- Nội dung là vùng chiếm diện tích chính; chạm vùng đọc có thể ẩn/hiện thanh công cụ nhưng không nuốt thao tác chọn chữ, link, zoom hoặc VoiceOver.
- Mục lục/tìm kiếm/dấu trang dùng sheet hoặc danh sách phụ; chọn một mục phải điều hướng đến đúng vị trí và đóng sheet khi phù hợp.
- PDF tối màu chỉ áp dụng chrome/nền vùng ngoài trang, không đảo màu ảnh hay cam kết làm trang PDF tối.
- Link ngoài không tải tự động. Khi người dùng chủ động mở link ngoài, hỏi trước khi chuyển sang trình duyệt; liên kết nội bộ phải giữ trong sách.
- Lưu vị trí sau khi điều hướng ổn định và khi chuyển nền; không chỉ lưu khi nhấn quay lại.

### Cài đặt và khả năng tiếp cận

- Chọn giao diện, thiết lập chữ mặc định cho sách văn bản, hướng dẫn định dạng và giấy phép thư viện.
- Dùng màu hệ thống có tương phản đọc được; màu chỉ làm dấu nhấn cho thao tác chính và tiến độ, không gradient/decorative card không có mục đích.
- Chữ giao diện hỗ trợ Dynamic Type; nút tối thiểu 44 x 44 pt, có nhãn VoiceOver và trạng thái dấu trang bằng chữ/nhãn truy cập, không chỉ màu.
- Hỗ trợ portrait/landscape và safe area; kiểm tra chữ lớn không che nút thoát/mục lục. Chất lượng truy cập nội dung EPUB phụ thuộc cấu trúc nguồn, không tuyên bố thay thế kiểm tra thực tế.

## 6. Kiến trúc và ràng buộc iOS 15

- SwiftUI dùng các API có từ iOS 15; UIKit wrapper cho Readium navigator, PDFView và bộ đọc TXT khi cần. Không dùng SwiftData, NavigationStack hay API chỉ có ở hệ điều hành mới mà không có phương án iOS 15.
- Readium Swift Toolkit khóa đúng phiên bản 3.11.1, không theo nhánh develop. Package manifest của tag này khai báo iOS 15.0 và Swift tools 5.10 [S1]; đây là bằng chứng khai báo tương thích, chưa phải bằng chứng app chạy trên máy thật.
- Chỉ liên kết các product phục vụ EPUB; không liên kết OPDS/LCP, ReadiumAdapterGCDWebServer hoặc thêm chức năng DRM. Theo migration guide cùng tag, từ 3.8 EPUB navigator dùng custom URL scheme handler thay HTTP server [S10]; app này không cần listener loopback/LAN. Kiểm tra phần phụ thuộc thực sự được kéo theo trước khi khóa toàn bộ graph.
- PDFKit của Apple cho PDF [S3]. Không dùng chung engine EPUB để làm lại phần hiển thị PDF sẵn có.
- Core Data cho thư viện/dấu trang/vị trí đọc; FileManager cho file; UserDefaults cho tùy chọn nhỏ. Core Data được chọn thay SwiftData để giữ iOS 15 và tránh thêm thư viện DB.
- Các ranh giới: Library/Import, ReaderHost, EPUBReader, PDFReader, TextReader, ReadingStateStore, Settings. Không tạo framework/plugin system tổng quát hoặc abstraction cho tính năng chưa tồn tại.
- Tách metadata/điều hướng khỏi giao diện đủ để sau này TTS đọc nội dung, nhưng không viết engine TTS rỗng hoặc parser dự phòng không hoạt động.

Luồng: Tệp của iOS -> vùng staging nội bộ -> kiểm tra/nhận dạng -> mở thử metadata -> chuyển vào thư mục sách -> lưu catalog -> thư viện -> reader đúng định dạng -> lưu vị trí đọc.

## 7. Lưu trữ, nhập và phục hồi

- `Application Support/Books/<UUID>/original.<ext>` giữ bản sao sách; không dùng tên file người dùng làm đường dẫn đích.
- Core Data lưu ID, đường dẫn tương đối, format, metadata, kích thước, SHA-256 của file đã nhập, ngày thêm/đọc, vị trí và dấu trang. Bìa/thumbnail là cache có thể tạo lại, không phải bản sách duy nhất.
- EPUB lưu Readium Locator JSON có version; PDF lưu trang 0-based và tọa độ điểm neo nếu khả dụng; TXT lưu vị trí trong văn bản đã chuẩn hóa cùng version chuẩn hóa. Dấu trang dùng cùng mô hình vị trí với reader tương ứng.
- Chỉ ghi nhận sách khi sao chép và parse tối thiểu thành công. Hủy/lỗi nhập không sinh mục catalog dở dang. Không sửa file nguồn.
- File provider có thể cần tải file iCloud trước: hiển thị đang lấy file; mất mạng thì thông báo tải chưa được, không hứa đọc offline file chưa nhập.
- Tính hash theo luồng trong khi copy, không nạp toàn bộ sách vào RAM. Trùng byte thì báo đã có và dẫn đến cuốn hiện có; cùng tên nhưng nội dung khác vẫn nhập được.
- Hàng đợi nhập xử lý từng file để giới hạn RAM; thao tác đọc vẫn có thể hủy/thoát; kết quả bất đồng bộ phải gắn book ID, không đè sách người dùng vừa chuyển sang.
- Giới hạn khởi đầu do người thiết kế chọn: 250 MiB/file, TXT 20 MiB; EPUB tối đa 10.000 entry, tổng dung lượng giải nén khai báo/đọc 1 GiB và mỗi entry 100 MiB. Đo thực tế và điều chỉnh có chủ ý, không cam kết đọc file vô hạn.
- Kiểm tra archive trước khi nội dung được giải nén; từ chối đường dẫn traversal, đường dẫn tuyệt đối, symlink nguy hiểm và archive vượt ngân sách. Không coi kiểm tra đuôi file là cơ chế an toàn. Nếu Readium/dependency không cung cấp đủ kiểm soát, phải có preflight streaming phù hợp và minh chứng bằng fixture trước khi chấp nhận nhập EPUB.
- Filesystem và Core Data không chung transaction: copy vào staging, chuyển đích, save catalog; nếu save thất bại thì chỉ rollback dữ liệu của lượt nhập đó. Khởi động sau crash phải phát hiện file mồ côi, không làm mất sách đã ghi nhận. Không tự xóa dữ liệu sách không nhận dạng được.
- Xóa sách: xác nhận nêu tên; nếu filesystem/catalog cập nhật lỗi, giữ khả năng retry và nêu kết quả thật, không báo đã xóa khi bản ghi/file còn ở trạng thái không nhất quán.
- Ghi persistence lỗi phải báo khả năng mất vị trí mới; không nuốt lỗi như thể lưu thành công. Core Data store không mở được thì hiện lỗi và hướng khôi phục, không tự xóa/reset thư viện.

## 8. Offline, riêng tư và lỗi

- Không backend, telemetry, quảng cáo, tài khoản hay API tính phí. Sách không được tải lên đâu.
- EPUB chỉ đọc file/tài nguyên nội bộ qua scheme handler của Readium, không mở server cục bộ. Chặn fetch HTTP(S), ảnh/font/CSS từ xa và kết nối do nội dung sách khởi tạo; chặn subresource và request chứ không chỉ link điều hướng. Thiết kế enforcement: cài content rules vào mọi web view trước lần load đầu, phối hợp policy cho tài nguyên do native loader yêu cầu; không bật ATS exception toàn cục. API WebKit có content filtering [S11], nhưng hook cấu hình tất cả web view của Readium phải được chứng minh bằng spike trước khi tích hợp production. Nếu thiếu hook an toàn, ghi rõ incompatibility và đề xuất thay đổi để duyệt; không bỏ qua chính sách chặn mạng.
- Tài nguyên từ xa bị chặn không làm ứng dụng treo: giữ bố cục đọc được và báo nội dung thiếu khi cần. Việc chặn mạng của EPUB là acceptance riêng, không suy ra từ việc chỉ thử chế độ máy bay.
- Thông báo lỗi phân biệt: file không hỗ trợ, hỏng, DRM/mật khẩu, thiếu dung lượng, quá giới hạn, tải từ provider thất bại, chưa có lớp chữ. Có đóng/thử lại khi thực sự có thể thử lại.
- Tìm kiếm theo lô, có hủy, giới hạn kết quả hiển thị mỗi lượt; đổi từ khóa hoặc sách hủy yêu cầu cũ. PDF không trích xuất toàn bộ để hiển thị trang đầu; thumbnail lazy và cache giới hạn.
- Không gửi đường dẫn cá nhân/nội dung sách vào log CI hoặc log chẩn đoán. Fixture dùng sách tự tạo hoặc có quyền phân phối rõ.

## 9. GitHub Actions và artifact

- Đề xuất `macos-15`, chọn cụ thể Xcode 16.4 và kiểm tra đường dẫn/toolchain trước build; bản runner được tra cứu hiện liệt kê Xcode này [S5]. Không dựa vào Xcode mặc định hoặc nhãn macos-latest.
- Khóa package version và lưu Package.resolved của graph thực sự resolve được; không bịa lockfile bằng tay. Cache SPM theo toolchain + lockfile; cache miss vẫn phải build được.
- Cung cấp Xcode project/scheme được chia sẻ trong repo; không bắt người dùng cài XcodeGen/CocoaPods chỉ để workflow hoạt động. Không thêm package hoặc công cụ toàn cục trước phê duyệt triển khai.
- Trigger: workflow_dispatch và push/PR theo đường dẫn liên quan; hủy run cũ cùng nhánh; workflow chỉ có quyền contents:read. PR không có secrets vẫn có thể build/check.
- Build/check simulator trong job xác minh; chọn simulator thực sự có trên runner. Run simulator mới không chứng minh iOS 15 runtime.
- Build Release `generic/platform=iOS`, `IPHONEOS_DEPLOYMENT_TARGET=15.0`, arm64, tắt yêu cầu ký cho bản artifact phục vụ jailbreak; không cần Apple certificate/provisioning secret cho đường này.
- Đóng gói cấu trúc `Payload/BookReader.app` thành `BookReader-ios15-unsigned.ipa`, kèm SHA-256 và thông tin commit/toolchain. Ghi rõ unsigned; không dùng exportOptions của App Store để giả tạo bản ký.
- Kiểm tra kiến trúc executable, MinimumOSVersion, resource/Readium bundle và cấu trúc IPA trước upload. Thiếu resource bundle phải làm job thất bại, không chỉ kiểm tra file IPA tồn tại.
- Build check, test và đóng gói lỗi thì job thất bại, không continue-on-error hoặc upload artifact nhãn release thành công.
- Pin actions theo commit đã xác minh trong lúc triển khai; artifact build riêng tư không chứa sách cá nhân. Retention ngắn (đề xuất 3 ngày), không upload DerivedData hoặc fixture không cần thiết.
- Runner tiêu chuẩn cho repo public được GitHub mô tả miễn phí; repo private và lưu trữ artifact phụ thuộc hạn mức tài khoản [S6]. Không hứa mọi cách chạy CI đều không mất phí; không bật runner trả phí hoặc bỏ hạn mức chi tiêu thay người dùng.
- Chưa có remote/repo GitHub trong thư mục hiện tại. Tạo workflow có thể thực hiện sau duyệt; chạy Actions thực sự cần repo và quyền của người dùng, không suy diễn quyền tạo/push.

## 10. TTS giai đoạn sau, không phải acceptance bản đầu

- Hướng ưu tiên: AVSpeechSynthesizer của iOS [S7], dùng giọng có sẵn trên máy, không gọi API TTS tính phí.
- Tính năng nghe cần thiết kế tiếp: nhận diện/người dùng chọn ngôn ngữ, chọn giọng thực có, tốc độ, play/pause, resume, chuyển chương; nghe nền/lock screen chỉ thêm khi đã có hành vi thực.
- Không hứa giọng tiếng Việt offline trên mọi máy iOS 15. Phải liệt kê giọng thực có, kiểm tra khi ngắt mạng và nói rõ nếu máy chưa có giọng phù hợp. Việc tải giọng hệ thống, nếu cần, là bước riêng.
- PDF có text layer có thể trích chữ; PDF scan cần OCR, nằm ngoài phạm vi hiện tại. EPUB nhiều cột/thứ tự đọc sai cần kiểm tra trên tài liệu mẫu.
- Không cài model neural, dịch vụ cloud hoặc gói TTS bên ngoài trong bản đọc sách này. Thay đổi đó cần đề xuất chi phí/dung lượng/license trước.

## 11. Nghiệm thu: bằng chứng cần có

Tất cả dưới đây là tiêu chí cần thực thi khi triển khai, KHÔNG phải kết quả đã đạt.

| ID | Kịch bản | Kết quả cần quan sát |
|---|---|---|
| A1 | Cài/mở bản build trên iPhone iOS 15 do người dùng chuẩn bị | Mở thư viện thật, không crash hoặc đòi đăng nhập; ghi rõ model/iOS phiên bản thực kiểm tra |
| A2 | Nhập EPUB tiếng Việt có dấu, bìa, 3 chương và ảnh | Metadata, nội dung, mục lục đúng; đổi cỡ chữ, chuyển chương và dấu trang thực sự hoạt động |
| A3 | Đọc giữa chương, đổi cỡ chữ, chuyển nền/khởi động lại offline | Quay về đoạn đang đọc hợp lý, không chỉ cùng số trang cũ sau khi reflow |
| A4 | Nhập PDF có text, outline và nhiều trang | Zoom, cuộn, nhảy trang, tìm chữ, dấu trang và khôi phục trang đọc hoạt động |
| A5 | Nhập PDF scan không text và PDF có mật khẩu | Scan vẫn xem/zoom, không có tìm kiếm giả; PDF khóa có thông báo rõ và không thêm sách lỗi |
| A6 | Nhập TXT tiếng Việt UTF-8 và UTF-16 BOM, file có dòng rất dài | Chữ không lỗi, cuộn/đổi chữ/tìm/dấu trang/khôi phục đúng; file legacy không giải mã được báo lỗi |
| A7 | Đổi đuôi file hỏng thành EPUB, file rỗng, DRM, quá giới hạn, zip traversal/bomb | Bị từ chối có lý do; thư viện cũ nguyên vẹn; không ghi ra ngoài staging/book scope hoặc vượt ngân sách giải nén |
| A8 | Nhập trùng file, hai file cùng tên khác nội dung, hủy nhập, thiếu dung lượng, dừng app giữa nhập | Không nhân bản trùng byte hoặc sinh mục sách rỗng; cùng tên khác nội dung không bị ghi đè; phục hồi không mất sách cũ |
| A9 | Đọc cả ba định dạng đã nhập ở chế độ máy bay | Không yêu cầu mạng; điều hướng, dấu trang và lưu trạng thái vẫn hoạt động |
| A10 | Mở EPUB reflow và fixed-layout có ảnh ngoài, stylesheet từ xa và script thử request khi mạng bật | Không có request ngoài thiết bị do nội dung sách; kiểm tra ngay lần load đầu, iframe/wrapper của fixed-layout, subresource và native loader bằng fixture + quan sát request có mục tiêu, không chỉ nhìn UI |
| A11 | Chữ giao diện lớn, VoiceOver, xoay ngang, sách thiếu bìa và thư viện không có kết quả | Nút chính vẫn truy cập được, trạng thái có nhãn, không clip hoặc báo nhầm trạng thái |
| A12 | Chạy GitHub Actions và tải artifact | Run thật có URL/evidence; IPA là device arm64, MinimumOSVersion 15.0, đủ bundle; workflow báo lỗi đúng nếu build/check hỏng |
| A13 | Xóa một sách sau xác nhận | Chỉ bản sao trong app và dữ liệu liên quan bị xóa; file nguồn và sách khác nguyên vẹn; lỗi xóa có thể retry |

### Mức bằng chứng và giới hạn môi trường

- Ở môi trường Windows hiện tại: có thể chuẩn bị spec/source/workflow và kiểm tra phần độc lập nền tảng. Không tuyên bố local Xcode build hay iOS simulator nếu không có tool/runtime thật.
- CI macOS: cần run xcodebuild thật, simulator smoke có file đại diện, kiểm tra artifact. Không dùng test chỉ kiểm tra chuỗi trong source làm bằng chứng reader hoạt động.
- iOS 15 thiết bị thật: do người dùng có máy; cung cấp checklist và build để kiểm tra, hoặc điều khiển thiết bị nếu sau này được cấp công cụ. Thiếu bằng chứng này phải ghi UNVERIFIED iOS 15 real-device, dù CI xanh.
- Có thể phát hành artifact thử nghiệm được ghi nhãn đúng trước A1, nhưng không gọi bản dùng thực tế đạt nghiệm thu cho đến khi có evidence các mục liên quan.
- Hiệu năng: chạy fixture PDF dài và EPUB lớn trong ngân sách, quan sát thao tác đọc/hủy tìm/đổi sách và memory; ghi thiết bị, kích thước, thời gian thực đo. Không bịa tốc độ mở hoặc RAM mục tiêu chưa đo.

## 12. Lựa chọn thay thế và lý do

| Lựa chọn | Đánh giá dựa trên nguồn | Quyết định đề xuất |
|---|---|---|
| Readium 3.11.1 cho EPUB | Có tài liệu mở publication, navigator, SwiftUI wrapper, locator/search và sample app; tag khai báo iOS 15; BSD-3-Clause [S1,S2,S4,S8] | BỔ SUNG vào app native mới, pin version, giữ notices |
| FolioReaderKit | Có tính năng EPUB nhưng repo đã archived, API trả về pushed_at 2020-09-22 [S9] | Không chọn làm nền tảng mới cho iOS reader |
| Tự viết EPUB bằng ZIP + WKWebView | Phải tự xử lý spine, mục lục, reflow, vị trí, accessibility, giới hạn nội dung ngoài mạng | Không chọn; không tái tạo reader engine khi có toolkit chuyên dụng |
| Quick Look cho tất cả | Không đáp ứng hợp đồng điều hướng, tùy chỉnh và vị trí theo định dạng một cách có chủ đích | Không dùng làm sản phẩm đọc chính; PDF dùng PDFKit, TXT dùng reader nhỏ native |

Không mang code sample sang mà thiếu notices. Khi resolve dependency phải rà license của graph thực tế và resource/font đi kèm, tạo thông báo third-party trong app/repo. Mẫu sách tự tạo hoặc có quyền phân phối; không đóng gói sách bản quyền cá nhân vào repo/artifact.

## 13. Nguồn sơ cấp và điều chưa được chứng minh

Nguồn được đọc phục vụ thiết kế, không thay thế compile/run:

- [S1] https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/Package.swift
- [S2] https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Guides/Open%20Publication.md và docs/Guides/Navigator/SwiftUI.md cùng tag.
- [S3] https://developer.apple.com/documentation/pdfkit/pdfview và https://developer.apple.com/documentation/pdfkit/pdfpage/string
- [S4] https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/TestApp/README.md
- [S5] https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-15-Readme.md (danh sách thay đổi theo runner; workflow phải kiểm tra trước chạy).
- [S6] https://docs.github.com/en/billing/concepts/product-billing/github-actions
- [S7] https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer và https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice
- [S8] https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/LICENSE và https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Guides/Search.md
- [S9] https://api.github.com/repos/FolioReader/FolioReaderKit (archived=true) và https://github.com/FolioReader/FolioReaderKit
- [S10] https://raw.githubusercontent.com/readium/swift-toolkit/3.11.1/docs/Migration%20Guide.md, mục 3.8.0 và 3.9.0.
- [S11] https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:)

UNVERIFIED trước triển khai: resolution graph/giấy phép bắc cầu, build thật của tổ hợp Readium 3.11.1 + Xcode được chọn, enforcement ngân sách archive và chặn request EPUB, memory trên máy iOS 15, IPA có thể chạy với phương thức cài của người dùng. Không biến các điểm này thành lời hứa đã thực hiện.

## 14. Cổng chuyển sang triển khai

- Rà độc lập về độ phủ yêu cầu và rủi ro kỹ thuật đã có kết quả trong `docs/superpowers/specs/2026-11-19-ios-reader-design-review.md`; tài liệu thiết kế đang chờ người dùng duyệt, không phải ứng dụng đã được nghiệm thu.
- Chỉ sau khi người dùng duyệt thiết kế đầy đủ mới lập kế hoạch triển khai và tạo project/source/workflow.
- Không tự commit, push, tạo GitHub repo, bật dịch vụ trả phí hoặc cài package/global tool. Những thao tác đó cần quyền tương ứng; thiết kế này không cấp quyền mặc định.
