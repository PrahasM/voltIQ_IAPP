import XCTest
@testable import VoltIQ

final class CalculatorTests: XCTestCase {
    func testTargetCrossesTaperAt80AndUsesGridEnergy() throws {
        let result = try ChargingCalculator.calculate(Preferences(), settings: CarSettings(), efficiency: 0.92)
        XCTAssertEqual(result.energy, 33.97, accuracy: 1e-8)
        XCTAssertEqual(result.energyToBuy, 36.92391304347826, accuracy: 1e-8)
        XCTAssertEqual(result.total, 923.0978260869565, accuracy: 1e-8)
        XCTAssertEqual(result.base, result.total / 1.18, accuracy: 1e-8)
        XCTAssertEqual(result.enterKWh, 37)
        XCTAssertEqual(result.phases.count, 2)
        XCTAssertEqual(result.phases[0].to, 80)
        XCTAssertEqual(result.phases[1].power, 24)
        XCTAssertEqual(result.hours, 0.7227373188405797, accuracy: 1e-8)
    }

    func testACUsesCarLimitWithoutTaper() throws {
        var p = Preferences()
        p.chargerID = "ac22"
        let result = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.87)
        XCTAssertEqual(result.effectivePower, 11)
        XCTAssertEqual(result.phases.count, 1)
        XCTAssertFalse(result.phases[0].tapered)
        XCTAssertEqual(result.hours, 33.97 / 0.87 / 11, accuracy: 1e-8)
    }

    func testAmountUsesGrossGSTRateAndCapsFullBattery() throws {
        var p = Preferences()
        p.mode = .amount
        p.operatorID = "network"
        p.gstIncluded = false
        p.budget = 590
        let result = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92)
        XCTAssertEqual(result.energyToBuy, 20, accuracy: 1e-8)
        XCTAssertEqual(result.total, 590, accuracy: 1e-8)
        XCTAssertEqual(result.base, 500, accuracy: 1e-8)
        XCTAssertEqual(result.gst, 90, accuracy: 1e-8)
        p.current = 99
        let capped = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92)
        XCTAssertTrue(capped.capped)
        XCTAssertEqual(capped.finalPercent, 100)
        XCTAssertEqual(capped.energy, 0.79, accuracy: 1e-8)
        XCTAssertLessThan(capped.total, p.budget)
    }

    func testNoGSTAndTimeInverseAcross80Percent() throws {
        var p = Preferences()
        p.gstIncluded = false
        let target = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92)
        XCTAssertEqual(target.base, target.total)
        XCTAssertEqual(target.gst, 0)
        p.mode = .time
        p.minutes = target.hours * 60
        let timed = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92)
        XCTAssertEqual(timed.finalPercent, 85, accuracy: 1e-8)
        XCTAssertEqual(timed.energyToBuy, target.energyToBuy, accuracy: 1e-8)
        XCTAssertEqual(timed.total, target.total, accuracy: 1e-8)
    }

    func testTimeStartingAbove80AndCapRecomputesTime() throws {
        var p = Preferences()
        p.mode = .time
        p.current = 90
        p.minutes = 5
        let result = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92)
        XCTAssertEqual(result.energy, 24 * 5 / 60 * 0.92, accuracy: 1e-8)
        XCTAssertEqual(result.phases.count, 1)
        XCTAssertTrue(result.phases[0].tapered)
        p.minutes = 1000
        let capped = try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92)
        XCTAssertTrue(capped.capped)
        XCTAssertEqual(capped.finalPercent, 100)
        XCTAssertEqual(capped.hours, 7.9 / 0.92 / 24, accuracy: 1e-8)
    }

    func testEnterRoundingAbsorbsFloatingPointNoise() {
        let result = CalculationResult(energy: 1, energyToBuy: 37.000000001, finalPercent: 85, hours: 1,
                                       total: 1, base: 1, gst: 0, effectivePower: 60, capped: false, phases: [])
        XCTAssertEqual(result.enterKWh, 37)
    }

    func testInvalidInputDoesNotProduceInfinityOrNegativeCharge() {
        var p = Preferences()
        for capacity in [0, -1, Double.nan, Double.infinity] {
            p.capacity = capacity
            XCTAssertThrowsError(try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92))
        }
        p = Preferences()
        p.target = p.current
        XCTAssertThrowsError(try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92))
        p.mode = .amount
        p.current = 100
        XCTAssertThrowsError(try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0.92))
        p = Preferences()
        XCTAssertThrowsError(try ChargingCalculator.calculate(p, settings: CarSettings(), efficiency: 0))
    }
}
