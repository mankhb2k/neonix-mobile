import UIKit
import XCTest
@testable import NeonixEditor

final class MomentumDecayTests: XCTestCase {
    private let decay = MomentumDecay.iosNormal

    func testUsesTheLiveUIScrollViewNormalDecelerationRate() {
        let expected = -1000 * log(Double(UIScrollView.DecelerationRate.normal.rawValue))
        XCTAssertEqual(decay.rate, expected, accuracy: 1e-9)
        XCTAssertGreaterThan(decay.rate, 1.5)
        XCTAssertLessThan(decay.rate, 3.0)
    }

    func testClosedFormDistanceMatchesMillisecondStepping() {
        // UIScrollView's own model: velocity *= rate once per millisecond.
        let initial = 10_000.0
        var velocity = initial
        var position = 0.0
        for _ in 0..<2000 {
            velocity *= decay.retentionPerMillisecond
            position += velocity / 1000
        }
        let closedForm = decay.distance(initial: initial, after: 2)
        XCTAssertEqual(closedForm, position, accuracy: abs(closedForm) * 0.005)
    }

    func testDistanceApproachesTotalDistanceAndNeverOvershoots() {
        let initial = 8000.0
        let total = decay.totalDistance(initial: initial)
        XCTAssertEqual(decay.distance(initial: initial, after: 30), total, accuracy: 1)
        for seconds in stride(from: 0.1, through: 10, by: 0.1) {
            XCTAssertLessThanOrEqual(decay.distance(initial: initial, after: seconds), total)
        }
    }

    func testBackwardFlickMirrorsForward() {
        XCTAssertEqual(
            decay.distance(initial: -5000, after: 1.3),
            -decay.distance(initial: 5000, after: 1.3),
            accuracy: 1e-9
        )
    }

    func testHalfLifeAndOneSecondRetention() {
        let halfLife = log(2) / decay.rate
        XCTAssertEqual(decay.velocity(initial: 1000, after: halfLife), 500, accuracy: 1e-6)
        // The old hand-tuned curve kept 4% after one second; this keeps ~13.5%.
        let kept = decay.velocity(initial: 1000, after: 1) / 1000
        XCTAssertGreaterThan(kept, 0.12)
        XCTAssertLessThan(kept, 0.15)
    }

    func testTravelsFarFurtherThanTheOldBrakingCurve() {
        let oldRate = -log(0.04)
        let initial = 10_000.0
        let ratio = decay.totalDistance(initial: initial) / (initial / oldRate)
        XCTAssertGreaterThan(ratio, 1.5)
    }

    func testDurationUntilSpeedIsConsistentWithVelocity() {
        let initial = 10_000.0
        let stopSpeed = 50.0
        let seconds = decay.duration(initial: initial, until: stopSpeed)
        XCTAssertGreaterThan(seconds, 1)
        XCTAssertEqual(decay.velocity(initial: initial, after: seconds), stopSpeed, accuracy: 1e-6)
        XCTAssertEqual(decay.duration(initial: 30, until: stopSpeed), 0)
    }

    func testReleaseEstimatorUsesOnlyTheLastHundredMilliseconds() {
        var estimator = ReleaseVelocityEstimator()
        // Slow for 0.5 s (100 pt/s), then a fast last 100 ms (1000 pt/s).
        for i in 0...5 { estimator.add(time: Double(i) * 0.1, x: Double(i) * 10) }
        estimator.add(time: 0.55, x: 100)
        estimator.add(time: 0.6, x: 150)
        let speed = try? XCTUnwrap(estimator.pointsPerSecond)
        XCTAssertEqual(speed ?? 0, 1000, accuracy: 1)
    }

    func testReleaseEstimatorNeedsTwoSamplesAndReportsHold() {
        var estimator = ReleaseVelocityEstimator()
        XCTAssertNil(estimator.pointsPerSecond)
        estimator.add(time: 1, x: 0)
        XCTAssertNil(estimator.pointsPerSecond)
        XCTAssertEqual(estimator.holdSeconds(now: 1.25) ?? 0, 0.25, accuracy: 1e-9)
        estimator.reset()
        XCTAssertNil(estimator.holdSeconds(now: 2))
    }

    func testFrictionScaleChangesRateAndDistanceProportionally() {
        let base = MomentumDecay.iosNormal
        let half = base.scalingFriction(by: 0.5)
        XCTAssertEqual(half.rate, base.rate * 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.totalDistance(initial: 1000), base.totalDistance(initial: 1000) * 2, accuracy: 1e-6)
        XCTAssertEqual(base.scalingFriction(by: 1), base)
    }

    func testDefaultCoastTuningIsGainTwoWithLighterFriction() {
        let tuning = CoastTuning()
        XCTAssertEqual(tuning.velocityGain, 2)
        XCTAssertEqual(tuning.decay, MomentumDecay.iosNormal.scalingFriction(by: 0.7))
    }
}
