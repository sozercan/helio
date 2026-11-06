/// Keeps a large value in a box that copies share until one of them changes it, as an array does,
/// so the struct holding it stays small. Theme parts and swipe actions are hundreds of bytes each,
/// and the views that hold them were as big: unoptimized code copies views on the stack many
/// times as SwiftUI updates them, which deep in a layout, as after rotating, ran Debug builds out
/// of main-thread stack. Encodes as the value itself, but synthesized coding writes a boxed nil as
/// null and needs its key, so box an optional only in a type that codes itself.
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
