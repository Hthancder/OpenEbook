import SwiftUI
import UIKit

struct BookCardView: View {
    let book: BookRecord
    let coverImage: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14))
                    if let coverImage {
                        Image(uiImage: coverImage).resizable().scaledToFill().frame(width: 52, height: 68).clipped()
                    } else {
                        Image(systemName: iconName).font(.title2).foregroundColor(.accentColor)
                    }
                }
                .frame(width: 52, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title).font(.headline).foregroundColor(.primary).lineLimit(2)
                    if let author = book.author { Text(author).font(.subheadline).foregroundColor(.secondary).lineLimit(1) }
                    Text(book.format.displayName).font(.caption).foregroundColor(.secondary)
                    ProgressView(value: progress)
                        .accessibilityLabel("Tiến độ đọc")
                        .accessibilityValue("\(Int(progress * 100)) phần trăm")
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mở \(book.title)")
        .accessibilityHint("Mở sách để đọc")
    }

    private var progress: Double { book.progress.isFinite ? min(max(book.progress, 0), 1) : 0 }
    private var iconName: String { book.format == .pdf ? "doc.richtext" : book.format == .epub ? "book.closed" : "doc.plaintext" }
}
