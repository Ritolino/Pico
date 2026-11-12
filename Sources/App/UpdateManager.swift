import AppKit
import CommonCrypto
import Foundation

struct UpdateReleaseInfo: Codable, Equatable {
    let version: String
    let tagName: String
    let htmlURL: String
    let downloadURL: String
    let sha256: String
    let notes: String
}

enum UpdateSemVer {
    /// Parses a semantic version string (e.g. "v1.2.0" or "1.2") into (major, minor, patch).
    /// Returns nil if it contains prerelease suffixes (e.g. "-beta", "-rc") or non-numeric parts.
    static func parse(_ raw: String) -> (Int, Int, Int)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        if s.contains("-") || s.contains("+") || s.isEmpty {
            return nil
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]), major >= 0, minor >= 0 else {
            return nil
        }
        let patch: Int
        if parts.count == 3 {
            guard let p = Int(parts[2]), p >= 0 else { return nil }
            patch = p
        } else {
            patch = 0
        }
        return (major, minor, patch)
    }

    static func normalized(_ raw: String) -> String? {
        guard let v = parse(raw) else { return nil }
        return "\(v.0).\(v.1).\(v.2)"
    }

    static func isRemoteNewer(remote: String, current: String) -> Bool {
        guard let r = parse(remote), let c = parse(current) else { return false }
        return r > c
    }
}

final class UpdateManager {
    static let latestReleaseAPI = "https://api.github.com/repos/Ritolino/Pico/releases/latest"
    static let expectedBundleID = "local.gabriele.pico"

    static let lastCheckTimestampKey = "PicoLastUpdateCheckTimestamp"
    static let skippedVersionKey = "PicoSkippedUpdateVersion"
    static let disableAutoUpdateKey = "PicoDisableAutoUpdate"

    private static let initialLaunchDelay: TimeInterval = 15.0
    private static let wakeDelay: TimeInterval = 5.0
    private static let checkCooldown: TimeInterval = 24.0 * 60.0 * 60.0
    private static let maxDownloadBytes: Int64 = 50 * 1024 * 1024

    var onUpdateStateChanged: ((UpdateReleaseInfo?, Bool) -> Void)?

    private(set) var availableUpdate: UpdateReleaseInfo?
    private var isChecking = false
    private var isDownloading = false
    private var pendingWorkItem: DispatchWorkItem?

    static var currentAppVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var isAutoUpdateDisabled: Bool {
        if CommandLine.arguments.contains("--no-update-check") {
            return true
        }
        return UserDefaults.standard.bool(forKey: disableAutoUpdateKey)
    }

    // MARK: - Scheduling (Zero Periodic Timers)

    func scheduleInitialCheckIfAllowed() {
        guard !Self.isAutoUpdateDisabled else { return }
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.triggerBackgroundCheck()
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialLaunchDelay, execute: work)
    }

    func scheduleWakeCheckIfDue() {
        guard !Self.isAutoUpdateDisabled else { return }
        let lastCheck = UserDefaults.standard.double(forKey: Self.lastCheckTimestampKey)
        let elapsed = Date().timeIntervalSince1970 - lastCheck
        guard lastCheck <= 0 || elapsed >= Self.checkCooldown else { return }

        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.triggerBackgroundCheck()
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeDelay, execute: work)
    }

    func cancelPendingChecks() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    func setSimulatedUpdate(version: String) {
        let info = UpdateReleaseInfo(
            version: version,
            tagName: "v\(version)",
            htmlURL: "https://github.com/Ritolino/Pico/releases",
            downloadURL: "https://github.com/Ritolino/Pico/releases/download/v\(version)/Pico-v\(version)-macOS.zip",
            sha256: "",
            notes: "Simulated release notes for UI and alert verification."
        )
        availableUpdate = info
        onUpdateStateChanged?(info, false)
    }

    // MARK: - Ephemeral Background Check

    private func triggerBackgroundCheck() {
        guard !isChecking, !isDownloading else { return }
        guard let executableURL = Bundle.main.executableURL else { return }
        isChecking = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let proc = Process()
            proc.executableURL = executableURL
            proc.arguments = ["--internal-update-check"]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = FileHandle.nullDevice

            var parsedRelease: UpdateReleaseInfo?
            var checkSucceeded = false

            do {
                try proc.run()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0, !data.isEmpty {
                    checkSucceeded = true
                    if let decoded = try? JSONDecoder().decode(CheckWorkerOutput.self, from: data),
                       decoded.status == "update_available",
                       let release = decoded.release {
                        parsedRelease = release
                    }
                }
            } catch {
                checkSucceeded = false
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false

                if checkSucceeded {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckTimestampKey)
                }

                if let release = parsedRelease, Self.shouldOfferUpdate(release) {
                    self.availableUpdate = release
                    self.onUpdateStateChanged?(release, false)
                } else if checkSucceeded {
                    self.availableUpdate = nil
                    self.onUpdateStateChanged?(nil, false)
                }
            }
        }
    }

    private static func shouldOfferUpdate(_ release: UpdateReleaseInfo) -> Bool {
        guard UpdateSemVer.isRemoteNewer(remote: release.version, current: currentAppVersion) else {
            return false
        }
        if let skipped = UserDefaults.standard.string(forKey: skippedVersionKey),
           UpdateSemVer.normalized(skipped) == UpdateSemVer.normalized(release.version) {
            return false
        }
        return true
    }

    // MARK: - User Interaction & Atomic Update Flow

    func presentUpdatePrompt() {
        guard let release = availableUpdate, !isDownloading else { return }

        NSApp.activate(ignoringOtherApps: true)

        let bundleURL = Bundle.main.bundleURL
        let canAutoReplace = Self.canAutoReplaceBundle(at: bundleURL)

        if !canAutoReplace {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Update Available: Pico v\(release.version)"
            alert.informativeText = "You are currently running v\(Self.currentAppVersion).\n\nMove Pico.app into /Applications to enable automatic 1-click updates, or download the latest release directly from GitHub."
            alert.addButton(withTitle: "Open GitHub Release")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: release.htmlURL) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Available: Pico v\(release.version)"
        let cleanNotes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesBlock = cleanNotes.isEmpty ? "Bug fixes and improvements." : cleanNotes
        alert.informativeText = "You are currently running v\(Self.currentAppVersion).\n\nRelease notes:\n\(notesBlock)"
        alert.addButton(withTitle: "Update & Restart")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            startDownloadAndInstall(release: release, targetAppURL: bundleURL)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
            availableUpdate = nil
            onUpdateStateChanged?(nil, false)
        default:
            break
        }
    }

    static func canAutoReplaceBundle(at bundleURL: URL) -> Bool {
        let path = bundleURL.path
        let userApps = NSHomeDirectory() + "/Applications/"
        guard path.hasPrefix("/Applications/") || path.hasPrefix(userApps) else {
            return false
        }
        let parentPath = bundleURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parentPath)
            && FileManager.default.isWritableFile(atPath: path)
    }

    private func startDownloadAndInstall(release: UpdateReleaseInfo, targetAppURL: URL) {
        guard let executableURL = Bundle.main.executableURL else { return }

        isDownloading = true
        onUpdateStateChanged?(release, true)

        let stagingRoot = "/tmp/pico-update-\(UUID().uuidString)"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let proc = Process()
            proc.executableURL = executableURL
            proc.arguments = [
                "--internal-update-download",
                release.downloadURL,
                release.sha256,
                stagingRoot
            ]
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            var stagedAppPath: String?
            var errorMessage = "Unable to download or verify the update package."

            do {
                try proc.run()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()

                if proc.terminationStatus == 0,
                   let path = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    stagedAppPath = path
                } else if let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !errStr.isEmpty {
                    errorMessage = errStr
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            DispatchQueue.main.async {
                guard let self else { return }
                if let stagedPath = stagedAppPath {
                    LoginItemManager.markRestoreNeededAfterUpdateIfEnabled()
                    UserDefaults.standard.removeObject(forKey: Self.skippedVersionKey)
                    Self.launchSwapHelperAndTerminate(
                        stagedAppPath: stagedPath,
                        stagingRoot: stagingRoot,
                        targetAppPath: targetAppURL.path
                    )
                } else {
                    try? FileManager.default.removeItem(atPath: stagingRoot)
                    self.isDownloading = false
                    self.onUpdateStateChanged?(release, false)
                    self.showUpdateErrorAlert(message: errorMessage, releaseURL: release.htmlURL)
                }
            }
        }
    }

    private func showUpdateErrorAlert(message: String, releaseURL: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update Failed"
        alert.informativeText = "\(message)\n\nYour current version of Pico was not modified."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub Release")
        if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }

    static func launchSwapHelperAndTerminate(stagedAppPath: String, stagingRoot: String, targetAppPath: String) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let script = """
        OLD_PID="$1"
        STAGED_APP="$2"
        STAGING_ROOT="$3"
        TARGET_APP="$4"
        BACKUP_APP="${STAGING_ROOT}/Pico.old.app"
        LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

        i=0
        while kill -0 "$OLD_PID" 2>/dev/null && [ "$i" -lt 50 ]; do
            sleep 0.2
            i=$((i + 1))
        done

        if [ -e "$TARGET_APP" ]; then
            if ! mv "$TARGET_APP" "$BACKUP_APP"; then
                rm -rf "$STAGING_ROOT"
                exit 1
            fi
        fi

        if ! mv "$STAGED_APP" "$TARGET_APP"; then
            if [ -e "$BACKUP_APP" ]; then
                mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
            fi
            rm -rf "$STAGING_ROOT"
            exit 1
        fi

        if [ -x "$LSREG" ]; then
            "$LSREG" -u "$STAGED_APP" 2>/dev/null || true
            "$LSREG" -f "$TARGET_APP" 2>/dev/null || true
        fi

        rm -rf "$STAGING_ROOT"
        /usr/bin/open "$TARGET_APP"
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script, "pico-updater", "\(currentPID)", stagedAppPath, stagingRoot, targetAppPath]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(atPath: stagingRoot)
        }
    }

    // MARK: - Ephemeral CLI Workers (No AppKit / Zero Resident RAM Impact)

    private struct GitHubReleaseResponse: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
        let digest: String?
        let size: Int64?
    }

    private struct CheckWorkerOutput: Codable {
        let status: String
        let release: UpdateReleaseInfo?
    }

    static func isTrustedGitHubURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com"
            || host == "api.github.com"
            || host.hasSuffix(".githubusercontent.com")
    }

    static func sha256Hex(fileAt path: String) -> String? {
        guard let stream = InputStream(fileAtPath: path) else { return nil }
        stream.open()
        defer { stream.close() }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        let bufferSize = 65_536
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: bufferSize)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            _ = buffer.withUnsafeBytes { rawBuf in
                CC_SHA256_Update(&context, rawBuf.baseAddress, CC_LONG(readCount))
            }
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func parseGitHubReleaseJSON(_ data: Data, currentVersion: String) -> UpdateReleaseInfo? {
        guard let decoded = try? JSONDecoder().decode(GitHubReleaseResponse.self, from: data) else {
            return nil
        }
        if decoded.draft == true || decoded.prerelease == true {
            return nil
        }
        guard let remoteNorm = UpdateSemVer.normalized(decoded.tag_name),
              UpdateSemVer.isRemoteNewer(remote: remoteNorm, current: currentVersion) else {
            return nil
        }
        let zipAssets = decoded.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard let asset = zipAssets.first(where: { $0.name.contains("macOS") }) ?? zipAssets.first,
              isTrustedGitHubURL(asset.browser_download_url),
              isTrustedGitHubURL(decoded.html_url) else {
            return nil
        }
        if let size = asset.size, size > maxDownloadBytes {
            return nil
        }

        var sha = asset.digest ?? ""
        if sha.lowercased().hasPrefix("sha256:") {
            sha = String(sha.dropFirst("sha256:".count))
        }

        let rawBody = decoded.body ?? ""
        let trimmedNotes = rawBody.count > 600 ? String(rawBody.prefix(597)) + "…" : rawBody

        return UpdateReleaseInfo(
            version: remoteNorm,
            tagName: decoded.tag_name,
            htmlURL: decoded.html_url,
            downloadURL: asset.browser_download_url,
            sha256: sha.lowercased(),
            notes: trimmedNotes
        )
    }

    static func runInternalUpdateCheckCLI() -> Int32 {
        guard let url = URL(string: latestReleaseAPI) else { return 1 }

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url)
        req.setValue("Pico/\(currentAppVersion) (macOS; arm64)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var statusCode = 0

        let task = session.dataTask(with: req) { data, response, error in
            if error == nil, let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
                resultData = data
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 16.0)

        guard statusCode == 200, let data = resultData else {
            return 1
        }

        let output: CheckWorkerOutput
        if let release = parseGitHubReleaseJSON(data, currentVersion: currentAppVersion) {
            output = CheckWorkerOutput(status: "update_available", release: release)
        } else {
            output = CheckWorkerOutput(status: "up_to_date", release: nil)
        }

        if let jsonData = try? JSONEncoder().encode(output),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            print(jsonStr)
            return 0
        }
        return 1
    }

    static func runInternalUpdateDownloadCLI(downloadURLString: String, expectedSha256: String, stagingRoot: String) -> Int32 {
        guard isTrustedGitHubURL(downloadURLString), let url = URL(string: downloadURLString) else {
            fputs("Untrusted download URL.\n", stderr)
            return 1
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: stagingRoot, withIntermediateDirectories: true)
            fm.createFile(atPath: "\(stagingRoot)/.metadata_never_index", contents: Data())
        } catch {
            fputs("Failed to create staging directory.\n", stderr)
            return 1
        }

        let zipPath = "\(stagingRoot)/Pico.zip"
        let extractedDir = "\(stagingRoot)/extracted"

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url)
        req.setValue("Pico/\(currentAppVersion) (macOS; arm64)", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var downloadOK = false
        var downloadErr = "Download failed."

        let task = session.downloadTask(with: req) { tempURL, response, error in
            defer { sem.signal() }
            if let error {
                downloadErr = error.localizedDescription
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let tempURL else {
                downloadErr = "Invalid server response while downloading update."
                return
            }
            do {
                let attrs = try fm.attributesOfItem(atPath: tempURL.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0, size <= maxDownloadBytes else {
                    downloadErr = "Downloaded archive size is invalid."
                    return
                }
                try fm.moveItem(at: tempURL, to: URL(fileURLWithPath: zipPath))
                downloadOK = true
            } catch {
                downloadErr = error.localizedDescription
            }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 65.0)

        guard downloadOK else {
            try? fm.removeItem(atPath: stagingRoot)
            fputs("\(downloadErr)\n", stderr)
            return 1
        }

        return verifyAndExtractStagedZip(
            zipPath: zipPath,
            expectedSha256: expectedSha256,
            extractedDir: extractedDir,
            stagingRoot: stagingRoot
        )
    }

    static func verifyAndExtractStagedZip(
        zipPath: String,
        expectedSha256: String,
        extractedDir: String,
        stagingRoot: String
    ) -> Int32 {
        let fm = FileManager.default
        let cleanExpected = expectedSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanExpected.isEmpty {
            guard let actual = sha256Hex(fileAt: zipPath), actual == cleanExpected else {
                try? fm.removeItem(atPath: stagingRoot)
                fputs("SHA-256 verification failed for the downloaded archive.\n", stderr)
                return 1
            }
        }

        do {
            try fm.createDirectory(atPath: extractedDir, withIntermediateDirectories: true)
        } catch {
            try? fm.removeItem(atPath: stagingRoot)
            fputs("Failed to create extraction directory.\n", stderr)
            return 1
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", "--noqtn", zipPath, extractedDir]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        do {
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else {
                try? fm.removeItem(atPath: stagingRoot)
                fputs("Failed to extract downloaded archive.\n", stderr)
                return 1
            }
        } catch {
            try? fm.removeItem(atPath: stagingRoot)
            fputs("Failed to launch archive extractor.\n", stderr)
            return 1
        }

        let candidateApp = "\(extractedDir)/Pico.app"
        guard fm.fileExists(atPath: candidateApp),
              let stagedBundle = Bundle(path: candidateApp),
              stagedBundle.bundleIdentifier == expectedBundleID else {
            try? fm.removeItem(atPath: stagingRoot)
            fputs("Extracted bundle failed identifier verification.\n", stderr)
            return 1
        }

        let stagedExe = "\(candidateApp)/Contents/MacOS/Pico"
        guard fm.isExecutableFile(atPath: stagedExe) else {
            try? fm.removeItem(atPath: stagingRoot)
            fputs("Extracted bundle is missing an executable binary.\n", stderr)
            return 1
        }

        let xattrProc = Process()
        xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProc.arguments = ["-dr", "com.apple.quarantine", candidateApp]
        xattrProc.standardOutput = FileHandle.nullDevice
        xattrProc.standardError = FileHandle.nullDevice
        try? xattrProc.run()
        xattrProc.waitUntilExit()

        let verifyProc = Process()
        verifyProc.executableURL = URL(fileURLWithPath: stagedExe)
        verifyProc.arguments = ["--verify-build"]
        verifyProc.standardOutput = FileHandle.nullDevice
        verifyProc.standardError = FileHandle.nullDevice
        do {
            try verifyProc.run()
            verifyProc.waitUntilExit()
            guard verifyProc.terminationStatus == 0 else {
                try? fm.removeItem(atPath: stagingRoot)
                fputs("Staged application failed native verification.\n", stderr)
                return 1
            }
        } catch {
            try? fm.removeItem(atPath: stagingRoot)
            fputs("Failed to verify staged application binary.\n", stderr)
            return 1
        }

        print(candidateApp)
        return 0
    }

    // MARK: - Deterministic Self-Test (--test-update-logic)

    static func runSelfTestCLI() -> Int32 {
        guard UpdateSemVer.isRemoteNewer(remote: "v1.2.0", current: "1.1.0"),
              !UpdateSemVer.isRemoteNewer(remote: "v1.1.0", current: "1.1.0"),
              !UpdateSemVer.isRemoteNewer(remote: "v1.0.0", current: "1.1.0"),
              UpdateSemVer.parse("v1.2.0-beta.1") == nil else {
            fputs("SemVer logic failed\n", stderr)
            return 1
        }
        guard isTrustedGitHubURL("https://github.com/Ritolino/Pico/releases/download/v1.1.0/Pico-v1.1.0-macOS.zip"),
              !isTrustedGitHubURL("http://github.com/Ritolino/Pico/releases"),
              !isTrustedGitHubURL("https://evil.example.com/Pico.zip") else {
            fputs("URL trust logic failed\n", stderr)
            return 1
        }

        let sampleJSON = """
        {
          "tag_name": "v9.9.9",
          "html_url": "https://github.com/Ritolino/Pico/releases/tag/v9.9.9",
          "body": "Bugfix release",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "Pico-v9.9.9-macOS.zip",
              "browser_download_url": "https://github.com/Ritolino/Pico/releases/download/v9.9.9/Pico-v9.9.9-macOS.zip",
              "digest": "sha256:ABCDEF",
              "size": 1006694
            }
          ]
        }
        """.data(using: .utf8)!

        guard let parsed = parseGitHubReleaseJSON(sampleJSON, currentVersion: "1.2.0"),
              parsed.version == "9.9.9",
              parsed.sha256 == "abcdef" else {
            fputs("JSON release parsing failed\n", stderr)
            return 1
        }

        let tmpFile = "/tmp/pico-sha-selftest-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try? "pico".data(using: .utf8)?.write(to: URL(fileURLWithPath: tmpFile))
        guard let digest = sha256Hex(fileAt: tmpFile),
              digest == "9ea2483b344bb5c59f34a4b43ef6bc9d5ac9bd4e0370e4b1b90a1a416b0b28cd" else {
            fputs("SHA-256 self-test mismatch\n", stderr)
            return 1
        }

        print("Pico [Update Logic Self-Test] — PASS (SemVer, URL trust, JSON, SHA-256)")
        return 0
    }
}
