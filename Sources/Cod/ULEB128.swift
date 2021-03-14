//
//  ULEB128.swift
//
//
//  Created by Saagar Jha on 3/25/21.
//

import Foundation

// TODO: BinaryInteger
extension FixedWidthInteger {
	public var uleb128: Data {
		precondition(self >= 0)
		var bytes = [UInt8]()
		var copy = self
		repeat {
			let bits = UInt8(copy & 0b0111_1111) | 0b1000_0000
			bytes.append(bits)
			copy >>= 7
		} while copy != 0
		bytes.append(bytes.popLast()! & ~0b1000_0000)
		return Data(bytes)
	}

	public init(uleb128 data: inout Data) throws {
		self = 0
		var index = data.startIndex
		var bits: UInt8
		repeat {
			guard (index - data.startIndex) * 8 / 7 <= MemoryLayout<Self>.size + 1,
				index < data.endIndex
			else {
				throw CodError.truncated
			}
			bits = data[index]
			self |= Self(bits & 0b0111_1111) << Self(7 * (index - data.startIndex))
			index += 1
		} while bits & 0b1000_0000 != 0
		data = data[index...]
	}
}
