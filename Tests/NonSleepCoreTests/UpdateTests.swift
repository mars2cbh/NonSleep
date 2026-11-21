import XCTest
@testable import NonSleepCore

final class UpdateTests: XCTestCase {
    func testCalendarDatesAndCanonicalFormatting() throws {
        XCTAssertEqual(CalVer("v2026.11.21.2")?.description, "2026.11.21.2")
        XCTAssertEqual(CalVer("2026.11.21.2")?.appVersion, "2026.11.21")
        XCTAssertNotNil(CalVer("2028.02.29"))
        for invalid in ["2026.02.29", "2026.04.31", "2026.13.01", "2026.1.01", "2026.11.21.0", "2026.11.21.01", "2026.11.21-beta.", "2026.11.21-beta-", "0.2.0", "2026.11.21/evil"] {
            XCTAssertNil(CalVer(invalid), invalid)
        }
    }

    func testOrderingRevisionPrereleaseAndLegacyMigration() throws {
        let versions = ["2026.11.20", "2026.11.21-beta.2", "2026.11.21-beta.10", "2026.11.21", "2026.11.21.1", "2026.12.01", "2027.01.01"]
        for (before, after) in zip(versions, versions.dropFirst()) {
            XCTAssertTrue(try XCTUnwrap(CalVer(after)).isNewer(than: before))
            XCTAssertFalse(try XCTUnwrap(CalVer(before)).isNewer(than: after))
        }
        let latest = try XCTUnwrap(CalVer("2026.11.21"))
        XCTAssertFalse(try latest.isNewer(than: "2026.11.21"))
        XCTAssertTrue(try latest.isNewer(than: "0.2.0"))
        XCTAssertThrowsError(try latest.isNewer(than: "unknown"))
    }

    func testSelectsMatchingArchitectureAndRevision() throws {
        let release = try fixture()
        for arch in [UpdateArchitecture.arm64, .x86_64] {
            guard case .available(let candidate) = try release.update(installedVersion: "2026.11.21", architecture: arch) else {
                return XCTFail("Expected newer same-day release")
            }
            XCTAssertTrue(candidate.archiveURL.lastPathComponent.hasSuffix("macos-\(arch.rawValue).zip"))
            XCTAssertEqual(candidate.appcastURL.lastPathComponent, "appcast-\(arch.rawValue).xml")
        }
        XCTAssertEqual(try release.update(installedVersion: "2026.11.21.1", architecture: .arm64), .upToDate)
        XCTAssertEqual(try release.update(installedVersion: "2026.11.22", architecture: .arm64), .upToDate)
    }

    func testDraftPrereleaseMissingAssetsAndForeignDownloads() throws {
        for key in ["draft", "prerelease"] {
            XCTAssertEqual(try fixture(change: { $0[key] = true }).update(installedVersion: "0.2.0", architecture: .arm64), .upToDate)
        }
        XCTAssertThrowsError(try fixture(change: { $0["tag_name"] = "v0.3.0" }).update(installedVersion: "0.2.0", architecture: .arm64))
        XCTAssertThrowsError(try fixture(change: { $0["tag_name"] = "v2026.11.21-beta.1" }).update(installedVersion: "0.2.0", architecture: .arm64))
        XCTAssertThrowsError(try fixture(change: { $0["assets"] = [] }).update(installedVersion: "0.2.0", architecture: .arm64))
        for badURL in ["https://evil.example/file.zip", "http://github.com/mars2cbh/NonSleep/releases/download/v2026.11.21.1/NonSleep-2026.11.21.1-macos-arm64.zip"] {
            let release = try fixture { json in
                var assets = json["assets"] as! [[String: Any]]
                assets[0]["browser_download_url"] = badURL
                json["assets"] = assets
            }
            XCTAssertThrowsError(try release.update(installedVersion: "0.2.0", architecture: .arm64))
        }
    }

    func testGitHubResponseHandlingAndFixedEndpoint() async throws {
        let noRelease = GitHubUpdateClient(transport: StubTransport(status: 404))
        let result = try await noRelease.check(installedVersion: "2026.11.21", architecture: .arm64)
        XCTAssertEqual(result, .noPublishedRelease)
        for status in [403, 429, 500] {
            do {
                _ = try await GitHubUpdateClient(transport: StubTransport(status: status))
                    .check(installedVersion: "2026.11.21", architecture: .arm64)
                XCTFail("HTTP \(status) must fail")
            } catch let error as UpdateError {
                if status == 500 { guard case .http(500) = error else { return XCTFail() } }
                else { guard case .rateLimited = error else { return XCTFail() } }
            }
        }
        let available = try await GitHubUpdateClient(transport: StubTransport(status: 200, body: fixtureData()))
            .check(installedVersion: "0.2.0", architecture: .arm64)
        guard case .available = available else { return XCTFail("Expected available update") }
        do {
            _ = try await GitHubUpdateClient(transport: StubTransport(status: 200, body: Data("invalid".utf8)))
                .check(installedVersion: "0.2.0", architecture: .arm64)
            XCTFail("Malformed metadata must fail")
        } catch is DecodingError {}
    }

    private func fixture(change: (inout [String: Any]) -> Void = { _ in }) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: fixtureData(change: change))
    }

    private func fixtureData(change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        let version = "2026.11.21.1", tag = "v2026.11.21.1"
        let files = ["NonSleep-\(version)-macos-arm64.zip", "appcast-arm64.xml", "NonSleep-\(version)-macos-x86_64.zip", "appcast-x86_64.xml"]
        var json: [String: Any] = ["tag_name": tag, "html_url": "https://github.com/mars2cbh/NonSleep/releases/tag/\(tag)",
            "draft": false, "prerelease": false, "assets": files.map {
                ["name": $0, "size": 1024, "browser_download_url": "https://github.com/mars2cbh/NonSleep/releases/download/\(tag)/\($0)"] as [String: Any]
            }]
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
}

private struct StubTransport: ReleaseTransport {
    let status: Int
    var body = Data()
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        XCTAssertEqual(request.url, GitHubUpdateClient.latestReleaseURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["X-RateLimit-Remaining": "0"])!)
    }
}
