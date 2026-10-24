import XCTest
@testable import WhoopProtocol

final class CommunityFeedFilterTests: XCTestCase {
    func testToutIsTheDefaultAndTheFullSet() {
        let tout = CommunityFeedSelection.decode(nil)
        XCTAssertTrue(tout.showsEverything)
        XCTAssertNil(tout.typesQuery)
        XCTAssertEqual(CommunityFeedSelection.decode("").showsEverything, true)
        XCTAssertEqual(CommunityFeedSelection.decode("meal,barcode,muscy,coursy,vely").showsEverything, true)
        XCTAssertEqual(CommunityFeedRequest.socialPath(types: nil), "/api/v1/social")
    }

    func testSelectingOneLeavesToutAndTheLastRemovalReturns() {
        let meal = CommunityFeedSelection().toggling(.meal)
        XCTAssertEqual(meal.kinds, [.meal])
        XCTAssertEqual(meal.typesQuery, "meal")
        XCTAssertTrue(meal.toggling(.meal).showsEverything)
    }

    func testSeveralTypesStayAndAllOfThemEqualsTout() {
        let two = CommunityFeedSelection(kinds: [.meal]).toggling(.coursy)
        XCTAssertEqual(two.stored, "meal,coursy")
        XCTAssertEqual(CommunityFeedRequest.socialPath(types: two.typesQuery), "/api/v1/social?types=meal,coursy")
        var all = CommunityFeedSelection()
        for kind in CommunityPostKind.allCases {
            all = all.toggling(kind)
        }
        XCTAssertTrue(all.showsEverything)
        XCTAssertNil(all.typesQuery)
    }

    func testUnknownStoredValueFallsBackToTout() {
        XCTAssertTrue(CommunityFeedSelection.decode("meal,legacy").showsEverything)
        XCTAssertTrue(CommunityFeedSelection.decode("[\"nope\"]").showsEverything)
        XCTAssertEqual(CommunityFeedSelection.decode("[\"barcode\",\"vely\"]").kinds, [.barcode, .vely])
    }

    func testLocalFilterKeepsOnlyTheChosenKinds() {
        let meal = CommunityFeedSelection(kinds: [.meal, .vely])
        XCTAssertTrue(meal.includes(.meal))
        XCTAssertTrue(meal.includes(.vely))
        XCTAssertFalse(meal.includes(.muscy))
        XCTAssertFalse(meal.includes(.barcode))
        XCTAssertFalse(meal.includes(.coursy))
        XCTAssertTrue(CommunityFeedSelection().includes(.muscy))
    }
}
