# Rà thiết kế ứng dụng đọc sách iOS 15

Đối tượng: `docs/superpowers/specs/2026-11-19-ios-reader-design.md`.
Trạng thái: đủ rõ để người dùng duyệt thiết kế và sau đó lập kế hoạch; không phải nghiệm thu ứng dụng hoặc xác nhận build.

## Bằng chứng và phạm vi

- Reviewer `DesignBuildability`: đọc độc lập phần yêu cầu/khả năng lập kế hoạch, trả về `nothing important left`. Không có câu hỏi sản phẩm trọng yếu buộc phải hỏi thêm trước lập kế hoạch; không chạy build/test và không sửa file.
- Reviewer `DesignSafetyCI`: đọc độc lập phần an toàn/CI/khả thi, không nêu lỗi trọng yếu chưa được chặn trong bản thiết kế đã cập nhật. Các điều kiện archive/network/runtime vẫn là UNVERIFIED. Không chạy build/test/simulator/device hoặc sửa file.
- Tác giả đọc lại tài liệu trên đĩa và đối chiếu kết quả reviewer; xác nhận các giới hạn và cổng phê duyệt ở mục 11, 13, 14 không bị biến thành tuyên bố sản phẩm hoạt động.

## Độ phủ thiết kế

| Ranh giới | Chỗ quy định | Kết luận ở mức tài liệu |
|---|---|---|
| iOS 15 và chứng cứ thiết bị | Mục 6; A1; mục 11 | Khai báo deployment target không được dùng thay bằng chứng chạy máy thật |
| GitHub Actions device IPA | Mục 9; A12 | Phân biệt unsigned device artifact, simulator, ký/cài do người dùng lo |
| Reader local PDF/EPUB/TXT | Mục 3-5; A2-A9 | Luồng nhập/đọc/lưu vị trí và định dạng không hỗ trợ được nêu rõ |
| UI và trạng thái lỗi | Mục 5, 8; A7-A11 | Empty/loading/error, Dynamic Type, VoiceOver, rotation là acceptance thực tế |
| Dữ liệu và phục hồi | Mục 7; A8/A13 | Staging/catalog không transaction chung, rollback cục bộ, không reset thư viện khi lỗi |
| TTS miễn phí/offline về sau | Mục 3, 10 | Không thuộc bản đầu, không nút giả hoặc lời hứa mọi máy có voice Việt |
| Chi phí/license | Mục 9, 12 | Không hứa CI/storage miễn phí vô hạn; graph và notices cần rà sau resolve |

## Điều chỉnh từ rà kỹ thuật

1. Dùng migration guide cùng tag để bỏ khả năng kéo local HTTP server cũ vào thiết kế: Readium EPUB đã dùng custom scheme từ 3.8; 3.9 bỏ nốt server ở PDF navigator. App dùng PDFKit nên không có nhu cầu GCDWebServer.
2. Chính sách EPUB phải áp dụng trước load đầu và bao quát native-resource request, không chỉ navigation delegate. WebKit content-rule API có tài liệu, nhưng việc nó gắn vào mọi web view của Readium và thật sự chặn mọi đường mạng vẫn cần spike.
3. Reviewer kỹ thuật nêu `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)` là hook khả dĩ và cảnh báo fixed-layout có wrapper load sớm. Đây là phát hiện source-level của reviewer, không phải bằng chứng enforcement. A10 được làm rõ để bắt buộc kiểm tra cả reflow/fixed-layout, lần load đầu, wrapper/iframe và native loader.

## Các cổng chưa có bằng chứng thực thi

- Resolve graph/giấy phép bắc cầu và build đúng Readium 3.11.1 + Xcode đã chọn.
- Giới hạn ZIP thực đọc/giải nén, bảo vệ đường dẫn và từ chối archive xấu trước parse tài nguyên.
- Không request ngoài thiết bị từ EPUB khi có mạng, bao gồm fixed-layout/wrapper.
- Mở sách, tìm, lưu/khôi phục, memory, accessibility trên runtime thực.
- Workflow GitHub Actions run thật, kiểm tra IPA và iPhone iOS 15 của người dùng.

Không có điểm nào ở trên được gán PASS runtime. Không chạy lệnh không liên quan để tạo bằng chứng hình thức.

## Kiểm tra cấu trúc hồ sơ

Một cell kiểm tra tài liệu xác nhận 14 mục đánh số, A1-A13 liên tục, nguồn tham chiếu được định nghĩa, không placeholder TODO/TBD/lorem ipsum. Cell đầu dừng tại giả định thư mục chỉ có Markdown vì phát hiện `.ai/STATE/journal.jsonl`; đọc mục tiêu cho thấy journal ghi thao tác edit tài liệu. Không xóa/chỉnh journal. Cell phạm vi tiếp theo phân biệt journal với ba hồ sơ Markdown có chủ ý và không phát hiện source/project/workflow.

Kiểm tra này chỉ chứng minh cấu trúc và phạm vi tài liệu. Nó không chứng minh API, build, bảo mật hoặc reader hoạt động. Phiên bản tài liệu cuối chỉ thêm rõ kiểm tra fixed-layout và đường dẫn báo cáo; lệnh cấu trúc cuối sẽ kiểm tra chính phiên bản bàn giao.

## Quyền và bàn giao

Chỉ tạo hồ sơ nghiên cứu, thiết kế và báo cáo rà; không tạo app, cài dependency, commit, push, remote repository hoặc bật runner trả phí. Chờ duyệt thiết kế đầy đủ trước lập kế hoạch triển khai.
