import Foundation

public enum UpdateArchitecture: String { case arm64, x86_64 }

public struct UpdateCandidate: Equatable {
    public let version: CalVer
    public let releaseURL: URL
    public let archiveURL: URL
    public let appcastURL: URL
}

public enum UpdateCheck: Equatable {
    case noPublishedRelease
    case upToDate
    case available(UpdateCandidate)
}

public enum UpdateError: LocalizedError {
    case invalidInstalledVersion, invalidReleaseVersion, invalidReleaseURL, missingAssets, rateLimited, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidInstalledVersion: return "현재 앱의 버전 정보를 읽지 못했습니다."
        case .invalidReleaseVersion: return "GitHub Release가 CalVer 버전 형식이 아닙니다."
        case .invalidReleaseURL: return "공식 NonSleep 저장소의 업데이트 파일이 아닙니다."
        case .missingAssets: return "이 Mac용 업데이트 파일이나 설치 정보가 아직 준비되지 않았습니다. 잠시 후 다시 확인해 주세요."
        case .rateLimited: return "GitHub 요청 한도에 도달했습니다. 잠시 후 다시 확인해 주세요."
        case .http(let code): return "GitHub에 연결하지 못했습니다. (HTTP \(code))"
        }
    }
}

public struct GitHubRelease: Decodable {
    public struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int
        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public func update(installedVersion: String, architecture: UpdateArchitecture) throws -> UpdateCheck {
        guard !draft, !prerelease else { return .upToDate }
        guard let version = CalVer(tagName), tagName == "v\(version)", version.prerelease == nil else { throw UpdateError.invalidReleaseVersion }
        guard try version.isNewer(than: installedVersion) else { return .upToDate }
        let base = "https://github.com/mars2cbh/NonSleep/releases"
        guard htmlURL.absoluteString == "\(base)/tag/\(tagName)" else { throw UpdateError.invalidReleaseURL }
        let archiveName = "NonSleep-\(version)-macos-\(architecture.rawValue).zip"
        let appcastName = "appcast-\(architecture.rawValue).xml"
        guard let archive = assets.first(where: { $0.name == archiveName && $0.size > 0 }),
              let appcast = assets.first(where: { $0.name == appcastName && $0.size > 0 }) else { throw UpdateError.missingAssets }
        for asset in [archive, appcast] {
            guard asset.browserDownloadURL.absoluteString == "\(base)/download/\(tagName)/\(asset.name)" else {
                throw UpdateError.invalidReleaseURL
            }
        }
        return .available(UpdateCandidate(version: version, releaseURL: htmlURL,
            archiveURL: archive.browserDownloadURL, appcastURL: appcast.browserDownloadURL))
    }
}

public protocol ReleaseTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionReleaseTransport: ReleaseTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.http(0) }
        return (data, http)
    }
}

public struct GitHubUpdateClient {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/mars2cbh/NonSleep/releases/latest")!
    private let transport: any ReleaseTransport
    public init(transport: any ReleaseTransport = URLSessionReleaseTransport()) { self.transport = transport }

    public func check(installedVersion: String, architecture: UpdateArchitecture) async throws -> UpdateCheck {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NonSleep/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 404 { return .noPublishedRelease }
        if response.statusCode == 429 || (response.statusCode == 403 && response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
            throw UpdateError.rateLimited
        }
        guard response.statusCode == 200 else { throw UpdateError.http(response.statusCode) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data).update(installedVersion: installedVersion, architecture: architecture)
    }
}
