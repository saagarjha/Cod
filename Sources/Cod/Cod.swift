//
//  Cod.swift
//
//
//  Created by Saagar Jha on 3/14/21.
//

import Foundation

enum SingleValueContainerMetadata: UInt8 {
	case nonnull
	case null
}

enum UnkeyedContainerMetadata: UInt8 {
	case homogenouslySized
	case hetrogenous
	case nullable
}

enum KeyedContainerMetadata: UInt8 {
	case nonnull
	case nullable
}

enum CodError: Swift.Error {
	case truncated
	case duplicateKeys
	case unknownKey
	case invalidOptional
	case invalidMetadata(Data.Index)
	case invalidShapeID(Data.Index)
	case invalidBool(Data.Index)
	case invalidUTF8(Data.Index)
}

func evaluate<T>(_ expression: T?, _ error: @autoclosure () -> Error) throws -> T {
	guard let value = expression else {
		throw error()
	}
	return value
}

extension RandomAccessCollection {
	func slice(fromOffset: Int = 0, toOffset: Int? = nil) throws -> SubSequence {
		let toOffset = toOffset ?? count
		guard toOffset >= fromOffset,
			fromOffset >= 0,
			toOffset <= count else {
			throw CodError.truncated
		}
		return self[index(startIndex, offsetBy: fromOffset)..<index(startIndex, offsetBy: toOffset)]
	}
}

protocol OptionalProtocol {
	var isNil: Bool { get }
	static var `nil`: Self { get }
}

extension Optional: OptionalProtocol {
	var isNil: Bool {
		self == nil
	}

	static var `nil`: Self {
		nil
	}
}
