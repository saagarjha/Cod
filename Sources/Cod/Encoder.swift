//
//  Encoder.swift
//
//
//  Created by Saagar Jha on 3/14/21.
//

import Foundation

#if canImport(Combine)
	import Combine
#endif

public class CodEncoder {
	public init() {}

	public func encode<T: Encodable>(_ value: T) throws -> Data {
		let encoder = Encoder(sharedContext: nil)
        encoder.userInfo = self.userInfo
		try value.encode(to: encoder)
		let valueData = encoder.container.combine()
		var data = Data()
		data.append(encoder.sharedContext.shapeCounter.uleb128)
		for shape in encoder.sharedContext.shapes {
			data.append(shape.count.uleb128)
			for key in shape {
				let utf8 = key.utf8
				data.append(utf8.count.uleb128)
				data.append(Data(utf8))
			}
		}
		data.append(valueData)
		return data
	}
    
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    
	fileprivate class Encoder: Swift.Encoder {
		let codingPath: [CodingKey] = []
		let topLevel: Bool
		var container: Container!
		let sharedContext: SharedContext

        var userInfo: [CodingUserInfoKey: Any] {
            get { sharedContext.userInfo }
            set { sharedContext.userInfo = newValue }
        }
        
		init(sharedContext: SharedContext?) {
			topLevel = sharedContext == nil
			self.sharedContext = sharedContext ?? SharedContext()
		}

		func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
			precondition(container == nil, "An encoder may only have one container")
			let container = KeyedContainer<Key>(sharedContext: sharedContext)
			self.container = container
			return KeyedEncodingContainer(container)
		}

		func unkeyedContainer() -> UnkeyedEncodingContainer {
			precondition(container == nil, "An encoder may only have one container")
			let container = UnkeyedContainer(sharedContext: sharedContext)
			self.container = container
			return container
		}

		func singleValueContainer() -> SingleValueEncodingContainer {
			precondition(container == nil, "An encoder may only have one container")
			let container = SingleValueContainer(topLevel: topLevel, sharedContext: sharedContext)
			self.container = container
			return container
		}
	}

	fileprivate class SingleValueContainer: Container, SingleValueEncodingContainer {
		let topLevel: Bool
		let sharedContext: SharedContext
		var value: Data??

		init(topLevel: Bool, sharedContext: SharedContext) {
			self.topLevel = topLevel
			self.sharedContext = sharedContext
		}

		func encode<T: Encodable>(_ value: T) throws {
			precondition(self.value == nil, "Single value containers may only encode once")
			self.value = try encode(value)
		}

		func encodeNil() throws {
			value = .some(nil)
		}

		func combine() -> Data {
			guard let value = value else {
				preconditionFailure("Single value container did not encode anything")
			}

			guard let value = value else {
				return Data([SingleValueContainerMetadata.null.rawValue])
			}

			return topLevel ? Data([SingleValueContainerMetadata.nonnull.rawValue]) + value : value
		}
	}

	fileprivate class UnkeyedContainer: Container, UnkeyedEncodingContainer {
		let sharedContext: SharedContext
		var values = [ContainerElement]()

		init(sharedContext: SharedContext) {
			self.sharedContext = sharedContext
		}

		var count: Int {
			values.count
		}

		func encode<T: Encodable>(_ value: T) throws {
			if let value = value as? TransparentlyEncodable {
				var `self`: UnkeyedEncodingContainer = self
				try value.transparentlyEncode(into: &`self`)
			} else if let value = value as? OptionalProtocol, value.isNil {
				try encodeNil()
			} else {
				values.append(.data(try encode(value)))
			}
		}

		func encodeNil() throws {
			values.append(.data(nil))
		}

		func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
			let container = KeyedContainer<NestedKey>(sharedContext: sharedContext)
			values.append(.container(container))
			return KeyedEncodingContainer(container)
		}

		func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
			let container = UnkeyedContainer(sharedContext: sharedContext)
			values.append(.container(container))
			return container
		}

		func superEncoder() -> Swift.Encoder {
			let encoder = Encoder(sharedContext: sharedContext)
			values.append(.encoder(encoder))
			return encoder
		}

		func combine() -> Data {
			let values = self.values.compactMap {
				$0.data
			}
			guard values.count == self.values.count else {
				var data = Data([UnkeyedContainerMetadata.nullable.rawValue])
				data.append(values.count.uleb128)
				data.append(
					contentsOf: BitVector(
						bits: self.values.map {
							$0.data == nil
						}
					).bytes)
				for value in values {
					data.append(value.count.uleb128)
				}
				for value in values {
					data.append(value)
				}
				return data
			}
			let sizes = Set(values.map(\.count))
			if sizes.count <= 1 {
				var data = Data([UnkeyedContainerMetadata.homogenouslySized.rawValue])
				data.append(values.count.uleb128)
				data.append((sizes.first ?? 0).uleb128)
				for value in values {
					data.append(value)
				}
				return data
			} else {
				var data = Data([UnkeyedContainerMetadata.hetrogenous.rawValue])
				data.append(values.count.uleb128)
				for value in values {
					data.append(value.count.uleb128)
				}
				for value in values {
					data.append(value)
				}
				return data
			}
		}
	}

	fileprivate class KeyedContainer<Key: CodingKey>: Container, KeyedEncodingContainerProtocol {
		let sharedContext: SharedContext
		var values = [String: ContainerElement]()

		init(sharedContext: SharedContext) {
			self.sharedContext = sharedContext
		}

		@inlinable
		func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
			precondition(values[key.stringValue] == nil, "Can only encode a key once")
			if let value = value as? TransparentlyEncodable {
				var `self` = self
				try value.transparentlyEncode(into: &`self`, forKey: key)
			} else if let value = value as? OptionalProtocol, value.isNil {
				try encodeNil(forKey: key)
			} else {
				values[key.stringValue] = .data(try encode(value))
			}
		}

		func encodeNil(forKey key: Key) throws {
			precondition(values[key.stringValue] == nil, "Can only encode a key once")
			values[key.stringValue] = .data(nil)
		}

		func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
			let container = KeyedContainer<NestedKey>(sharedContext: sharedContext)
			values[key.stringValue] = .container(container)
			return KeyedEncodingContainer(container)
		}

		func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
			let container = UnkeyedContainer(sharedContext: sharedContext)
			values[key.stringValue] = .container(container)
			return container
		}

		func superEncoder() -> Swift.Encoder {
			return superEncoder(forKey: Key(stringValue: "super")!)
		}

		func superEncoder(forKey key: Key) -> Swift.Encoder {
			let encoder = Encoder(sharedContext: sharedContext)
			values[key.stringValue] = .encoder(encoder)
			return encoder
		}

		func combine() -> Data {
			let sortedKeys = values.keys.sorted()
			let id = sharedContext.lookupID(forShape: sortedKeys)
			var values = [Data]()
			for key in sortedKeys {
				let value = self.values[key]!
				if let value = value.data {
					values.append(value)
				}
			}

			guard values.count == self.values.count else {
				var data = Data([KeyedContainerMetadata.nullable.rawValue])
				data.append(id.uleb128)
				data.append(
					contentsOf: BitVector(
						bits: sortedKeys.map {
							self.values[$0]!.data == nil
						}
					).bytes)
				for value in values {
					data.append(value.count.uleb128)
				}
				for value in values {
					data.append(value)
				}
				return data
			}

			var data = Data([KeyedContainerMetadata.nonnull.rawValue])
			data.append(id.uleb128)
			for value in values {
				data.append(value.count.uleb128)
			}
			for value in values {
				data.append(value)
			}
			return data
		}
	}

	class SharedContext {
		var shapeCounter = 0
		var shapes = [[String]]()
		var shapeIDs = [[String]: Int]()
        var userInfo: [CodingUserInfoKey: Any] = [:]
        
		func lookupID(forShape shape: [String]) -> Int {
			guard let id = shapeIDs[shape] else {
				defer {
					shapeCounter += 1
				}
				shapes.append(shape)
				shapeIDs[shape] = shapeCounter
				return shapeCounter
			}
			return id
		}

		/*func combined() -> Data {
			guard keys.isEmpty else {
				var data = keys.count.uleb128
				for key in keys.map(\.1).map(\.uleb128) {
					data.append(key)
				}
				for string in keys.map(\.0) {
					data.append(string.data(using: .utf8)! + [0])
				}
				data.append(self.data)
				return data
//				return Data(bytesOf: keys.count) +
//					keys.map(\.1).map(Int.bytes).reduce(Data(), +) +
//					keys.map(\.0).map {
//						$0.data(using: .utf8)! + [0]
//					}.reduce(Data(), +) +
//					data
			}

			guard indices.isEmpty else {
				if isHomogeneouslySizedTriviallyCopyable {
					var data = Data([0])
					data.append(indices.count.uleb128)
					data.append((size ?? 0).uleb128)
					data.append(self.data)
					return data
				} else {
					var data = Data([1])
					data.append(indices.count.uleb128)
					for index in indices.map(\.uleb128) {
						data.append(index)
					}
					data.append(self.data)
					return data
				}
			}

			return data
		}*/
	}

	fileprivate enum ContainerElement {
		case data(Data?)
		case container(Container)
		case encoder(Encoder)

		var data: Data? {
			switch self {
				case .data(let data):
					return data
				case .container(let container):
					return container.combine()
				case .encoder(let encoder):
					return encoder.container.combine()
			}
		}
	}
}

#if canImport(Combine)
	extension CodEncoder: TopLevelEncoder {}
#endif

private protocol Container {
	var sharedContext: CodEncoder.SharedContext { get }

	func combine() -> Data
}

extension Container {
	var codingPath: [CodingKey] {
		[]
	}

	func encode<T: Encodable>(_ value: T) throws -> Data {
		switch value {
			case let value as TriviallyCopyable:
				return value.bytes
			case let value as String:
				let utf8 = value.utf8
				return utf8.count.uleb128 + Data(utf8)
			default:
				let encoder = CodEncoder.Encoder(sharedContext: sharedContext)
				try value.encode(to: encoder)
				return encoder.container.combine()
		}
	}
}
