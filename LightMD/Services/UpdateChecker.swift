import Foundation
import AppKit

// MARK: - GitHub API Models

struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let assets: [Asset]

    struct Asset: Codable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }

    var zipAssetUrl: String? {
        assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadUrl
    }
}

// MARK: - UpdateChecker

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestRelease: GitHubRelease?
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var errorMessage: String?

    private static let owner = "matsuura-satoshi"
    private static let repo = "light-md"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Version Comparison

    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = parseVersion(remote)
        let localParts = parseVersion(local)

        guard remoteParts.count == 3, localParts.count == 3 else { return false }

        for i in 0..<3 {
            if remoteParts[i] > localParts[i] { return true }
            if remoteParts[i] < localParts[i] { return false }
        }
        return false
    }

    private nonisolated static func parseVersion(_ version: String) -> [Int] {
        let stripped = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return stripped.split(separator: ".").compactMap { Int($0) }
    }

    // MARK: - Check for Updates

    func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            if Self.isNewer(release.tagName, than: currentVersion) {
                latestRelease = release
                updateAvailable = true
            } else {
                updateAvailable = false
                latestRelease = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpdateError.apiError
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: - Download and Install

    func downloadAndInstall() async {
        guard let release = latestRelease,
              let zipUrlString = release.zipAssetUrl,
              let zipUrl = URL(string: zipUrlString) else {
            errorMessage = "No download URL available"
            return
        }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("LightMDUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Download zip
            let (localUrl, _) = try await URLSession.shared.download(from: zipUrl)
            let zipPath = tempDir.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: localUrl, to: zipPath)
            downloadProgress = 0.5

            // Extract zip
            let extractDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = ["-xk", zipPath.path, extractDir.path]
            try dittoProcess.run()
            dittoProcess.waitUntilExit()

            guard dittoProcess.terminationStatus == 0 else {
                throw UpdateError.extractionFailed
            }
            downloadProgress = 0.7

            // Find .app bundle
            let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.noAppBundle
            }

            // Remove quarantine attribute
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-dr", "com.apple.quarantine", appBundle.path]
            try xattrProcess.run()
            xattrProcess.waitUntilExit()
            downloadProgress = 0.8

            // Replace current app
            let currentAppUrl = Bundle.main.bundleURL
            try await NSWorkspace.shared.recycle([currentAppUrl])
            downloadProgress = 0.9

            try FileManager.default.copyItem(at: appBundle, to: currentAppUrl)
            downloadProgress = 1.0

            // Relaunch
            let openProcess = Process()
            openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProcess.arguments = [currentAppUrl.path]
            try openProcess.run()

            NSApplication.shared.terminate(nil)
        } catch {
            isDownloading = false
            errorMessage = "Update failed: \(error.localizedDescription)"
            openReleasePage()
        }
    }

    func openReleasePage() {
        if let release = latestRelease, let url = URL(string: release.htmlUrl) {
            NSWorkspace.shared.open(url)
        } else {
            let urlString = "https://github.com/\(Self.owner)/\(Self.repo)/releases/latest"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Errors

    enum UpdateError: LocalizedError {
        case invalidUrl
        case apiError
        case extractionFailed
        case noAppBundle

        var errorDescription: String? {
            switch self {
            case .invalidUrl: return "Invalid API URL"
            case .apiError: return "Failed to fetch release information"
            case .extractionFailed: return "Failed to extract update"
            case .noAppBundle: return "No app bundle found in update"
            }
        }
    }
}
