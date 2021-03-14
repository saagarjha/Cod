//
//  CodBasicTests.swift
//
//
//  Created by Saagar Jha on 3/14/21.
//

import XCTest
@testable import Cod

final class CodBasicTests: XCTestCase {
	func testSingleValueRoundtrip() {
		for testingCodable in testingCodables {
			TestingSingleValueContainer.testingCodable = .singleValue(.simple(testingCodable))
			checkRoundtrip(TestingSingleValueContainer(value: testingCodable.random()))
		}
	}

	func testUnkeyedRoundtrip() {
		for testingCodables in Self.combinationsOfTestingCodables {
			TestingUnkeyedContainer.testingCodable = .unkeyed(
				testingCodables.map {
					.simple($0)
				})
			checkRoundtrip(
				TestingUnkeyedContainer(
					values: testingCodables.map {
						$0.random()
					}))
		}
	}

	func testKeyedRoundtrip() {
		for testingCodables in Self.combinationsOfTestingCodables {
			TestingKeyedContainer.testingCodable = .keyed(
				testingCodables.map {
					.simple($0)
				})
			checkRoundtrip(
				TestingKeyedContainer(
					values: testingCodables.map {
						$0.random()
					}))
		}
	}

	func testNestedSingleValueRoundtrip() {
		for testingCodables in Self.combinationsOfTestingCodables {
			TestingSingleValueContainer.testingCodable = .singleValue(
				.unkeyed(
					testingCodables.map {
						.simple($0)
					}))
			checkRoundtrip(
				TestingSingleValueContainer(
					value: TestingUnkeyedContainer(
						values: testingCodables.map {
							$0.random()
						})))

			TestingSingleValueContainer.testingCodable = .singleValue(
				.keyed(
					testingCodables.map {
						.simple($0)
					}))
			checkRoundtrip(
				TestingSingleValueContainer(
					value: TestingKeyedContainer(
						values: testingCodables.map {
							$0.random()
						})))
		}
	}

	func testNestedUnkeyedRoundtrip() {
		for testingCodables in Self.combinationsOfTestingCodables {
			TestingUnkeyedContainer.testingCodable = .unkeyed(
				testingCodables.map {
					.singleValue(.simple($0))
				})
			checkRoundtrip(
				TestingUnkeyedContainer(
					values: testingCodables.map {
						TestingSingleValueContainer(value: $0.random())
					}))
		}

		//		for combination in Array(Self.combinationsOfTestingCodables.shuffled().prefix(5)).combinations(ofSize: 3) {
		//			for permutation in combination.permutations() {
		//				TestingUnkeyedContainer.testingCodable = .unkeyed(permutation.map {
		//					.keyed($0.map {
		//						.simple($0)
		//					})
		//				})
		//				checkRoundtrip(TestingUnkeyedContainer(values: permutation.map {
		//					TestingKeyedContainer(values: $0.map {
		//						$0.random()
		//					})
		//				}))
		//			}
		//		}
	}

	func testSingleValueNullableRoundtrip() {
		for testingCodable in testingCodables {
			TestingSingleValueContainer.testingCodable = .singleValue(.simple(testingCodable))
			//			checkRoundtrip(TestingSingleValueContainer(value: Optional.some(testingCodable.random())))
		}
	}

	func testNestedKeyedRoundtrip() {
		for testingCodables in Self.combinationsOfTestingCodables {
			TestingKeyedContainer.testingCodable = .keyed(
				testingCodables.map {
					.singleValue(.simple($0))
				})
			checkRoundtrip(
				TestingKeyedContainer(
					values: testingCodables.map {
						TestingSingleValueContainer(value: $0.random())
					}))
		}
	}

	static var combinationsOfTestingCodables = {
		(0..<5).flatMap {
			testingCodables.combinations(ofSize: $0).flatMap {
				$0.permutations()
			}
		}
	}()
}

// Not the most performant or generic, but it'll do for these tests
extension Array {
	func combinations(ofSize size: Int) -> [Self] {
		precondition(size <= count)
		guard size > 0 else {
			return [[]]
		}
		return (startIndex..<index(endIndex, offsetBy: -size)).flatMap { i in
			Self(self[index(after: i)...]).combinations(ofSize: size - 1).map {
				[self[i]] + $0
			}
		}
	}

	func permutations() -> [Self] {
		guard !self.isEmpty else {
			return [[]]
		}
		var copy = self
		return (startIndex..<endIndex).flatMap { i -> [Self] in
			let element = copy.remove(at: i)
			defer {
				copy.insert(element, at: i)
			}
			return copy.permutations().map {
				[element] + Array($0)
			}
		}
	}
}
