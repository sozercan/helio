import Foundation
import NaturalLanguage
import SwiftUI
#if canImport(Translation)
  import Translation
#endif

enum OnDeviceTranslation {
  static func detectLanguageCode(for text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(trimmed)
    guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
      return nil
    }
    return canonicalLanguageCode(dominant.rawValue)
  }

  static func canonicalLanguageCode(_ raw: String) -> String {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }
    let components = Locale.Language.Components(identifier: normalized)
    guard let language = components.languageCode?.identifier.lowercased(), !language.isEmpty else {
      return ""
    }
    if let script = components.script?.identifier, !script.isEmpty {
      return "\(language)-\(script)"
    }
    return language
  }

  static func makeLanguage(_ code: String) -> Locale.Language {
    let canonical = canonicalLanguageCode(code)
    let components = Locale.Language.Components(identifier: canonical)
    if let languageCode = components.languageCode {
      return Locale.Language(languageCode: languageCode, script: components.script, region: nil)
    }
    return Locale.Language(identifier: canonical)
  }

  static func targetLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
    for lang in preferredLanguages {
      let code = canonicalLanguageCode(lang)
      if !code.isEmpty {
        return code
      }
    }
    return "en"
  }

  static func postTranslationText(title: String, selftext: String?) -> String {
    let trimmedBody = selftext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmedBody.isEmpty {
      return title
    }
    return "\(title)\n\n\(trimmedBody)"
  }
}

struct TranslationSheet: View {
  let sourceText: String
  @Environment(\.dismiss) private var dismiss
  @State private var translatedText: String?
  @State private var errorMessage: String?
  @State private var isTranslating = false
  @State private var detectedCode: String?
  #if canImport(Translation)
    @State private var configuration: TranslationSession.Configuration?
  #endif

  private var targetCode: String {
    OnDeviceTranslation.targetLanguageCode()
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let detectedCode {
            let sourceName = Locale.current.localizedString(forLanguageCode: detectedCode) ?? detectedCode
            let targetName = Locale.current.localizedString(forLanguageCode: targetCode) ?? targetCode
            Text("\(sourceName) → \(targetName)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if isTranslating {
            HStack(spacing: 8) {
              ProgressView()
              Text("Translating on device…")
                .foregroundStyle(.secondary)
            }
          } else if let translatedText {
            Text(translatedText)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else if let errorMessage {
            Text(errorMessage)
              .foregroundStyle(.secondary)
          }

          Divider()

          VStack(alignment: .leading, spacing: 6) {
            Text("Original")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(sourceText)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding()
      }
      .navigationTitle("Translate")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        if let translatedText {
          ToolbarItem(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") {
              UIPasteboard.general.string = translatedText
            }
          }
        }
      }
      .task(id: sourceText) {
        prepareTranslation()
      }
      #if canImport(Translation)
      .translationTask(configuration) { session in
        await runTranslation(using: session)
      }
      #endif
    }
  }

  private func prepareTranslation() {
    translatedText = nil
    errorMessage = nil
    let detected = OnDeviceTranslation.detectLanguageCode(for: sourceText)
    detectedCode = detected

    guard let detected else {
      errorMessage = "Could not detect the source language for on-device translation."
      return
    }
    if detected == targetCode {
      translatedText = sourceText
      return
    }

    #if canImport(Translation)
      isTranslating = true
      configuration = TranslationSession.Configuration(
        source: OnDeviceTranslation.makeLanguage(detected),
        target: OnDeviceTranslation.makeLanguage(targetCode),
      )
    #else
      errorMessage = "On-device translation is unavailable on this platform."
    #endif
  }

  #if canImport(Translation)
    private func runTranslation(using session: TranslationSession) async {
      defer { isTranslating = false }
      do {
        try await session.prepareTranslation()
        let response = try await session.translate(sourceText)
        translatedText = response.targetText
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  #endif
}
