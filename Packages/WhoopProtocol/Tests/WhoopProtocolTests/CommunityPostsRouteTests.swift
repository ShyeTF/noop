import XCTest
@testable import WhoopProtocol

final class CommunityPostsRouteTests: XCTestCase {
    func testDecodesTheSevenKeysAndACursor() throws {
        let json = """
        {"meals":[{"id":"m1","user_id":"leo"}],"barcodes":[],"feed":[{"id":"w1"}],"runs":[],"rides":[],"nextCursor":"Ab3-_xy","restricted":false}
        """
        let page = try CommunityPostsPage.decode(Data(json.utf8))
        XCTAssertEqual(page.meals.map(\.id), ["m1"])
        XCTAssertEqual(page.feed.map(\.id), ["w1"])
        XCTAssertTrue(page.barcodes.isEmpty)
        XCTAssertTrue(page.runs.isEmpty)
        XCTAssertTrue(page.rides.isEmpty)
        XCTAssertEqual(page.nextCursor, "Ab3-_xy")
        XCTAssertFalse(page.restricted)
    }

    func testNextCursorNullAndRestrictedStayDistinct() throws {
        let json = """
        {"meals":[],"barcodes":[],"feed":[],"runs":[],"rides":[],"nextCursor":null,"restricted":true}
        """
        let page = try CommunityPostsPage.decode(Data(json.utf8))
        XCTAssertNil(page.nextCursor)
        XCTAssertTrue(page.restricted)
        XCTAssertTrue(page.meals.isEmpty)
    }

    func testAMissingKeyDoesNotDecode() {
        let json = #"{"meals":[],"barcodes":[],"feed":[],"runs":[],"rides":[]}"#
        XCTAssertThrowsError(try CommunityPostsPage.decode(Data(json.utf8)))
    }

    func testJSON404IsProfileMissingAndHTML404IsUndeployed() {
        let json = CommunityPostsRoute.fault(httpStatus: 404, json: true, message: "Profil introuvable.")
        XCTAssertEqual(json, .missingProfile)
        XCTAssertFalse(CommunityPostsRoute.hidesMore(json))
        XCTAssertEqual(
            CommunityPersonLoad.message(for: CommunityPersonLoad.outcome(cancelled: false, profileNotFound: true)),
            "Profil introuvable")

        let html = CommunityPostsRoute.fault(httpStatus: 404, json: false, message: "Introuvable.")
        XCTAssertEqual(html, .routeNotDeployed)
        XCTAssertTrue(CommunityPostsRoute.hidesMore(html))
        XCTAssertNotEqual(html, .missingProfile)
    }

    func testFirstPageUsesThePostsRouteAndKeepsNextCursor() throws {
        let first = CommunityFeedRequest.userPostsPath(userId: "leo", types: nil, cursor: nil, limit: 30)
        XCTAssertEqual(first, "/api/v1/community/users/leo/posts?limit=30")
        XCTAssertFalse(first.contains("cursor="))
        XCTAssertEqual(
            CommunityFeedRequest.profilePath(userId: "leo", types: nil),
            "/api/v1/social?userId=leo")

        let json = """
        {"meals":[{"id":"m1"}],"barcodes":[],"feed":[],"runs":[],"rides":[],"nextCursor":"page-2","restricted":false}
        """
        let page = try CommunityPostsPage.decode(Data(json.utf8))
        XCTAssertTrue(CommunityPersonPagePlan.showsMore(nextCursor: page.nextCursor))
        XCTAssertEqual(page.nextCursor, "page-2")
        XCTAssertFalse(CommunityPersonPagePlan.showsMore(nextCursor: nil))
        XCTAssertFalse(CommunityPersonPagePlan.showsMore(nextCursor: ""))
    }

    func testHTML404FallsBackToMappingWithoutMore() {
        let html = CommunityPostsRoute.fault(httpStatus: 404, json: false, message: "Introuvable.")
        XCTAssertEqual(html, .routeNotDeployed)
        XCTAssertTrue(CommunityPersonPagePlan.keepsMappedPosts(fault: html))
        XCTAssertFalse(CommunityPersonPagePlan.fallbackShowsMore)

        let json = CommunityPostsRoute.fault(httpStatus: 404, json: true, message: "Profil introuvable.")
        XCTAssertFalse(CommunityPersonPagePlan.keepsMappedPosts(fault: json))
        XCTAssertFalse(CommunityPersonPagePlan.keepsMappedPosts(fault: .invalidCursor))
        XCTAssertFalse(CommunityPersonPagePlan.keepsMappedPosts(fault: .other))
    }

    func testDumbbellFactorMatchesTheFeed() {
        XCTAssertEqual(CommunitySetLoad.multiplier(equipment: "Haltères"), 2)
        XCTAssertEqual(CommunitySetLoad.multiplier(equipment: "haltères"), 2)
        XCTAssertEqual(CommunitySetLoad.multiplier(equipment: "Dumbbell"), 2)
        XCTAssertEqual(CommunitySetLoad.multiplier(equipment: "Barre olympique"), 1)
        XCTAssertEqual(CommunitySetLoad.multiplier(equipment: nil), 1)
        XCTAssertEqual(
            CommunitySetLoad.volume(weight: 12, reps: 8, equipment: "Haltères", completed: true),
            192)
        XCTAssertEqual(
            CommunitySetLoad.volume(weight: 12, reps: 8, equipment: "Haltères", completed: false),
            0)
        XCTAssertEqual(
            CommunitySetLoad.volume(weight: 20, reps: 5, equipment: "Barre", completed: true),
            100)
    }

    func testStopwatchNameAndCompletedDurationMatchTheFeed() {
        XCTAssertEqual(
            CommunityFeedExercise.displayName(
                exerciseID: CommunityFeedExercise.stopwatchID, catalogName: "Chronomètre", notes: "Gainage"),
            "Gainage")
        XCTAssertEqual(
            CommunityFeedExercise.displayName(
                exerciseID: CommunityFeedExercise.stopwatchID, catalogName: "Chronomètre", notes: ""),
            "Chronomètre")
        XCTAssertEqual(
            CommunityFeedExercise.displayName(
                exerciseID: "squat", catalogName: "Squat", notes: "lent"),
            "Squat")
        XCTAssertEqual(CommunityFeedExercise.durationSeconds(completed: true, duration: 40), 40)
        XCTAssertEqual(CommunityFeedExercise.durationSeconds(completed: true, duration: nil), 0)
        XCTAssertEqual(CommunityFeedExercise.durationSeconds(completed: false, duration: 40), 0)
    }

    func testFilterChangeWhileAPersonIsOpenResetsTheCursor() {
        XCTAssertTrue(CommunityPersonReload.reloadsPerson(pickedUserId: "leo"))
        XCTAssertFalse(CommunityPersonReload.reloadsPerson(pickedUserId: nil))
        XCTAssertFalse(CommunityPersonReload.reloadsPerson(pickedUserId: ""))
        XCTAssertNil(CommunityPersonReload.cursorAfterFilterChange(personOpen: true, previousCursor: "page-2"))
        XCTAssertEqual(
            CommunityPersonReload.cursorAfterFilterChange(personOpen: false, previousCursor: "page-2"),
            "page-2")
    }

    func testInvalidCursorHidesMoreWithoutRetrying() {
        let fault = CommunityPostsRoute.fault(httpStatus: 400, json: true, message: "Curseur invalide.")
        XCTAssertEqual(fault, .invalidCursor)
        XCTAssertTrue(CommunityPostsRoute.hidesMore(fault))
        XCTAssertEqual(CommunityPostsRoute.cursorNotice, "Les publications plus anciennes ne sont pas disponibles.")
        XCTAssertNotEqual(fault, .routeNotDeployed)
        XCTAssertEqual(
            CommunityPostsRoute.fault(httpStatus: 400, json: true, message: "Type de publication inconnu."),
            .unknownType)
    }
}