//
//  BitVector.swift
//
//
//  Created by Saagar Jha on 3/25/21.
//

public struct BitVector: RandomAccessCollection, RangeReplaceableCollection, ExpressibleByArrayLiteral {
	public typealias Element = Bool
	public typealias Index = Int

	public let startIndex = 0
	public private(set) var endIndex: Int

	public private(set) var bytes: [UInt8]

	public init() {
		endIndex = 0
		bytes = []
	}

	public init<S>(bits: S) where S: Sequence, S.Element == Element {
		var position = 0
		bytes = bits.reduce(into: []) { bytes, next in
			if position % 8 == 0 {
				bytes.append(0)
			}
			bytes[bytes.endIndex - 1] |= (next ? 1 : 0) << (position % 8)
			position += 1
		}
		endIndex = position
	}

	public init<S>(bytes: S, count: Int) where S: Sequence, S.Element == UInt8 {
		endIndex = count
		self.bytes = Array(bytes.prefix((count + 7) / 8))
		precondition(count <= self.bytes.count * 8)
		clearTopBits()
	}

	public init(arrayLiteral elements: Element...) {
		self.init(bits: elements)
	}

	private mutating func set(at index: Index, to value: Element) {
		bytes[index / 8] = (bytes[index / 8]) & ~(1 << (index % 8)) | (value ? 1 : 0) << (index % 8)
	}

	private mutating func clearTopBits() {
		for i in endIndex..<(bytes.count * 8) {
			set(at: i, to: false)
		}
	}

	public subscript(position: Index) -> Element {
		get {
			precondition(startIndex <= position && position < endIndex)
			return (bytes[position / 8] >> (position % 8)) & 1 != 0
		}
		set {
			precondition(startIndex <= position && position < endIndex)
			set(at: position, to: newValue)
		}
	}

	public func index(_ i: Index, offsetBy distance: Int) -> Index {
		i + distance
	}

	public func distance(from start: Index, to end: Index) -> Index {
		end - start
	}

	public mutating func replaceSubrange<C>(_ subrange: Indices, with newElements: C) where C: Collection, Element == C.Element {
		precondition(startIndex <= subrange.startIndex && subrange.endIndex <= endIndex)
		let elements = Array(newElements)
		let sizeDifference = elements.count - subrange.count
		let newSize = (count + sizeDifference + 7) / 8
		let oldEndIndex = endIndex
		if sizeDifference > 0 {
			bytes.append(contentsOf: Array(repeating: 0, count: newSize - bytes.count))
			endIndex += sizeDifference
			for i in (subrange.endIndex..<oldEndIndex).reversed() {
				self[i + sizeDifference] = self[i]
			}
		} else if sizeDifference < 0 {
			for i in subrange.endIndex..<oldEndIndex {
				self[i + sizeDifference] = self[i]
			}
			bytes.removeLast(bytes.count - newSize)
			endIndex += sizeDifference
			clearTopBits()
		}
		for i in elements.indices {
			self[subrange.startIndex + i] = elements[i]
		}
	}
}
