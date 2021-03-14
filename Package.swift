// swift-tools-version:5.3

import PackageDescription

let package = Package(
	name: "Cod",
	products: [
		.library(name: "Cod", targets: ["Cod"]),
	],
	targets: [
		.target(name: "Cod"),
		.testTarget(name: "CodTests", dependencies: ["Cod"]),
	]
)
