import MarkdownUI
import SwiftUI

struct SelectableTextSheet: View {
  let markdown: String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        Markdown(MarkdownUtil.formatForMarkdown(markdown, showSpoiler: true))
          .markdownTheme(.helioMarkdown(fontSize: 17, lineSpacing: 3, textSelection: true))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .navigationTitle("Select Text")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            UIPasteboard.general.string = markdown
            dismiss()
          } label: {
            Label("Copy All", systemImage: "doc.on.doc")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
