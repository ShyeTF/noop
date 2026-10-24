import XCTest
@testable import WhoopProtocol

final class CommunitySearchTests: XCTestCase {
    private let lea = CommunitySearchHit(id: "lea", name: "Léa Martin", username: "lea")
    private let leo = CommunitySearchHit(id: "leo", name: "Léo", username: "leo")

    func testEmptyQueryReturnsToTheFeed() {
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "  ", hits: [lea]), .feed)
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "", hits: []), .feed)
    }

    func testSingleOrExactMatchOpensThePerson() {
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "lea", hits: [lea]), .person("lea"))
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "Léo", hits: [lea, leo]), .person("leo"))
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "@lea", hits: [lea, leo]), .person("lea"))
    }

    func testSeveralResultsStayAListUntilATap() {
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "l", hits: [lea, leo]), .list)
        XCTAssertEqual(CommunitySearchOpen.resolve(query: "nobody", hits: []), .list)
    }

    func testUserPostsQueryCarriesUserTypesAndCursor() {
        let path = CommunityFeedRequest.userPostsPath(
            userId: "leo id", types: "meal,vely", cursor: "abc", limit: 30)
        XCTAssertTrue(path.hasPrefix("/api/v1/community/users/leo%20id/posts?"))
        XCTAssertTrue(path.contains("types=meal,vely"))
        XCTAssertTrue(path.contains("cursor=abc"))
        XCTAssertTrue(path.contains("limit=30"))
        let open = CommunityFeedRequest.userPostsPath(userId: "lea", types: nil, cursor: nil, limit: 30)
        XCTAssertFalse(open.contains("types="))
        XCTAssertFalse(open.contains("cursor="))
    }

    func testPrivateProfileHidesPosts() {
        XCTAssertTrue(CommunityPersonPostsGate.hidesPosts(restricted: true))
        XCTAssertFalse(CommunityPersonPostsGate.hidesPosts(restricted: false))
    }

    func testCursorUsesAStrictQuerySet() {
        let path = CommunityFeedRequest.userPostsPath(
            userId: "leo", types: nil, cursor: "a/b?c=d&e", limit: 30)
        XCTAssertTrue(path.contains("cursor=a%2Fb%3Fc%3Dd%26e"))
        XCTAssertFalse(path.contains("cursor=a/b"))
        let opaque = CommunityFeedRequest.userPostsPath(
            userId: "leo", types: nil, cursor: "Ab3-_xy", limit: 30)
        XCTAssertTrue(opaque.contains("cursor=Ab3-_xy"))
    }

    func testPostsPathOmitsToutAndCapsTheLimit() {
        let tout = CommunityFeedRequest.userPostsPath(userId: "leo", types: "", cursor: nil, limit: 80)
        XCTAssertFalse(tout.contains("types="))
        XCTAssertTrue(tout.contains("limit=50"))
        XCTAssertTrue(tout.hasPrefix("/api/v1/community/users/leo/posts?"))
        let fallback = CommunityFeedRequest.userPostsPath(userId: "leo", types: "yoga", cursor: nil, limit: 0)
        XCTAssertFalse(fallback.contains("types="))
        XCTAssertTrue(fallback.contains("limit=30"))
        let profile = CommunityFeedRequest.profilePath(userId: "leo id", types: "vely,meal")
        XCTAssertEqual(profile, "/api/v1/social?userId=leo%20id&types=meal,vely")
        XCTAssertEqual(CommunityFeedRequest.profilePath(userId: "leo", types: nil), "/api/v1/social?userId=leo")
        XCTAssertFalse(CommunityFeedRequest.profilePath(userId: "leo", types: "").contains("types="))
    }

    func testProfileJSON404IsMissingAndOtherFailuresCanRetry() {
        XCTAssertEqual(
            CommunityPersonLoad.message(for: CommunityPersonLoad.outcome(cancelled: false, profileNotFound: true)),
            "Profil introuvable")
        XCTAssertEqual(
            CommunityPersonLoad.message(for: CommunityPersonLoad.outcome(cancelled: false, profileNotFound: false)),
            "Le profil n’a pas pu être chargé.")
        XCTAssertNil(CommunityPersonLoad.message(for: CommunityPersonLoad.outcome(cancelled: true, profileNotFound: true)))
    }

    func testPagination404KeepsPostsAndASecondPageDedupes() {
        XCTAssertTrue(CommunityPersonPage.keepPostsAfterMissingRoute(appending: true, undeployed: true))
        XCTAssertFalse(CommunityPersonPage.keepPostsAfterMissingRoute(appending: false, undeployed: true))
        XCTAssertEqual(CommunityPersonPage.mergeIDs(["a", "b"], ["b", "c"]), ["a", "b", "c"])
    }

    func testSearchChoiceWaitsForASuccessfulSearch() {
        XCTAssertFalse(CommunitySearchApply.shouldApply(searchSucceeded: false))
        XCTAssertTrue(CommunitySearchApply.shouldApply(searchSucceeded: true))
    }

    func testClosingSearchClearsThePersonAndTheLists() {
        let state = CommunitySearchSessionReset.closed()
        XCTAssertEqual(state.query, "")
        XCTAssertNil(state.pickedUserId)
        XCTAssertTrue(state.users.isEmpty)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.personCleared)
    }
}
