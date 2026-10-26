import XCTest
@testable import Ensembyte

final class JSONValueTests: XCTestCase {
    // MARK: - Parsing

    func testParseFragments() {
        XCTAssertEqual(JSONValue.parse("42")?.int, 42)
        XCTAssertEqual(JSONValue.parse("3.5")?.double, 3.5)
        XCTAssertEqual(JSONValue.parse("\"hi\"")?.string, "hi")
        XCTAssertEqual(JSONValue.parse("true")?.bool, true)
        XCTAssertEqual(JSONValue.parse("null")?.isNull, true)
        XCTAssertNil(JSONValue.parse("junk"))
        XCTAssertNil(JSONValue.parse(""))
        XCTAssertNil(JSONValue.parse("[1,"))
    }

    func testParseNestedStructure() {
        let value = JSONValue.parse(#"{"a": [1, 2.5, "x"], "b": {"c": true}}"#)
        let object = value?.object
        XCTAssertEqual(object?["a"]?.array?.count, 3)
        XCTAssertEqual(object?["a"]?[0]?.int, 1)
        XCTAssertEqual(object?["a"]?[1]?.double, 2.5)
        XCTAssertEqual(object?["a"]?[2]?.string, "x")
        XCTAssertEqual(object?["b"]?["c"]?.bool, true)
    }

    // MARK: - Encode / round-trip

    func testRoundTripScalars() {
        for value in [JSONValue.null, .bool(true), .bool(false), .int(0), .int(-17), .double(2.25), .string("s/é\n\"q\"")] {
            let re = JSONValue.parse(value.data())
            XCTAssertEqual(re, value)
        }
    }

    func testRoundTripCompound() {
        let value: JSONValue = ["outer": ["list": ["a", 1, 1.5, nil], "flag": true], "empty": [:]]
        let re = JSONValue.parse(value.data())
        XCTAssertEqual(re, value)
        XCTAssertEqual(re?["empty"]?.object?.isEmpty, true)
    }

    func testPrettyPrintsKeysSorted() {
        let value: JSONValue = ["z": 1, "a": 2]
        let pretty = value.prettyString
        let z = pretty.range(of: "\"z\"")!.lowerBound
        let a = pretty.range(of: "\"a\"")!.lowerBound
        XCTAssertLessThan(a, z, "pretty output must sort keys")
        // Compact output does not promise key order, but both must hold the data.
        XCTAssertEqual(JSONValue.parse(value.compactString)?.object?["z"]?.int, 1)
    }

    func testDataOfNull() {
        XCTAssertEqual(JSONValue.null.data(), Data("null".utf8))
        XCTAssertEqual(JSONValue.null.data(pretty: true), Data("null".utf8))
    }

    // MARK: - Accessors

    func testStringToIntCoercion() {
        XCTAssertEqual(JSONValue.string("42").int, 42)
        XCTAssertEqual(JSONValue.string("oops").int, nil)
        XCTAssertEqual(JSONValue.double(4.9).int, 4)
        XCTAssertEqual(JSONValue.double(Double.nan).int, nil)
        XCTAssertEqual(JSONValue.int(7).double, 7.0)
        XCTAssertEqual(JSONValue.bool(true).int, nil)
    }

    func testSubscriptBounds() {
        let value: JSONValue = [10, 20]
        XCTAssertEqual(value[0]?.int, 10)
        XCTAssertEqual(value[1]?.int, 20)
        XCTAssertNil(value[2])
        XCTAssertNil(value[-1])
        XCTAssertEqual(value["key"] as JSONValue?, nil)
    }

    func testDisplayText() {
        XCTAssertEqual(JSONValue.null.displayText, "")
        XCTAssertEqual(JSONValue.string("plain").displayText, "plain")
        XCTAssertEqual(JSONValue.bool(false).displayText, "false")
        XCTAssertEqual(JSONValue.int(3).displayText, "3")
        XCTAssertEqual(JSONValue.string("4").displayText, "4")
        let object: JSONValue = [.int(1), .int(2)]
        XCTAssertEqual(object.displayText, object.prettyString)
    }

    // MARK: - Literals and helpers

    func testDictionaryLiteralKeepsLast() {
        let value = ["k": .int(1), "k": .int(2)] as JSONValue
        XCTAssertEqual(value["k"]?.int, 2)
        let nilString = JSONValue.optional(nil as String?)
        XCTAssertEqual(nilString.isNull, true)
        XCTAssertEqual(JSONValue.optional("v").string, "v")
    }

    func testFoundationObjectShape() {
        let value: JSONValue = [.int(1), .string("s"), .bool(false)]
        let object = value.foundationObject
        let array = object as? [AnyHashable]
        XCTAssertEqual(array, [1 as AnyHashable, "s" as AnyHashable, false as AnyHashable])
        XCTAssertEqual(JSONValue(foundation: [1, "two", NSNull()]).string, nil)
        XCTAssertEqual(JSONValue(foundation: "raw").string, "raw")
    }
}
