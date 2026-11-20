import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("reader.colorScheme") private var colorMode = "system"
    @AppStorage("reader.textSize") private var storedTextSize = 18.0
    @AppStorage("reader.textBackground") private var storedTextBackground = "paper"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Giao diện ứng dụng")) {
                    Picker("Màu sắc", selection: $colorMode) {
                        Text("Theo hệ thống").tag("system")
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                    }
                    .onChange(of: colorMode) { value in
                        applyColorMode(value)
                        UserDefaults.standard.set(value, forKey: "reader.colorScheme")
                    }
                }
                Section(header: Text("Văn bản TXT")) {
                    Picker("Nền đọc", selection: $storedTextBackground) {
                        Text("Giấy").tag("paper")
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                    }
                    .onChange(of: storedTextBackground) { value in
                        model.textBackgroundName = value
                        UserDefaults.standard.set(value, forKey: "reader.textBackground")
                    }
                    HStack {
                        Text("Cỡ chữ mặc định")
                        Slider(value: $storedTextSize, in: 14...30, step: 1).accessibilityLabel("Cỡ chữ mặc định")
                        Text("\(Int(storedTextSize))").monospacedDigit().accessibilityValue("\(Int(storedTextSize)) điểm")
                    }
                }
                Section(header: Text("Định dạng và giới hạn")) {
                    Text("PDF: hiển thị và tìm chữ khi tài liệu có lớp văn bản; tệp scan vẫn xem được, không có OCR.")
                    Text("EPUB 2/3: bộ nhập xác thực sách cục bộ không DRM; ngoại tuyến/chặn yêu cầu tài nguyên chưa được xác minh trong bản này.")
                    Text("TXT: UTF-8, UTF-8 BOM và UTF-16 BOM.")
                }
                Section(header: Text("Ngoài phạm vi")) {
                    Text("TTS, OCR, DRM và đồng bộ chưa có trong bản này.")
                }
                Section(header: Text("Giấy phép")) {
                    NavigationLink("Thông báo thư viện bên thứ ba") { ThirdPartyNoticesView() }
                }
                Section(header: Text("Phiên bản")) { Text("BookReader · iOS 15 trở lên") }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            model.textSize = storedTextSize
            model.textBackgroundName = storedTextBackground
            applyColorMode(colorMode)
        }
        .onChange(of: storedTextSize) {
            model.textSize = $0
            UserDefaults.standard.set($0, forKey: "reader.textSize")
        }
    }

    private func applyColorMode(_ mode: String) {
        switch mode {
        case "light": model.colorScheme = .light
        case "dark": model.colorScheme = .dark
        default: model.colorScheme = nil
        }
    }
}
