//
//  TrivialCopying.swift
//
//
//  Created by Saagar Jha on 3/30/21.
//

import Foundation

protocol TriviallyCopyable {
	var bytes: Data { get }
	init(bytes: Data) throws
	init(bytes: inout Data) throws
}

extension TriviallyCopyable {
	init(bytes: inout Data) throws {
		try self.init(bytes: bytes)
		bytes = try bytes.slice(fromOffset: MemoryLayout<Self>.size)
	}
}

extension TriviallyCopyable where Self: FixedWidthInteger {
	var bytes: Data {
		Data((0..<MemoryLayout<Self>.size).map {
			UInt8(self >> ($0 * 8) & 0xff)
		})
	}
	
	init(bytes: Data) throws {
		self = try bytes.slice(toOffset: MemoryLayout<Self>.size).reversed().reduce(into: 0) { result, next in
			result = Self(next) | result << 8
		}
	}
}

// 0xff is unrepresentable in an Int8. See also https://bugs.swift.org/browse/SR-15709.
extension Int8: TriviallyCopyable {
	var bytes: Data {
		Data([UInt8(bitPattern: self)])
	}
	
	init(bytes: Data) throws {
		self = Int8(bitPattern: bytes.first!)
	}
}

extension Int16: TriviallyCopyable { }
extension Int32: TriviallyCopyable { }
extension Int64: TriviallyCopyable { }
extension Int: TriviallyCopyable { }
extension UInt8: TriviallyCopyable { }
extension UInt16: TriviallyCopyable { }
extension UInt32: TriviallyCopyable { }
extension UInt64: TriviallyCopyable { }
extension UInt: TriviallyCopyable { }

extension Bool: TriviallyCopyable {
	var bytes: Data {
		((self ? 1 : 0) as UInt8).bytes
	}
	
	init(bytes: Data) throws {
		guard let byte = bytes.first else {
			throw CodError.truncated
		}
		switch byte {
		case 0:
			self = false
		case 1:
			self = true
		default:
			throw CodError.invalidBool(bytes.startIndex)
		}
	}
}

extension Float: TriviallyCopyable {
	var bytes: Data {
		bitPattern.bytes
	}
	
	init(bytes: Data) throws {
		self.init(bitPattern: try .init(bytes: bytes))
	}
}

extension Double: TriviallyCopyable {
	var bytes: Data {
		bitPattern.bytes
	}
	
	init(bytes: Data) throws {
		self.init(bitPattern: try .init(bytes: bytes))
	}
}
//
//extension TriviallyCopyable {
//	init(bytes: Data) throws {
//		var storage = 0 as UInt
//		assert(MemoryLayout<Self>.size <= MemoryLayout.size(ofValue: storage))
//		assert(MemoryLayout<Self>.alignment <= MemoryLayout.alignment(ofValue: storage))
//
//		guard MemoryLayout<Self>.size <= bytes.count else {
//			throw CodError.truncated
//		}
//
//		self = withUnsafeMutableBytes(of: &storage) { buffer in
//			bytes.withUnsafeBytes {
//				buffer.baseAddress!.copyMemory(from: $0.baseAddress!, byteCount: MemoryLayout<Self>.size)
//				return buffer.bindMemory(to: Self.self).first!
//			}
//		}
//	}
//
//	init(bytes: inout Data) throws {
//		try self.init(bytes: bytes)
//		bytes = bytes[bytes.startIndex.advanced(by: MemoryLayout<Self>.size)...]
//	}
//
//	var bytes: Data {
//		var copy = self
//		return withUnsafeBytes(of: &copy) {
//			Data(buffer: $0.bindMemory(to: Self.self))
//		}
//	}
//}
