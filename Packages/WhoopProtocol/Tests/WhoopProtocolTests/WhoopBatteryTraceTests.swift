import XCTest

@testable import WhoopProtocol

/// La courbe « Batterie récente » doit être continue, sans jamais rien
/// inventer avant le premier relevé ni après le dernier.
final class WhoopBatteryTraceTests: XCTestCase {
    private func trace(
        _ points: [(time: TimeInterval, value: Double)]
    ) -> [WhoopBatteryTrace.Sample] {
        WhoopBatteryTrace.continuous(points: points)
    }

    func testNothingIsInventedBeforeOrAfterTheMeasurements() {
        let points: [(time: TimeInterval, value: Double)] = [
            (0, 100), (480, 98), (960, 96), (960 + 7200, 70), (960 + 7680, 69),
        ]
        let samples = trace(points)
        XCTAssertEqual(samples.first?.time, 0)
        XCTAssertEqual(samples.first?.value, 100)
        XCTAssertEqual(samples.first?.measured, true)
        XCTAssertEqual(samples.last?.time, 960 + 7680)
        XCTAssertEqual(samples.last?.value, 69)
        XCTAssertEqual(samples.last?.measured, true)
    }

    func testEveryMeasurementIsKeptUntouched() {
        let points: [(time: TimeInterval, value: Double)] = [
            (0, 100), (480, 98), (960, 96), (960 + 7200, 70),
        ]
        let kept = trace(points).filter(\.measured)
        XCTAssertEqual(kept.count, points.count)
        for (sample, point) in zip(kept, points) {
            XCTAssertEqual(sample.time, point.time)
            XCTAssertEqual(sample.value, point.value)
        }
    }

    func testAHoleIsFilledAndTheTimesStayIncreasing() {
        // Cadence de huit minutes, puis un trou de deux heures.
        let points: [(time: TimeInterval, value: Double)] = [
            (0, 100), (480, 98), (960, 96), (960 + 7200, 70),
        ]
        let samples = trace(points)
        let inHole = samples.filter { $0.time > 960 && $0.time < 960 + 7200 }
        XCTAssertFalse(inHole.isEmpty, "le trou doit être comblé")
        XCTAssertTrue(inHole.allSatisfy { $0.measured == false })
        for index in 1..<samples.count {
            XCTAssertGreaterThan(samples[index].time, samples[index - 1].time)
        }
    }

    func testTheCurveNeverOvershootsItsNeighbours() {
        // Fritsch–Carlson : une batterie qui descend ne remonte pas dans le creux.
        let points: [(time: TimeInterval, value: Double)] = [
            (0, 100), (480, 60), (960, 58), (960 + 7200, 12), (960 + 7680, 11),
        ]
        let samples = trace(points)
        for index in 0..<(points.count - 1) {
            let low = min(points[index].value, points[index + 1].value)
            let high = max(points[index].value, points[index + 1].value)
            let inner = samples
                .filter { $0.time > points[index].time && $0.time < points[index + 1].time }
                .map(\.value)
            for value in inner {
                XCTAssertGreaterThanOrEqual(value, low - 1e-9)
                XCTAssertLessThanOrEqual(value, high + 1e-9)
            }
        }
        // Et la série reste globalement décroissante, comme les relevés.
        for index in 1..<samples.count {
            XCTAssertLessThanOrEqual(samples[index].value, samples[index - 1].value + 1e-9)
        }
    }

    func testValuesStayWithinZeroAndOneHundred() {
        let points: [(time: TimeInterval, value: Double)] = [
            (0, 2), (480, 1), (960 + 7200, 0), (960 + 7680, 0),
        ]
        for sample in trace(points) {
            XCTAssertGreaterThanOrEqual(sample.value, 0)
            XCTAssertLessThanOrEqual(sample.value, 100)
        }
    }

    /// Le test ci-dessus ne prouvait rien : ses relevés tenaient déjà dans
    /// `0...2`, donc l’interpolation ne pouvait pas en sortir — il passait même
    /// sans le bornage. Celui-ci part de valeurs **hors bornes**, qui ne
    /// passaient justement pas par le bornage avant ce correctif.
    func testOutOfRangeMeasurementsAreClamped() {
        let high = trace([(0, 150), (4800, 40)])
        XCTAssertEqual(high.first?.value, 100, "une mesure à 150 % ressort à 100")
        let low = trace([(0, -20), (4800, 40)])
        XCTAssertEqual(low.first?.value, 0, "une mesure négative ressort à 0")
        for sample in high + low {
            XCTAssertGreaterThanOrEqual(sample.value, 0)
            XCTAssertLessThanOrEqual(sample.value, 100)
        }
        // Et la marche artificielle a disparu : le premier point calculé reste
        // sous la mesure bornée, au lieu de plonger depuis 150.
        XCTAssertLessThanOrEqual(high[1].value, 100)
    }

    /// Un Catmull-Rom naïf dépasse sur ce profil : forte descente, puis palier.
    /// Fritsch–Carlson doit rester dans l’intervalle de chaque paire voisine.
    func testNoOvershootOnASharpDropFollowedByAPlateau() {
        let points: [(time: TimeInterval, value: Double)] = [
            (0, 100), (480, 60), (960, 58), (8160, 12),
        ]
        let samples = trace(points)
        XCTAssertGreaterThan(samples.count, points.count, "les trous sont comblés")
        // Chaque point calculé tient entre les deux mesures qui l’encadrent.
        var index = 0
        for pair in zip(points, points.dropFirst()) {
            let lower = min(pair.0.value, pair.1.value)
            let upper = max(pair.0.value, pair.1.value)
            while index < samples.count, samples[index].time <= pair.1.time {
                if samples[index].time >= pair.0.time, !samples[index].measured {
                    XCTAssertGreaterThanOrEqual(samples[index].value, lower - 1e-9)
                    XCTAssertLessThanOrEqual(samples[index].value, upper + 1e-9)
                }
                index += 1
            }
        }
        // La série reste décroissante de bout en bout, sans rebond dans le creux.
        for position in 1..<samples.count {
            XCTAssertLessThanOrEqual(
                samples[position].value, samples[position - 1].value + 1e-9)
        }
    }

    func testTooFewMeasurementsInventNothing() {
        XCTAssertEqual(trace([]).count, 0)
        let single = trace([(10, 42)])
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.first?.measured, true)
    }

    func testCloseMeasurementsAreLeftAlone() {
        // Soixante secondes d’écart : rien à combler.
        XCTAssertEqual(trace([(0, 50), (60, 49)]).count, 2)
    }

    func testUnorderedAndDuplicatedInputIsNormalised() {
        let samples = trace([(960, 96), (0, 100), (480, 98), (480, 97)])
        let measured = samples.filter(\.measured)
        XCTAssertEqual(measured.map(\.time), [0, 480, 960])
        XCTAssertEqual(measured.map(\.value), [100, 97, 96], "le dernier relevé d’un instant gagne")
    }

    func testAVeryLongHoleStaysBounded() {
        // Bracelet laissé de côté une semaine : la série ne doit pas exploser.
        let samples = trace([(0, 80), (7 * 24 * 3600, 5)])
        XCTAssertLessThanOrEqual(samples.count, WhoopBatteryTrace.maxFillPerGap + 2)
        XCTAssertEqual(samples.first?.value, 80)
        XCTAssertEqual(samples.last?.value, 5)
    }
}
