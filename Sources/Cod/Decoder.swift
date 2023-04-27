//
//  Decoder.swift
//
//
//  Created by Saagar Jha on 3/14/21.
//

import Foundation

#if canImport(Combine)
	import Combine
#endif

public class CodDecoder {
	public init() {}

	public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
		let decoder = try Decoder(sharedContext: nil, data: data)
        decoder.userInfo = self.userInfo
		return try T(from: decoder)
	}

    public var userInfo: [CodingUserInfoKey : Any] = [:]
    
	fileprivate class Decoder: Swift.Decoder {
		let codingPath: [CodingKey] = []
		let topLevel: Bool
		let sharedContext: SharedContext
		let data: Data

        var userInfo: [CodingUserInfoKey: Any] {
            get { sharedContext.userInfo }
            set { sharedContext.userInfo = newValue }
        }
        
		init(sharedContext: SharedContext?, data: Data) throws {
			topLevel = sharedContext == nil
			if let sharedContext = sharedContext {
				self.sharedContext = sharedContext
				self.data = data
			} else {
				var data = data
				let shapeCount = try Int(uleb128: &data)
				var shapes = [Int: [String]]()
				for i in 0..<shapeCount {
					let keyCount = try Int(uleb128: &data)
					let shape: [String] = try (0..<keyCount).map { _ in
						let count = try Int(uleb128: &data)
						let slice = try data.slice(toOffset: count)
						defer {
							data = data[slice.endIndex...]
						}
						return try evaluate(String(data: slice, encoding: .utf8), CodError.invalidUTF8(data.startIndex))
					}
					guard Set(shape).count == shape.count else {
						throw CodError.duplicateKeys
					}
					shapes[i] = shape
				}
				self.sharedContext = SharedContext(shapes: shapes)
				self.data = data
			}
		}

		func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
			KeyedDecodingContainer(try KeyedContainer(sharedContext: sharedContext, data: data))
		}

		func unkeyedContainer() throws -> UnkeyedDecodingContainer {
			try UnkeyedContainer(sharedContext: sharedContext, data: data)
		}

		func singleValueContainer() throws -> SingleValueDecodingContainer {
			return SingleValueContainer(topLevel: topLevel, sharedContext: sharedContext, data: data)
		}
	}

	fileprivate struct SingleValueContainer: DecodingContainer, SingleValueDecodingContainer {
		let topLevel: Bool
		var sharedContext: SharedContext
		let data: Data

		func decodeNil() -> Bool {
			// This really sucks, but alas, this method cannot throw or mutate state.
			topLevel && (try? Bool(bytes: data)) ?? true
		}

		func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
			try decode(type, from: topLevel ? data.slice(fromOffset: MemoryLayout<Bool>.size) : data)
		}
	}

	fileprivate struct UnkeyedContainer: DecodingContainer, UnkeyedDecodingContainer {
		let sharedContext: SharedContext
		let data: Data

		let indexCount: Int
		enum Indices {
			case homogenouslySized(Int)
			case hetrogenous([Data.Index])
			case nullable([Data.Index?])
		}
		let indices: Indices

		init(sharedContext: SharedContext, data: Data) throws {
			self.sharedContext = sharedContext
			var data = data
			let type = try evaluate(UnkeyedContainerMetadata(rawValue: UnkeyedContainerMetadata.RawValue(bytes: &data)), CodError.invalidMetadata(data.startIndex))
			indexCount = try Int(uleb128: &data)
			switch type {
				case .homogenouslySized:
					indices = .homogenouslySized(try Int(uleb128: &data))
					self.data = data
				case .hetrogenous:
					var offset = 0
					indices = .hetrogenous(
						try (0..<indexCount).map { _ in
							let size = try Data.Index(uleb128: &data)
							defer {
								offset += size
							}
							return offset
						})
					self.data = data
				case .nullable:
					guard data.count * 8 >= indexCount else {
						throw CodError.truncated
					}
					let optionals = BitVector(bytes: data, count: indexCount)
					data = data[data.index(data.startIndex, offsetBy: optionals.bytes.count)...]
					var offset = 0
					indices = .nullable(
						try optionals.map { optional in
							let size = optional ? 0 : try Data.Index(uleb128: &data)
							defer {
								offset += size
							}
							return optional ? nil : offset
						})
					self.data = data
			}
		}

		var count: Int? {
			indexCount
		}

		var isAtEnd: Bool {
			currentIndex == indexCount
		}

		var currentIndex: Int = 0

		mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
			if let type = type as? TransparentlyDecodable.Type {
				var `self`: UnkeyedDecodingContainer = self
				return try type.init(from: &`self`) as! T
			}

			defer {
				currentIndex += 1
			}

			switch indices {
				case .homogenouslySized(let size):
					return try decode(T.self, from: data.slice(fromOffset: currentIndex * size, toOffset: (currentIndex + 1) * size))
				case .hetrogenous(let indices):
					return try decode(T.self, from: data.slice(fromOffset: indices[currentIndex], toOffset: currentIndex < indices.index(before: indices.endIndex) ? indices[currentIndex + 1] : nil))
				case .nullable(let indices):
					if let index = indices[currentIndex] {
						return try decode(T.self, from: data.slice(fromOffset: index))
					} else if let type = type as? OptionalProtocol.Type {
						return type.nil as! T
					} else {
						throw CodError.invalidOptional
					}
			}
		}

		mutating func decodeNil() throws -> Bool {
			switch indices {
				case .nullable(let indices):
					defer {
						currentIndex += 1
					}
					return indices[currentIndex] == nil
				default:
					return false
			}
		}

		mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
			try KeyedDecodingContainer(KeyedContainer<NestedKey>(sharedContext: sharedContext, data: nestedDataForCurrentIndex()))
		}

		mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
			try UnkeyedContainer(sharedContext: sharedContext, data: nestedDataForCurrentIndex())
		}

		mutating func superDecoder() throws -> Swift.Decoder {
			try Decoder(sharedContext: sharedContext, data: nestedDataForCurrentIndex())
		}

		func nestedDataForCurrentIndex() throws -> Data {
			switch indices {
				case .homogenouslySized(let size):
					return try data.slice(fromOffset: currentIndex * size, toOffset: (currentIndex + 1) * size)
				case .hetrogenous(let indices):
					return try data.slice(fromOffset: indices[currentIndex], toOffset: currentIndex < indices.index(before: indices.endIndex) ? indices[currentIndex + 1] : nil)
				case .nullable(let indices):
					guard let index = indices[currentIndex] else {
						throw CodError.invalidOptional
					}
					return try data.slice(fromOffset: index)

			}
		}
	}

	fileprivate struct KeyedContainer<Key: CodingKey>: DecodingContainer, KeyedDecodingContainerProtocol {
		let sharedContext: SharedContext
		let data: Data

		enum Keys {
			case nonnull([String: Data.Index])
			case nullable([String: Data.Index?])
		}
		let keys: Keys

		init(sharedContext: SharedContext, data: Data) throws {
			self.sharedContext = sharedContext
			var data = data
			let type = try evaluate(KeyedContainerMetadata(rawValue: try KeyedContainerMetadata.RawValue(bytes: &data)), CodError.invalidMetadata(data.startIndex))
			let shape = try evaluate(sharedContext.shapes[try Int(uleb128: &data)], CodError.invalidShapeID(data.startIndex))
			switch type {
				case .nonnull:
					var keys = [String: Data.Index]()
					var offset = 0
					for key in shape {
						keys[key] = offset
						offset += try Data.Index(uleb128: &data)
					}
					self.keys = .nonnull(keys)
				case .nullable:
					guard data.count * 8 >= shape.count else {
						throw CodError.truncated
					}
					let optionals = BitVector(bytes: data, count: shape.count)
					data = data[data.index(data.startIndex, offsetBy: optionals.bytes.count)...]
					var keys = [String: Data.Index?]()
					var offset = 0
					for (key, optional) in zip(shape, optionals) {
						if optional {
							keys[key] = .some(nil)
						} else {
							keys[key] = offset
							offset += try Data.Index(uleb128: &data)
						}
					}
					self.keys = .nullable(keys)
			}
			self.data = data
		}

		var allKeys: [Key] {
			switch keys {
				case .nonnull(let keys):
					return keys.keys.compactMap(Key.init)
				case .nullable(let keys):
					return keys.keys.compactMap(Key.init)
			}
		}

		func contains(_ key: Key) -> Bool {
			switch keys {
				case .nonnull(let keys):
					return keys[key.stringValue] != nil
				case .nullable(let keys):
					return keys[key.stringValue] != nil
			}
		}

		@inlinable
		func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
			if let type = type as? TransparentlyDecodable.Type {
				return try type.init(from: self, forKey: key) as! T
			}

			switch keys {
				case .nonnull(let keys):
					return try decode(type, from: data.slice(fromOffset: evaluate(keys[key.stringValue], CodError.unknownKey)))
				case .nullable(let keys):
					let offset = keys[key.stringValue]
					guard let offset = offset else {
						throw CodError.unknownKey
					}

					if let offset = offset {
						return try decode(type, from: data.slice(fromOffset: offset))
					} else if let type = type as? OptionalProtocol.Type {
						return type.nil as! T
					} else {
						throw CodError.invalidOptional
					}
			}
		}

		func decodeNil(forKey key: Key) throws -> Bool {
			switch keys {
				case .nullable(let keys):
					return keys[key.stringValue] == nil
				default:
					return false
			}
		}

		func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
			try KeyedDecodingContainer(KeyedContainer<NestedKey>(sharedContext: sharedContext, data: nestedData(for: key)))
		}

		func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
			try UnkeyedContainer(sharedContext: sharedContext, data: nestedData(for: key))
		}

		func superDecoder() throws -> Swift.Decoder {
			try superDecoder(forKey: Key(stringValue: "super")!)
		}

		func superDecoder(forKey key: Key) throws -> Swift.Decoder {
			try Decoder(sharedContext: sharedContext, data: nestedData(for: key))
		}

		func nestedData(for key: Key) throws -> Data {
			switch keys {
				case .nonnull(let keys):
					return try self.data.slice(fromOffset: evaluate(keys[key.stringValue], CodError.unknownKey))
				case .nullable(let keys):
					let offset = try evaluate(evaluate(keys[key.stringValue], CodError.unknownKey), CodError.unknownKey)
					return try self.data.slice(fromOffset: offset)
			}
		}
	}

	fileprivate class SharedContext {
		let shapes: [Int: [String]]
        var userInfo: [CodingUserInfoKey: Any] = [:]
		init(shapes: [Int: [String]]) {
			self.shapes = shapes
		}
	}
}

#if canImport(Combine)
	extension CodDecoder: TopLevelDecoder {}
#endif

private protocol DecodingContainer {
	var data: Data { get }
	var sharedContext: CodDecoder.SharedContext { get }
}

extension DecodingContainer {
	var codingPath: [CodingKey] {
		[]
	}

	func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
		switch type {
			case let type as TriviallyCopyable.Type:
				return try type.init(bytes: data) as! T
			case is String.Type:
				var data = data
				let count = try Int(uleb128: &data)
				return try evaluate(String(data: data.slice(toOffset: count), encoding: .utf8), CodError.invalidUTF8(data.startIndex)) as! T
			default:
				let decoder = try CodDecoder.Decoder(sharedContext: sharedContext, data: data)
				return try T(from: decoder)
		}
	}
}
