import XCTest
@testable import WhoopProtocol

final class CommunityErrorRoutingTests: XCTestCase {
    func testSearchCancellationDoesNotLookLikeAComment() {
        XCTAssertTrue(CommunityErrorRouting.isCancellation(CancellationError()))
        XCTAssertTrue(CommunityErrorRouting.isCancellation(URLError(.cancelled)))
        XCTAssertNil(CommunityErrorRouting.searchNotice(cancelled: true, failed: true))
        XCTAssertNil(CommunityErrorRouting.commentAlert(cancelled: true, failed: true))
        XCTAssertNotEqual(
            CommunityErrorRouting.searchNotice(cancelled: false, failed: true),
            CommunityErrorRouting.commentMessage)
    }

    func testSearchTimeoutIsItsOwnMessage() {
        XCTAssertFalse(CommunityErrorRouting.isCancellation(URLError(.timedOut)))
        XCTAssertEqual(
            CommunityErrorRouting.searchNotice(cancelled: false, failed: true),
            CommunityErrorRouting.searchMessage)
        XCTAssertNil(CommunityErrorRouting.commentAlert(cancelled: false, failed: false))
    }

    func testCommentPostFailureShowsTheMessage() {
        XCTAssertEqual(
            CommunityErrorRouting.commentAlert(cancelled: false, failed: true),
            CommunityErrorRouting.commentMessage)
    }

    func testCommentCancellationStaysQuiet() {
        XCTAssertNil(CommunityErrorRouting.commentAlert(cancelled: true, failed: true))
        XCTAssertNil(CommunityErrorRouting.commentAlert(cancelled: false, failed: false))
    }
}
