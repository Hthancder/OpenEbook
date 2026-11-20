import SwiftUI

struct ThirdPartyNoticesView: View {
    private let notices: String = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "Thông báo giấy phép không khả dụng."
        }
        return contents
    }()

    var body: some View {
        ScrollView {
            Text(notices)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Giấy phép")
        .navigationBarTitleDisplayMode(.inline)
    }
}
