//
//  CodTestsShared.swift
//
//
//  Created by Saagar Jha on 3/14/21.
//

import XCTest

@testable import Cod

func checkRoundtrip(_ value: TestingCodable) {
	XCTAssertNoThrow(XCTAssertTrue(try type(of: value).decode(from: try value.encode(to: CodEncoder()), decoder: CodDecoder()).isEquivalent(to: value)))
}

protocol TestingCodable: Codable {
	func isEquivalent(to other: TestingCodable) -> Bool
}

extension TestingCodable {
	func encode(to encoder: CodEncoder) throws -> Data {
		try encoder.encode(self)
	}

	static func decode(from data: Data, decoder: CodDecoder) throws -> Self {
		try decoder.decode(Self.self, from: data)
	}

	func encode(into singleValueContainer: inout SingleValueEncodingContainer) throws {
		try singleValueContainer.encode(self)
	}

	func encode(into unkeyedContainer: inout UnkeyedEncodingContainer) throws {
		try unkeyedContainer.encode(self)
	}

	func encode<K: CodingKey>(for key: K, into keyedContainer: inout KeyedEncodingContainer<K>) throws {
		try keyedContainer.encode(self, forKey: key)
	}

	static func decode(from singleValueContainer: SingleValueDecodingContainer) throws -> TestingCodable {
		try singleValueContainer.decode(Self.self)
	}

	static func decode(from unkeyedContainer: inout UnkeyedDecodingContainer) throws -> TestingCodable {
		return try unkeyedContainer.decode(Self.self)
	}

	static func decode<K: CodingKey>(for key: K, from keyedContainer: KeyedDecodingContainer<K>) throws -> TestingCodable {
		try keyedContainer.decode(Self.self, forKey: key)
	}
}

protocol RandomTestingCodable: TestingCodable {
	static func random() -> Self
}

extension TestingCodable where Self: Equatable {
	func isEquivalent(to other: TestingCodable) -> Bool {
		self == other as! Self
	}
}

extension RandomTestingCodable where Self: FixedWidthInteger {
	static func random() -> Self {
		Self.random(in: Self.min...Self.max)
	}
}

extension RandomTestingCodable where Self == Double {
	static func random() -> Self {
		Self(bitPattern: .random())
	}

	func isEquivalent(to other: TestingCodable) -> Bool {
		return self.bitPattern == (other as! Self).bitPattern
	}
}

extension RandomTestingCodable where Self == Float {
	static func random() -> Self {
		Self(bitPattern: .random())
	}

	func isEquivalent(to other: TestingCodable) -> Bool {
		return self.bitPattern == (other as! Self).bitPattern
	}
}

extension Bool: RandomTestingCodable {}
extension Int8: RandomTestingCodable {}
extension Int16: RandomTestingCodable {}
extension Int32: RandomTestingCodable {}
extension Int64: RandomTestingCodable {}
extension Int: RandomTestingCodable {}
extension UInt8: RandomTestingCodable {}
extension UInt16: RandomTestingCodable {}
extension UInt32: RandomTestingCodable {}
extension UInt64: RandomTestingCodable {}
extension UInt: RandomTestingCodable {}
extension Float: RandomTestingCodable {}
extension Double: RandomTestingCodable {}

let testingCodables: [RandomTestingCodable.Type] = [
	Bool.self,
	Int8.self,
	Int16.self,
	Int32.self,
	Int64.self,
	Int.self,
	UInt8.self,
	UInt16.self,
	UInt32.self,
	UInt64.self,
	UInt.self,
	Float.self,
	Double.self,
]

protocol TestingCodableContainer {
	static var testingCodable: TestingCodableHeirarchy! { get set }
}

indirect enum TestingCodableHeirarchy {
	case simple(TestingCodable.Type)
	case singleValue(TestingCodableHeirarchy)
	case unkeyed([TestingCodableHeirarchy])
	case keyed([TestingCodableHeirarchy])

	func temporarySetTestingCodable(_ decode: (TestingCodable.Type) throws -> TestingCodable) rethrows -> TestingCodable {
		let container: TestingCodableContainer.Type?
		switch self {
			case .simple(_):
				container = nil
			case .singleValue(_):
				container = TestingSingleValueContainer.self
			case .unkeyed(_):
				container = TestingUnkeyedContainer.self
			case .keyed(_):
				container = TestingKeyedContainer.self
		}
		let oldTestingCodable = container?.testingCodable
		defer {
			container?.testingCodable = oldTestingCodable
		}
		container?.testingCodable = self
		return try decode(testingCodable)
	}

	var testingCodable: TestingCodable.Type {
		switch self {
			case .simple(let testingCodable):
				return testingCodable
			case .singleValue(_):
				return TestingSingleValueContainer.self
			case .unkeyed(_):
				return TestingUnkeyedContainer.self
			case .keyed(_):
				return TestingKeyedContainer.self
		}
	}
}

struct TestingSingleValueContainer: TestingCodable, TestingCodableContainer {
	let value: TestingCodable
	static var testingCodable: TestingCodableHeirarchy!

	func isEquivalent(to other: TestingCodable) -> Bool {
		return value.isEquivalent(to: (other as! Self).value)
	}
}

extension TestingSingleValueContainer {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		switch Self.testingCodable {
			case .singleValue(let testingCodable):
				value = try testingCodable.temporarySetTestingCodable {
					try $0.decode(from: container)
				}
			default:
				fatalError()
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try value.encode(into: &container)
	}
}

struct TestingUnkeyedContainer: TestingCodable, TestingCodableContainer {
	let values: [TestingCodable]
	static var testingCodable: TestingCodableHeirarchy!

	func isEquivalent(to other: TestingCodable) -> Bool {
		values.elementsEqual((other as! Self).values) {
			$0.isEquivalent(to: $1)
		}
	}
}

extension TestingUnkeyedContainer {
	init(from decoder: Decoder) throws {
		var container = try decoder.unkeyedContainer()
		switch Self.testingCodable {
			case .unkeyed(let testingCodables):
				values = try testingCodables.map { testingCodable in
					try testingCodable.temporarySetTestingCodable {
						try $0.decode(from: &container)
					}
				}
			default:
				fatalError()
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.unkeyedContainer()
		for value in values {
			try value.encode(into: &container)
		}
	}
}

struct TestingKeyedContainer: TestingCodable, TestingCodableContainer {
	let values: [TestingCodable]
	static var testingCodable: TestingCodableHeirarchy!

	func isEquivalent(to other: TestingCodable) -> Bool {
		values.elementsEqual((other as! Self).values) {
			$0.isEquivalent(to: $1)
		}
	}

	struct CodingKeys: CodingKey {
		var stringValue: String

		init?(stringValue: String) {
			self.stringValue = stringValue
		}

		var intValue: Int?

		init?(intValue: Int) {
			nil
		}
	}
}

extension TestingKeyedContainer {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		switch Self.testingCodable {
			case .keyed(let testingCodables):
				values = try testingCodables.enumerated().map { (index, testingCodable) in
					try testingCodable.temporarySetTestingCodable {
						try $0.decode(for: CodingKeys(stringValue: "\(index)")!, from: container)
					}
				}
			default:
				fatalError()
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		for (index, value) in values.enumerated() {
			try value.encode(for: CodingKeys(stringValue: "\(index)")!, into: &container)
		}
	}
}
