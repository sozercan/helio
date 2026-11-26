import Foundation
import WhatsNewKit

func getCurrentChangelog() -> WhatsNewCollection {
  let filePath = Bundle.main.path(forResource: "changelog", ofType: "json") ?? ""

  guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return [] }

  let decoder = JSONDecoder()

  do {
    let changelog = try decoder.decode(WhatsNewRelease.self, from: jsonData)

    let version = changelog.version
    let title = changelog.title
    let features = changelog.features

    var newCollection: WhatsNewCollection = []

    var featureArray: [WhatsNew.Feature] = []

    if let features {
      for feature in features {
        let systemImage = feature.systemImage
        let featureTitle = feature.title
        let featureSubtitle = feature.subtitle

        let newFeature = WhatsNew.Feature(
          image: .init(systemName: systemImage),
          title: WhatsNew.Text(stringLiteral: featureTitle),
          subtitle: WhatsNew.Text(stringLiteral: featureSubtitle),
        )

        featureArray.append(newFeature)
      }
    }

    let newWhatsNew = WhatsNew(
      version: WhatsNew.Version(stringLiteral: version ?? "0.0.0"),
      title: WhatsNew.Title(stringLiteral: title ?? ""),
      features: featureArray,
      primaryAction: getDefaultPrimaryAction(),
      secondaryAction: getDefaultSecondaryAction(),
    )

    newCollection.append(newWhatsNew)

    return newCollection

  } catch {
    print(error)
  }

  return []
}

func getDefaultPrimaryAction() -> WhatsNew.PrimaryAction {
  WhatsNew.PrimaryAction(
    title: "Continue",
    backgroundColor: .accentColor,
    foregroundColor: .white,
    hapticFeedback: .notification(.success),
    onDismiss: {},
  )
}

func getDefaultSecondaryAction() -> WhatsNew.SecondaryAction {
  WhatsNew.SecondaryAction(
    title: "Learn more",
    foregroundColor: .accentColor,
    hapticFeedback: .selection,
    action: .openURL(
      .init(string: "https://github.com/sozercan/helio"),
    ),
  )
}

struct WhatsNewRelease: Decodable {
  let title: String?
  let version: String?
  let features: [WhatsNewFeatureDetail]?
}

struct WhatsNewFeatureDetail: Decodable {
  let subtitle: String
  let systemImage: String
  let title: String
}
