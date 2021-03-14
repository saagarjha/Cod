//
//  TransparentCoding.swift
//
//
//  Created by Saagar Jha on 3/30/21.
//

import Foundation

public protocol TransparentlyEncodable {
	func transparentlyEncode(into container: inout SingleValueEncodingContainer) throws
	func transparentlyEncode(into container: inout UnkeyedEncodingContainer) throws
	func transparentlyEncode<C: KeyedEncodingContainerProtocol>(into container: inout C, forKey key: C.Key) throws
}

public protocol TransparentlyDecodable {
	init(from container: SingleValueDecodingContainer) throws
	init(from container: inout UnkeyedDecodingContainer) throws
	init<C: KeyedDecodingContainerProtocol>(from container: C, forKey key: C.Key) throws
}

public typealias TransparentlyCodable = TransparentlyEncodable & TransparentlyDecodable

public protocol TransparentlyEncodableViaPassthrough: TransparentlyEncodable {
	associatedtype TransparentType: Encodable

	var passthroughValue: TransparentType { get }
}

extension TransparentlyEncodableViaPassthrough {
	public func transparentlyEncode(into container: inout SingleValueEncodingContainer) throws {
		try container.encode(passthroughValue)
	}

	public func transparentlyEncode(into container: inout UnkeyedEncodingContainer) throws {
		try container.encode(passthroughValue)
	}

	public func transparentlyEncode<C: KeyedEncodingContainerProtocol>(into container: inout C, forKey key: C.Key) throws {
		try container.encode(passthroughValue, forKey: key)
	}
}

public protocol TransparentlyDecodableViaPassthrough: TransparentlyDecodable {
	associatedtype TransparentType: Decodable

	init(passthroughValue: TransparentType)
}

extension TransparentlyDecodableViaPassthrough {
	public init(from container: SingleValueDecodingContainer) throws {
		self.init(passthroughValue: try container.decode(TransparentType.self))
	}

	public init(from container: inout UnkeyedDecodingContainer) throws {
		self.init(passthroughValue: try container.decode(TransparentType.self))
	}

	public init<C: KeyedDecodingContainerProtocol>(from container: C, forKey key: C.Key) throws {
		self.init(passthroughValue: try container.decode(TransparentType.self, forKey: key))
	}
}

public typealias TransparentlyCodableViaPassthrough = TransparentlyEncodableViaPassthrough & TransparentlyDecodableViaPassthrough
