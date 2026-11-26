import Combine
import Foundation

extension Published: Decodable where Value: Decodable {
  public init(from decoder: Decoder) throws {
    try self.init(wrappedValue: .init(from: decoder))
  }
}

extension Published: Encodable where Value: Encodable {
  public func encode(to encoder: Encoder) throws {
    try unofficialValue.encode(to: encoder)
  }
}
