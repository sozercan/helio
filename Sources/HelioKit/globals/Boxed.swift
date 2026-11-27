@propertyWrapper
struct Boxed<Value> {
  private final class Box {
    var value: Value

    init(_ value: Value) {
      self.value = value
    }
  }

  private var box: Box

  init(wrappedValue: Value) {
    box = Box(wrappedValue)
  }

  var wrappedValue: Value {
    get { box.value }
    set {
      if isKnownUniquelyReferenced(&box) {
        box.value = newValue
      } else {
        box = Box(newValue)
      }
    }
  }
}

extension Boxed: Equatable where Value: Equatable {
  static func == (lhs: Boxed, rhs: Boxed) -> Bool {
    lhs.box === rhs.box || lhs.wrappedValue == rhs.wrappedValue
  }
}

extension Boxed: Hashable where Value: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(wrappedValue)
  }
}

extension Boxed: Codable where Value: Codable {
  init(from decoder: Decoder) throws {
    try self.init(wrappedValue: decoder.singleValueContainer().decode(Value.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(wrappedValue)
  }
}
