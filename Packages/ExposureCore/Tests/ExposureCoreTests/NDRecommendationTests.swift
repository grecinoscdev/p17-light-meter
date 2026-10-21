import XCTest
@testable import ExposureCore

final class NDRecommendationTests: XCTestCase {
    private func recommend(ev: Double = 15, iso: Int = 100, ec: Double = 0,
                           mode: ExposureMode = .bokeh, inventory: [NDFilter] = NDFilter.catalog,
                           selected: NDFilter? = nil, uncertainty: Double? = nil) throws -> NDRecommendation {
        try NDRecommendationEngine.recommend(
            sceneEV100: ev,
            configuration: ExposureConfiguration(cameraISO: iso, exposureCompensationEV: ec, mode: mode),
            inventory: inventory, selectedFilter: selected, uncertaintyEV: uncertainty
        )
    }

    private func candidate(_ result: NDRecommendation, file: StaticString = #filePath, line: UInt = #line) throws -> FilterAssessment {
        guard case let .candidate(candidate) = result.recommendation else {
            XCTFail("Expected a nominal candidate", file: file, line: line)
            throw ExposureError.unrepresentableExposure
        }
        return candidate
    }

    func testCatalogFactorsAndFractionalCustomFilters() throws {
        XCTAssertEqual(NDFilter.catalog.map(\.stops), [0, 1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(NDFilter.catalog.map(\.standardLabel), ["None", "ND2", "ND4", "ND8", "ND16", "ND32", "ND64", "ND128", "ND256"])
        XCTAssertEqual(NDFilter.catalog[3].factor, 8)
        let fractional = try NDFilter(id: "custom", stops: 2.5)
        XCTAssertNil(fractional.standardLabel)
        XCTAssertEqual(fractional.factor, 5.656854249492381, accuracy: 1e-12)
    }

    func testGoldenBokehAndProgramRecommendations() throws {
        for (ev, iso, expectedStops) in [(15.0, 100, 3.0), (15, 400, 5), (13, 100, 1), (8, 100, 0)] {
            XCTAssertEqual(try candidate(recommend(ev: ev, iso: iso)).filter.stops, expectedStops)
        }
        let program = try recommend(mode: .program(targetAperture: 8))
        XCTAssertEqual(program.exactMinimumStops, 0.5487888881676712, accuracy: 1e-12)
        XCTAssertEqual(program.upwardThirdStopMinimum, 2.0 / 3)
        XCTAssertEqual(try candidate(program).filter.stops, 1)
        XCTAssertEqual(try candidate(program).exposure.target.shutterSeconds, 1.0 / 256)
        XCTAssertEqual(try candidate(recommend(iso: 400, mode: .program(targetAperture: 8))).filter.stops, 3)
    }

    func testDialChangesNeverOptimizeISOAndPositiveECReducesND() throws {
        let base = try recommend()
        XCTAssertEqual(try recommend(iso: 400).exactMinimumStops - base.exactMinimumStops, 2, accuracy: 1e-12)
        XCTAssertEqual(try recommend(ec: 1).exactMinimumStops, base.exactMinimumStops - 1, accuracy: 1e-12)
        XCTAssertEqual(try candidate(recommend(ec: 1)).filter.stops, 2)
    }

    func testThirdStopRoundingAbsorbsOnlyNumericNoise() throws {
        XCTAssertEqual(try NDRounding.upwardThirdStops(0), 0)
        XCTAssertEqual(try NDRounding.upwardThirdStops(3.0000000000000004), 3)
        XCTAssertEqual(try NDRounding.upwardThirdStops(3 - 1e-8), 3)
        XCTAssertEqual(try NDRounding.upwardThirdStops(3 + 1e-8), 10.0 / 3)
        XCTAssertEqual(try NDRounding.upwardThirdStops(1.0 / 3), 1.0 / 3)
        XCTAssertThrowsError(try NDRounding.upwardThirdStops(-1))
        XCTAssertThrowsError(try NDRounding.upwardThirdStops(.nan))
        XCTAssertThrowsError(try NDRounding.upwardThirdStops(.greatestFiniteMagnitude))
    }

    func testInventorySelectionUsesExactMinimumNotRoundedDisplay() throws {
        let exact = try NDFilter(id: "fractional", stops: 2.95)
        let result = try recommend(inventory: [NDFilter.catalog[4], exact, NDFilter.catalog[3]])
        XCTAssertEqual(result.upwardThirdStopMinimum, 3)
        XCTAssertEqual(try candidate(result).filter, exact)
        XCTAssertEqual(try candidate(result).headroomStops, 0.015920955947537, accuracy: 1e-12)
    }

    func testExactFilterBoundaryAndNearbyScenes() throws {
        let ev = 15.065920955947537 // f/3.5 fast boundary plus exactly three ND stops.
        XCTAssertEqual(try candidate(recommend(ev: ev)).filter.stops, 3)
        XCTAssertEqual(try candidate(recommend(ev: ev - 1e-8)).filter.stops, 3)
        XCTAssertEqual(try candidate(recommend(ev: ev + 1e-8)).filter.stops, 4)
    }

    func testMissingInadequateAndExcessiveInventoriesExplainFailure() throws {
        let empty = try recommend(inventory: [])
        XCTAssertEqual(empty.recommendation, .noMatch(.emptyInventory))
        XCTAssertEqual(empty.exactMinimumStops, 2.934079044052463, accuracy: 1e-12)
        XCTAssertEqual(try recommend(inventory: [NDFilter.catalog[2]]).recommendation, .noMatch(.insufficientAttenuation))
        XCTAssertEqual(try recommend(ev: 0).recommendation, .noMatch(.exposuresTooSlow))
        let excessive = try NDFilter(id: "dense", stops: 20)
        XCTAssertEqual(try recommend(inventory: [excessive]).recommendation, .noMatch(.exposuresTooSlow))
        XCTAssertEqual(try recommend(inventory: [NDFilter.catalog[2], excessive]).recommendation,
                       .noMatch(.inventorySkipsFeasibleRange))
    }

    func testSelectedFilterDoesNotReplaceRecommendationOrHideItsFailure() throws {
        let selected = NDFilter.catalog[1]
        let result = try recommend(selected: selected)
        XCTAssertEqual(try candidate(result).filter.stops, 3)
        XCTAssertEqual(result.selected?.filter, selected)
        XCTAssertEqual(result.selected?.exposure.target.range, .fasterThanShutterLimit)
        XCTAssertEqual(result.selected?.isTargetPhysicallyFeasible, false)
        XCTAssertNil(try recommend().selected) // Returning to automatic clears manual comparison.
        let outsideInventory = try NDFilter(id: "manual", stops: 4.5)
        XCTAssertEqual(try recommend(inventory: [], selected: outsideInventory).selected?.filter, outsideInventory)
    }

    func testUnknownUncertaintyStaysUnknownAndNoSafetyStopIsAdded() throws {
        let unknown = try recommend()
        XCTAssertNil(try candidate(unknown).crossesFastBoundary)
        XCTAssertNil(unknown.strongerAlternative)
        let uncertain = try recommend(uncertainty: 0.2)
        XCTAssertEqual(try candidate(uncertain).filter.stops, 3)
        XCTAssertEqual(try candidate(uncertain).crossesFastBoundary, true)
        XCTAssertEqual(uncertain.strongerAlternative?.filter.stops, 4)
        XCTAssertEqual(try XCTUnwrap(uncertain.strongerAlternative).exposure.target.shutterSeconds,
                       try candidate(uncertain).exposure.target.shutterSeconds * 2, accuracy: 1e-12)
        XCTAssertEqual(try candidate(recommend(uncertainty: 0)).crossesFastBoundary, false)
    }

    func testUncertaintyCanCrossSlowLimitAndRuleOutStrongerAlternative() throws {
        let slow = try recommend(ev: 4, mode: .program(targetAperture: 8), uncertainty: 0.1)
        XCTAssertEqual(try candidate(slow).crossesSlowBoundary, true)
        // Wide enough interval that every stronger filter fails the dim endpoint.
        let wideInterval = try recommend(uncertainty: 6)
        XCTAssertTrue(try candidate(wideInterval).crossesFastBoundary == true)
        XCTAssertNil(wideInterval.strongerAlternative)
    }

    func testInvalidFilterInventoryAndUncertaintyAreRejected() throws {
        for stops in [-1, Double.nan, .infinity, 1024] {
            XCTAssertThrowsError(try NDFilter(id: "bad", stops: stops))
        }
        XCTAssertThrowsError(try NDFilter(id: "  ", stops: 1))
        XCTAssertThrowsError(try recommend(inventory: [NDFilter.catalog[3], NDFilter.catalog[3]])) {
            XCTAssertEqual($0 as? ExposureError, .duplicateFilterIdentifier)
        }
        for uncertainty in [-1, Double.nan, .infinity] {
            XCTAssertThrowsError(try recommend(uncertainty: uncertainty)) {
                XCTAssertEqual($0 as? ExposureError, .invalidUncertainty)
            }
        }
    }

    func testEqualStopFiltersHaveDeterministicSelection() throws {
        let first = try NDFilter(id: "a", stops: 3)
        let second = try NDFilter(id: "b", stops: 3)
        XCTAssertEqual(try candidate(recommend(inventory: [second, first])).filter, first)
        XCTAssertEqual(try candidate(recommend(inventory: [first, second])).filter, first)
    }
}
