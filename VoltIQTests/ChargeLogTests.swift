import XCTest
@testable import VoltIQ

final class ChargeLogTests: XCTestCase {
    private func draft() -> ChargeDraft {
        var d = ChargeDraft()
        d.start = 20
        d.end = 80
        d.billed = 50
        d.amount = 1000
        d.idle = 10
        return d
    }

    func testCompactSchemaRoundTripFeesAndLearning() throws {
        var op = ChargingOperator()
        op.name = "Network"
        op.gstIncluded = false
        op.sessionFee = 20
        op.idleFee = 2
        let entry = try draft().entry(capacity: 75, operator: op, manualGST: .included)
        XCTAssertEqual(entry.energy, 45)
        XCTAssertEqual(entry.efficiency, 0.9)
        XCTAssertEqual(entry.fees, 40)
        XCTAssertEqual(entry.spent, 1040)
        XCTAssertEqual(entry.effectiveRate, 20.8)
        XCTAssertEqual(entry.gst, .added)
        let data = try JSONEncoder().encode(entry)
        let keys = try JSONDecoder().decode([String: JSONValue].self, from: data)
        XCTAssertEqual(Set(keys.keys), ["t", "e", "c", "r", "g", "b", "s", "f", "y", "o", "oi", "m", "fe", "x", "q"])
        XCTAssertEqual(try JSONDecoder().decode(ChargeEntry.self, from: data), entry)
        XCTAssertNil(LearnedEfficiency.compute([entry, entry], type: .dc))
        XCTAssertEqual(try XCTUnwrap(LearnedEfficiency.compute([entry, entry, entry], type: .dc)).average, 0.9, accuracy: 1e-8)
        var impossible = entry
        impossible.efficiency = 1.5
        XCTAssertNil(LearnedEfficiency.compute([entry, entry, impossible], type: .dc))
        XCTAssertNil(LearnedEfficiency.compute([entry, entry, entry], type: .ac))
    }

    func testLegacyLogDecodesAndExportsEmptyNewFields() throws {
        let data = Data("[{\"t\":1720000000000,\"e\":10,\"c\":250,\"r\":25,\"g\":1,\"k\":60},{\"t\":1720000000001,\"e\":10,\"c\":250,\"r\":25,\"g\":0,\"k\":\"\"}]".utf8)
        let entries = try JSONDecoder().decode([ChargeEntry].self, from: data)
        XCTAssertEqual(entries[0].spent, 250)
        XCTAssertNil(entries[0].billed)
        XCTAssertNil(entries[1].chargerPower)
        let lines = ChargeCSV.export(entries).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1].split(separator: ",", omittingEmptySubsequences: false).count, 16)
    }

    func testCSVQuotesOperatorNames() throws {
        var op = ChargingOperator()
        op.name = "Green, \"Charge\"\nStation"
        let entry = try draft().entry(capacity: 75, operator: op, manualGST: .none)
        XCTAssertTrue(ChargeCSV.export([entry]).contains("\"Green, \"\"Charge\"\"\nStation\""))
    }

    func testRejectsMissingOrInvalidReceiptValues() {
        XCTAssertThrowsError(try ChargeDraft().entry(capacity: 75, operator: nil, manualGST: .none))
        var d = draft()
        d.end = 10
        XCTAssertThrowsError(try d.entry(capacity: 75, operator: nil, manualGST: .none))
        d = draft()
        d.billed = 0
        XCTAssertThrowsError(try d.entry(capacity: 75, operator: nil, manualGST: .none))
    }

    func testOperatorUsesNumericGSTFlagForWebCompatibility() throws {
        let data = Data("{\"id\":\"test\",\"n\":\"Local\",\"r\":25,\"g\":0,\"s\":20,\"f\":2}".utf8)
        let op = try JSONDecoder().decode(ChargingOperator.self, from: data)
        XCTAssertFalse(op.gstIncluded)
        XCTAssertEqual(try JSONDecoder().decode(ChargingOperator.self, from: JSONEncoder().encode(op)), op)
    }
}

private enum JSONValue: Decodable {
    case number(Double), string(String)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }
}
