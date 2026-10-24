import XCTest
@testable import WhoopProtocol

final class WhoopEnergyBudgetTests: XCTestCase {
    func testEverySceneAndTrigger() {
        for scene in NutryEnergyScene.allCases {
            for trigger in NutryWakeTrigger.allCases {
                for activity in NutryBackgroundActivity.allCases {
                    let allowed = WhoopEnergyBudget.allows(activity, scene: scene, trigger: trigger)
                    XCTAssertEqual(
                        allowed,
                        expected(activity, scene: scene, trigger: trigger, heavyWorkPaused: false),
                        "\(activity) \(scene) \(trigger)")
                }
            }
        }
    }

    func testHeatStopsHeavyJobsButNotTheOpenScreen() {
        for activity in NutryBackgroundActivity.allCases {
            let allowed = WhoopEnergyBudget.allows(
                activity, scene: .active, trigger: .foreground, heavyWorkPaused: true, thermal: .serious)
            switch activity {
            case .rescore, .refreshV5, .accountSync, .autoContinue, .historyOffload:
                XCTAssertFalse(allowed, "\(activity)")
            default:
                XCTAssertTrue(allowed, "\(activity)")
            }
        }
    }

    func testExplicitContinuousHrvDoesNotKeepTheHeartStreamInTheBackground() {
        for scene in [NutryEnergyScene.background, .locked, .inactive] {
            XCTAssertFalse(WhoopEnergyBudget.allows(
                .standardHeartNotify, scene: scene, continuousHrvExplicit: true))
            XCTAssertFalse(WhoopEnergyBudget.allows(
                .realtimeStream, scene: scene, continuousHrvExplicit: true))
            XCTAssertFalse(WhoopEnergyBudget.allows(
                .keepAliveTimer, scene: scene, continuousHrvExplicit: true))
        }
    }

    func testBackgroundHistoryIsAShortWakeOnly() {
        XCTAssertEqual(WhoopEnergyBudget.backgroundSyncMaxDuration, 30)
        let start: TimeInterval = 1_700_000_000
        XCTAssertFalse(WhoopEnergyBudget.backgroundSyncExpired(startedAt: start, now: start + 29))
        XCTAssertTrue(WhoopEnergyBudget.backgroundSyncExpired(startedAt: start, now: start + 30))
        XCTAssertFalse(WhoopEnergyBudget.allows(.historyOffload, scene: .background, trigger: .sceneBackground))
        XCTAssertFalse(WhoopEnergyBudget.allows(.historyOffload, scene: .locked, trigger: .none))
        XCTAssertTrue(WhoopEnergyBudget.allows(.historyOffload, scene: .background, trigger: .strapEvent))
        XCTAssertTrue(WhoopEnergyBudget.allows(.historyOffload, scene: .locked, trigger: .stateRestoration))
        XCTAssertFalse(WhoopEnergyBudget.allows(.autoContinue, scene: .background, trigger: .strapEvent))
        XCTAssertFalse(WhoopEnergyBudget.allows(.accountSync, scene: .background))
        XCTAssertFalse(WhoopEnergyBudget.allows(.rescore, scene: .locked))
        XCTAssertFalse(WhoopEnergyBudget.allows(.refreshV5, scene: .background))
    }

    func testOrphanSessionAndLocation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = now.addingTimeInterval(-(4 * 60 * 60))
        let stale = now.addingTimeInterval(-(4 * 60 * 60 + 1))
        XCTAssertTrue(WhoopEnergyBudget.shouldResumeOpenSession(startedAt: recent, now: now, alreadyLive: false))
        XCTAssertFalse(WhoopEnergyBudget.shouldResumeOpenSession(startedAt: stale, now: now, alreadyLive: false))
        XCTAssertTrue(WhoopEnergyBudget.shouldResumeOpenSession(startedAt: stale, now: now, alreadyLive: true))
        let indoor = WhoopEnergyBudget.presenceLocation(indoor: true)
        XCTAssertFalse(indoor.allowsBackground)
        XCTAssertEqual(indoor.accuracyMeters, 100)
        XCTAssertEqual(indoor.distanceFilterMeters, 50)
        XCTAssertEqual(WhoopEnergyBudget.liveActivityInterval(inBackground: true), 15)
    }

    func testThermalAndReconnectAndBattery() {
        XCTAssertTrue(WhoopEnergyBudget.heavyWorkPaused(thermal: .serious, lowPower: false, inForeground: true))
        XCTAssertTrue(WhoopEnergyBudget.heavyWorkPaused(thermal: .critical, lowPower: false, inForeground: false))
        XCTAssertFalse(WhoopEnergyBudget.heavyWorkPaused(thermal: .nominal, lowPower: true, inForeground: true))
        XCTAssertTrue(WhoopEnergyBudget.heavyWorkPaused(thermal: .nominal, lowPower: true, inForeground: false))
        XCTAssertFalse(WhoopEnergyBudget.heavyWorkPaused(thermal: .fair, lowPower: false, inForeground: true))
        XCTAssertEqual(WhoopEnergyBudget.reconnectDelay(afterFailures: 1), 4)
        XCTAssertEqual(WhoopEnergyBudget.reconnectDelay(afterFailures: 6), WhoopSyncDecision.backgroundInterval)
        let t: TimeInterval = 1_700_000_000
        XCTAssertEqual(WhoopBatteryPresentation.percent(raw: 64, readAt: t, now: t), 64)
        XCTAssertNil(WhoopBatteryPresentation.percent(raw: nil, readAt: t, now: t))
        XCTAssertNil(WhoopBatteryPresentation.percent(raw: .nan, readAt: nil, now: t))
        XCTAssertTrue(WhoopBatteryPresentation.showsBolt(charging: true))
        XCTAssertFalse(WhoopBatteryPresentation.showsBolt(charging: nil))
        XCTAssertNil(WhoopBatteryPresentation.percent(raw: 64, readAt: t, now: t, connected: false))
        XCTAssertNil(WhoopBatteryPresentation.percent(raw: 64, readAt: t, now: t + (24 * 60 * 60) + 1, connected: true))
        XCTAssertEqual(WhoopBatteryRead.query(isWhoop5: false), .getBatteryLevel)
        XCTAssertEqual(WhoopBatteryRead.query(isWhoop5: true), .standardBatteryLevel)
        XCTAssertFalse(WhoopBatteryRead.shouldRequest(connected: false))
    }

    func testLiveHeartStaysOffThroughRestoreAndReconnect() {
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldSubscribeLiveHR(liveWorkSuspended: true, characteristic: "2A37"))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldSubscribeLiveHR(
            liveWorkSuspended: true, characteristic: "00002A37-0000-1000-8000-00805F9B34FB"))
        XCTAssertTrue(WhoopLiveLinkPolicy.shouldSubscribeLiveHR(liveWorkSuspended: true, characteristic: "2A19"))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldArmKeepalive(liveWorkSuspended: true))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldRunRealtime(liveWorkSuspended: true))
        XCTAssertTrue(WhoopLiveLinkPolicy.shouldStopHeartNotifyAfterSample(liveWorkSuspended: true))
    }

    func testForegroundResumeRearmsLiveHeart() {
        XCTAssertTrue(WhoopLiveLinkPolicy.shouldSubscribeLiveHR(liveWorkSuspended: false, characteristic: "2A37"))
        XCTAssertTrue(WhoopLiveLinkPolicy.shouldArmKeepalive(liveWorkSuspended: false))
        XCTAssertTrue(WhoopLiveLinkPolicy.shouldRunRealtime(liveWorkSuspended: false))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldStopHeartNotifyAfterSample(liveWorkSuspended: false))
    }

    func testLowPowerDoesNotBlockTheOpenScreen() {
        XCTAssertFalse(WhoopEnergyBudget.heavyWorkPaused(thermal: .nominal, lowPower: true, inForeground: true))
        XCTAssertFalse(WhoopEnergyBudget.heavyWorkPaused(thermal: .fair, lowPower: true, inForeground: true))
        XCTAssertTrue(WhoopEnergyBudget.heavyWorkPaused(thermal: .serious, lowPower: true, inForeground: true))
        XCTAssertTrue(WhoopEnergyBudget.allows(.historyOffload, scene: .active, trigger: .foreground, heavyWorkPaused: false))
        XCTAssertTrue(WhoopEnergyBudget.allows(.rescore, scene: .active, trigger: .foreground, heavyWorkPaused: false))
        XCTAssertTrue(WhoopEnergyBudget.allows(
            .historyOffload, scene: .background, trigger: .strapEvent, heavyWorkPaused: true, thermal: .nominal))
        XCTAssertFalse(WhoopEnergyBudget.allows(
            .historyOffload, scene: .background, trigger: .strapEvent, heavyWorkPaused: true, thermal: .serious))
        XCTAssertFalse(WhoopEnergyBudget.allows(
            .historyOffload, scene: .background, trigger: .strapEvent, heavyWorkPaused: true, thermal: .critical))
        XCTAssertFalse(WhoopEnergyBudget.allows(.autoContinue, scene: .background, trigger: .strapEvent, heavyWorkPaused: true))
        XCTAssertFalse(WhoopEnergyBudget.allows(.standardHeartNotify, scene: .background, trigger: .strapEvent))
        XCTAssertFalse(WhoopEnergyBudget.allows(.keepAliveTimer, scene: .background, trigger: .strapEvent))
        XCTAssertFalse(WhoopEnergyBudget.allows(.realtimeStream, scene: .locked, trigger: .stateRestoration))
    }

    func testOutdoorPresenceHeartbeatOnly() {
        XCTAssertTrue(WhoopEnergyBudget.presenceHeartbeatAllowed(
            activity: "coursy", sceneActive: false, secondsSinceLast: 60, forced: false))
        XCTAssertTrue(WhoopEnergyBudget.presenceHeartbeatAllowed(
            activity: "vely", sceneActive: false, secondsSinceLast: 90, forced: true))
        XCTAssertFalse(WhoopEnergyBudget.presenceHeartbeatAllowed(
            activity: "coursy", sceneActive: false, secondsSinceLast: 59, forced: true))
        XCTAssertFalse(WhoopEnergyBudget.presenceHeartbeatAllowed(
            activity: "muscy", sceneActive: false, secondsSinceLast: 600, forced: true))
        XCTAssertFalse(WhoopEnergyBudget.presenceHeartbeatAllowed(
            activity: nil, sceneActive: false, secondsSinceLast: 600, forced: true))
        XCTAssertTrue(WhoopEnergyBudget.presenceHeartbeatAllowed(
            activity: "muscy", sceneActive: true, secondsSinceLast: 20, forced: false))
    }

    func testBackgroundWakeLine() {
        XCTAssertEqual(
            WhoopEnergyBudget.backgroundWakeLine(wallSeconds: 90.2, cpuSeconds: 1.24),
            "Temps en arrière-plan : 90 s au mur, 1.2 s de processeur")
    }

    private func expected(
        _ activity: NutryBackgroundActivity,
        scene: NutryEnergyScene,
        trigger: NutryWakeTrigger,
        heavyWorkPaused: Bool
    ) -> Bool {
        if heavyWorkPaused {
            switch activity {
            case .rescore, .refreshV5, .accountSync, .autoContinue:
                return false
            case .historyOffload:
                break
            default:
                break
            }
        }
        let foreground = scene == .active
        switch activity {
        case .historyOffload:
            switch trigger {
            case .manual, .foreground:
                return foreground
            case .backgroundRefresh, .backgroundProcessing, .strapEvent, .reconnection, .stateRestoration:
                return foreground == false
            case .none, .sceneBackground:
                return false
            }
        case .rescore, .refreshV5, .accountSync, .autoContinue,
             .keepAliveTimer, .standardHeartNotify, .realtimeStream, .silenceWatchdog, .liveRelay,
             .runTogetherPoll, .muscyPoll, .followedLivePoll, .presencePoll, .musicPoll:
            return foreground
        }
    }
}
