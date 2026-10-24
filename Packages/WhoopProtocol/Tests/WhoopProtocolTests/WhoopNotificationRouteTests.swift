import XCTest
@testable import WhoopProtocol

final class WhoopNotificationRouteTests: XCTestCase {
    func testBatteryFullOpensWhoopHomeWithoutUserInfo() {
        let destination = WhoopNotificationRoute.destination(
            identifier: "battery-full",
            categoryIdentifier: "",
            action: nil,
            route: nil)
        XCTAssertEqual(destination, .whoopHome)
    }

    func testExplicitWhoopRouteOpensHome() {
        let destination = WhoopNotificationRoute.destination(
            identifier: "battery-full",
            categoryIdentifier: "",
            action: nil,
            route: WhoopNotificationRoute.whoopHomeRoute)
        XCTAssertEqual(destination, .whoopHome)
    }

    func testOtherBatteryIdentifiersShareTheHomeRoute() {
        for identifier in WhoopNotificationRoute.batteryIdentifiers {
            let destination = WhoopNotificationRoute.destination(
                identifier: identifier,
                categoryIdentifier: "",
                action: " ",
                route: nil)
            XCTAssertEqual(destination, .whoopHome, identifier)
        }
    }

    func testUnknownPayloadOpensTheAppOnly() {
        let destination = WhoopNotificationRoute.destination(
            identifier: "rest-timer",
            categoryIdentifier: "gym",
            action: nil,
            route: nil)
        XCTAssertEqual(destination, .appOnly)
        let unknownRoute = WhoopNotificationRoute.destination(
            identifier: "something-else",
            categoryIdentifier: "",
            action: "",
            route: "nope")
        XCTAssertEqual(unknownRoute, .appOnly)
    }

    func testIosUpdateActionWinsOverAWhoopRoute() {
        let destination = WhoopNotificationRoute.destination(
            identifier: "nutry.ios-update.1",
            categoryIdentifier: "",
            action: WhoopNotificationRoute.iosUpdateAction,
            route: WhoopNotificationRoute.whoopHomeRoute)
        XCTAssertEqual(destination, .iosUpdate)
    }

    func testColdStartHoldsTheRouteUntilTheRouterExists() {
        var queue = WhoopPendingRouteQueue()
        XCTAssertNil(queue.receive(.whoopHome))
        XCTAssertEqual(queue.routerDidBecomeReady(), .whoopHome)
        XCTAssertNil(queue.routerDidBecomeReady())
        XCTAssertEqual(queue.receive(.whoopHome), .whoopHome)
    }

    func testUnknownPayloadIsNotQueued() {
        var queue = WhoopPendingRouteQueue()
        XCTAssertNil(queue.receive(.appOnly))
        XCTAssertNil(queue.routerDidBecomeReady())
    }

    func testColdStartRunsForegroundWorkOnce() {
        var gate = WhoopForegroundActivation()
        let launch = gate.admit(open: true)
        let scene = gate.admit(open: true)
        XCTAssertTrue(launch.startsForegroundWork)
        XCTAssertFalse(scene.startsForegroundWork)
        XCTAssertEqual(launch.generation, scene.generation)
        XCTAssertEqual(launch.generation, 1)
    }

    func testInactiveLaunchThenActiveRunsOnce() {
        var gate = WhoopForegroundActivation()
        XCTAssertFalse(gate.admit(open: false).startsForegroundWork)
        let active = gate.admit(open: true)
        XCTAssertTrue(active.startsForegroundWork)
        XCTAssertFalse(gate.admit(open: true).startsForegroundWork)
    }

    func testLeavingTheForegroundArmsTheNextOpen() {
        var gate = WhoopForegroundActivation()
        XCTAssertTrue(gate.admit(open: true).startsForegroundWork)
        gate.noteLeftForeground()
        XCTAssertTrue(gate.admit(open: true).startsForegroundWork)
        XCTAssertEqual(gate.generation, 2)
    }

    func testRescoreWaitsForAFrameAndAFreeEngine() {
        XCTAssertFalse(WhoopRescoreSchedule.shouldStart(afterFirstFrame: false, alreadyRunning: false))
        XCTAssertFalse(WhoopRescoreSchedule.shouldStart(afterFirstFrame: true, alreadyRunning: true))
        XCTAssertTrue(WhoopRescoreSchedule.shouldStart(afterFirstFrame: true, alreadyRunning: false))
    }
}
