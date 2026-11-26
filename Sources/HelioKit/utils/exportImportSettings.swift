import Foundation

func exportUserDefaultsToJSON(fileName: String) -> String? {
  let userDefaults = UserDefaults.standard
  let userDefaultsDictionary = userDefaults.dictionaryRepresentation()

  var serializedDictionary: [String: Any] = [:]

  for (key, value) in userDefaultsDictionary {
    if let date = value as? Date {
      serializedDictionary[key] = date.iso8601String
    } else {
      serializedDictionary[key] = value
    }
  }

  do {
    let jsonData = try JSONSerialization.data(withJSONObject: serializedDictionary, options: .prettyPrinted)

    if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      let fileURL = documentsDirectory.appendingPathComponent(fileName)

      try jsonData.write(to: fileURL)

      print("UserDefaults exported to: \(fileURL.absoluteString)")
      return fileURL.absoluteString
    }
  } catch {
    print("Error exporting UserDefaults to JSON: \(error)")
  }

  return nil
}

func importUserDefaultsFromJSON(jsonFilePath: URL) -> Bool {
  let gotAccess = jsonFilePath.startAccessingSecurityScopedResource()
  if !gotAccess {
    print("Can't get file access")
    return false
  }
  do {
    let jsonData = try Data(contentsOf: jsonFilePath)

    if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
      for (key, value) in jsonObject {
        if let dateStr = value as? String,
           let date = Date.dateFromISO8601String(dateStr)
        {
          UserDefaults.standard.set(date, forKey: key)
        } else {
          UserDefaults.standard.set(value, forKey: key)
        }
      }

      UserDefaults.standard.synchronize()

      print("UserDefaults imported from: \(jsonFilePath)")
      jsonFilePath.stopAccessingSecurityScopedResource()
      return true
    }
  } catch {
    print("Error importing UserDefaults from JSON: \(error)")
    jsonFilePath.stopAccessingSecurityScopedResource()
  }
  return false
}

extension Date {
  var iso8601String: String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: self)
  }
}

extension Date {
  static func dateFromISO8601String(_ iso8601String: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso8601String)
  }
}
