import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Zip

func saveImage(image: UIImage) -> String? {
  guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }

  let id = UUID().uuidString
  var data: Data?
  var ext: String?
  if let newData = image.jpegData(compressionQuality: 1) {
    data = newData
    ext = "jpg"
  }
  if let newData = image.pngData() {
    data = newData
    ext = "png"
  }
  guard let data, let ext else { return nil }

  let fileURL = documentsDirectory.appendingPathComponent("\(id).\(ext)")

  if FileManager.default.fileExists(atPath: fileURL.path) {
    do {
      try FileManager.default.removeItem(atPath: fileURL.path)
    } catch let removeError {
      print("couldn't remove file at path", removeError)
    }
  }

  do {
    try data.write(to: fileURL)
    return "\(id).\(ext)"
  } catch {
    print("error saving file with error", error)
    return nil
  }
}

func loadImage(fileName: String) -> UIImage? {
  let documentDirectory = FileManager.SearchPathDirectory.documentDirectory

  let userDomainMask = FileManager.SearchPathDomainMask.userDomainMask
  let paths = NSSearchPathForDirectoriesInDomains(documentDirectory, userDomainMask, true)

  if let dirPath = paths.first {
    let imageUrl = URL(fileURLWithPath: dirPath).appendingPathComponent(fileName)
    return UIImage(contentsOfFile: imageUrl.path)
  }

  return nil
}

func createZip(images: [String], theme: HelioTheme) throws -> URL {
  let fileManager = FileManager.default
  let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)

  guard let documentDirectory: URL = urls.first else { throw NSError(domain: "Document directory not found", code: 1, userInfo: nil) }

  let imgURLs = images.filter { $0 != "helioNoBG" }.map { documentDirectory.appendingPathComponent($0) }

  let jsonURL = documentDirectory.appendingPathComponent("theme.json")
  let jsonData = try JSONEncoder().encode(theme)
  try jsonData.write(to: jsonURL)

  let zipName = UUID().uuidString
  let zipURL = documentDirectory.appendingPathComponent("\(zipName).zip")

  if fileManager.fileExists(atPath: zipURL.path()) {
    try fileManager.removeItem(at: zipURL)
  }

  try Zip.zipFiles(paths: imgURLs + [jsonURL], zipFilePath: zipURL, password: nil, progress: nil)

  let helioFileName = "\(theme.metadata.name)-Theme"
  let helioFileNameURL = documentDirectory.appendingPathComponent("\(helioFileName).helio")

  if fileManager.fileExists(atPath: helioFileNameURL.path()) {
    try fileManager.removeItem(at: helioFileNameURL)
  }

  try fileManager.moveItem(at: zipURL, to: helioFileNameURL)

  return helioFileNameURL
}
