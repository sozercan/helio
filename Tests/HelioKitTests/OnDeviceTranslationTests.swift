import Foundation
import Testing
@testable import HelioKit

struct OnDeviceTranslationTests {
  @Test func canonicalizesLanguageCodesWithoutRegion() {
    #expect(OnDeviceTranslation.canonicalLanguageCode("en-US") == "en")
    #expect(OnDeviceTranslation.canonicalLanguageCode("pt_BR") == "pt")
    #expect(OnDeviceTranslation.canonicalLanguageCode("FR") == "fr")
    #expect(OnDeviceTranslation.canonicalLanguageCode("  ").isEmpty)
  }

  @Test func detectsLanguageForNonEmptyNaturalText() {
    #expect(OnDeviceTranslation.detectLanguageCode(for: "Bonjour tout le monde, comment allez-vous aujourd'hui?") == "fr")
    #expect(OnDeviceTranslation.detectLanguageCode(for: "   ") == nil)
  }

  @Test func targetLanguageFallsBackToEnglishWhenPreferredEmpty() {
    #expect(OnDeviceTranslation.targetLanguageCode(preferredLanguages: ["es-ES", "en-US"]) == "es")
    #expect(OnDeviceTranslation.targetLanguageCode(preferredLanguages: []) == "en")
  }

  @Test func postTranslationTextCombinesTitleAndSelftext() {
    #expect(OnDeviceTranslation.postTranslationText(title: "Title", selftext: nil) == "Title")
    #expect(OnDeviceTranslation.postTranslationText(title: "Title", selftext: "   ") == "Title")
    #expect(OnDeviceTranslation.postTranslationText(title: "Title", selftext: "Body text") == "Title\n\nBody text")
  }
}
