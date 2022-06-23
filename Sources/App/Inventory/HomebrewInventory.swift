/**
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as
 published by the Free Software Foundation, either version 3 of the
 License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import FairKit
import Foundation
import TabularData
import var FairExpo.appfairCaskAppsURL

/// The minimum number of characters before we will perform a search; helps improve performance for synchronous searches
let minimumSearchLength = 1

/// These functions are placed in an extension so they do not become subject to the `MainActor` restrictions.
private extension AppInventory where Self : HomebrewInventory {

    /// Installation is check simply by seeing if the brew install root exists.
    /// This will be used as the seed for the `enableHomebrew` app preference so we default to having it enabled if homebrew is seen as being installed
    static func homebrewCommandExists(at brewInstallRoot: URL) -> Bool {
        let cmd = brewCommand(at: brewInstallRoot).path
        let installed = FileManager.default.isExecutableFile(atPath: cmd)
        //dbg("installed:", cmd, installed)
        return installed
    }

    static func brewCommand(at brewInstallRoot: URL) -> URL {
        URL(fileURLWithPath: "bin/brew", relativeTo: brewInstallRoot)
    }

    /// The default install prefix for homebrew: “This script installs Homebrew to its preferred prefix (/usr/local for macOS Intel, /opt/homebrew for Apple Silicon and /home/linuxbrew/.linuxbrew for Linux) so that you don’t need sudo when you brew install. It is a careful script; it can be run even if you have stuff installed in the preferred prefix already. It tells you exactly what it will do before it does it too. You have to confirm everything it will do before it starts.”
    ///
    /// Note that on Intel, `/usr/local/bin/brew -> /usr/local/Homebrew/bin/brew`, but we shouldn't use `/usr/local/Homebrew/` as the brew root since `/usr/local/Caskroom` exists but `/usr/local/Homebrew/Caskroom` does not.
    static var globalBrewPath: URL {
        URL(fileURLWithPath: ProcessInfo.isArmMac ? "/opt/homebrew" : "/usr/local")
    }
}

private let appfairBase = URL(string: "https://github.com/App-Fair/")

/// The default values for brew default preferences
private struct HomebrewDefaults {
    /// ~/Library/Application Support/app.App-Fair/appfair-homebrew/Homebrew/
    static let brewInstallRoot: URL = {
        URL(fileURLWithPath: "Homebrew/", isDirectory: true, relativeTo: HomebrewInventory.localAppSupportFolder)
    }()

    static let caskAPIEndpoint = URL(string: "https://formulae.brew.sh/api/")!
    static let useSystemHomebrew = false
    static let quarantineCasks = true
    static let installDependencies = false
    static let zapDeletedCasks = false
    static let allowCasksWithoutApp = false
    static let ignoreAutoUpdatingAppUpdates = false
    static let requireCaskChecksum = false
    static let forceInstallCasks = false
    static let permitGatekeeperBypass = true
    static let manageCaskDownloads = true
    static let enableBrewAnalytics = false
    static let enableBrewSelfUpdate = false
    static let enableHomebrew = true
    static let enableCaskHomepagePreview = true
}

/// The cache policy to use when loading data
private let cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy

/// A manager for [Homebrew casks](https://formulae.brew.sh/docs/api/)
@available(macOS 12.0, iOS 15.0, *)
@MainActor public final class HomebrewInventory: ObservableObject, AppInventory {

    /// Whether to enable Homebrew Cask installation
    @AppStorage("enableHomebrew") var enableHomebrew = HomebrewDefaults.enableHomebrew {
        didSet {
            Task {
                // whenever the enableHomebrew setting is changed, perform a scan of the casks
                try await refreshAll(clearCatalog: true)
            }
        }
    }

    /// The base endpoint for the cask API; this can be used to test different cask endpoints
    @AppStorage("caskAPIEndpoint") var caskAPIEndpoint = HomebrewDefaults.caskAPIEndpoint

    /// Whether to allow Homebrew Cask installation; overriding this from the default path is un-tested and should only be changed for debugging Homebrew behavior
    @AppStorage("brewInstallRoot") var brewInstallRoot = HomebrewDefaults.brewInstallRoot

    /// Whether to use the system-installed Homebrew
    @AppStorage("useSystemHomebrew") var useSystemHomebrew = HomebrewDefaults.useSystemHomebrew

    /// Whether the quarantine flag should be applied to newly-installed casks
    @AppStorage("quarantineCasks") var quarantineCasks = HomebrewDefaults.quarantineCasks

    /// Whether to automatically install dependencies or not
    @AppStorage("installDependencies") var installDependencies = HomebrewDefaults.installDependencies

    /// Whether delete apps should be "zapped"
    @AppStorage("zapDeletedCasks") var zapDeletedCasks = HomebrewDefaults.zapDeletedCasks

    /// Whether apps that don't have an ".app" artifact should be shown
    @AppStorage("allowCasksWithoutApp") var allowCasksWithoutApp = HomebrewDefaults.allowCasksWithoutApp

    /// Whether to ignore casks that mark themselves as "autoupdates" from being shown in the "Updated" section
    @AppStorage("ignoreAutoUpdatingAppUpdates") var ignoreAutoUpdatingAppUpdates = HomebrewDefaults.ignoreAutoUpdatingAppUpdates

    /// Whether to require a checksum before downloading; many brew casks don't publish a checksum, so disabled by default
    @AppStorage("requireCaskChecksum") var requireCaskChecksum = HomebrewDefaults.requireCaskChecksum

    /// Whether to force overwrite other installations
    @AppStorage("forceInstallCasks") var forceInstallCasks = HomebrewDefaults.forceInstallCasks

    /// Whether to allow bypassing the gatekeeper check for unquarantined apps
    @AppStorage("permitGatekeeperBypass") var permitGatekeeperBypass = HomebrewDefaults.permitGatekeeperBypass

    /// Whether to use the in-app downloader to pre-cache the download file (which allows progress monitoring and user cancellation)
    @AppStorage("manageCaskDownloads") var manageCaskDownloads = HomebrewDefaults.manageCaskDownloads

    /// Whether to permit the `brew` command to send activitiy analytics. This controls whether to set Homebrew's flag [HOMEBREW_NO_ANALYTICS](https://docs.brew.sh/Analytics#opting-out)
    @AppStorage("enableBrewAnalytics") var enableBrewAnalytics = HomebrewDefaults.enableBrewAnalytics

    /// Allow brew to update itself when performing operations
    @AppStorage("enableBrewSelfUpdate") var enableBrewSelfUpdate = HomebrewDefaults.enableBrewSelfUpdate

    /// Enable browsing brew homepages from within the app
    @AppStorage("enableCaskHomepagePreview") var enableCaskHomepagePreview = HomebrewDefaults.enableCaskHomepagePreview

    /// The arranged list of app info items, synthesized from the `casks`, `stats`, and `appcasks` properties
    @Published private var appInfos: [AppInfo] = [] { didSet { updateAppCategories() } }

    /// The apps indexed by category
    @Published private var appCategories: [AppCategory: [AppInfo]] = [:]

    /// The current catalog of casks
    @Published var casks: [CaskItem] = [] { didSet { updateAppInfo() } }

    /// The date the catalog was most recently updated
    @Published private(set) var catalogUpdated: Date? = nil

    /// The download stats for cask tokens
    @Published private var appstats: CaskStats? = nil { didSet { updateAppInfo() } }

    /// Map of installed apps from `[token: [versions]]`
    @Published private var installedCasks: [CaskItem.ID: Set<String>] = [:] { didSet { updateAppInfo() } }

    /// Enhanced metadata about individual apps
    @Published private var appcasks: AppCatalog? { didSet { updateAppInfo() } }

    @Published private var sortOrder: [KeyPathComparator<AppInfo>] = [
        // don't have any initial sort so we can sort by the ranking
        // KeyPathComparator(\AppInfo.catalogMetadata.downloadCount, order: .reverse)
    ] { didSet { updateAppInfo() } }

    /// The number of outstanding update requests
    @Published var updateInProgress: UInt = 0

    /// The list of casks
    private var caskList: URL { URL(string: "cask.json", relativeTo: caskAPIEndpoint)! }
    private var formulaList: URL { URL(string: "formula.json", relativeTo: caskAPIEndpoint)! }

    private var caskSourceBase: URL { URL(string: "cask-source/", relativeTo: caskAPIEndpoint)! }
    private var caskMetadataBase: URL { URL(string: "cask/", relativeTo: caskAPIEndpoint)! }

    private var caskStatsBase: URL { URL(string: "analytics/cask-install/homebrew-cask/", relativeTo: caskAPIEndpoint)! }

    private var caskStats30: URL { URL(string: "30d.json", relativeTo: caskStatsBase)! }
    private var caskStats90: URL { URL(string: "90d.json", relativeTo: caskStatsBase)! }
    private var caskStats365: URL { URL(string: "365d.json", relativeTo: caskStatsBase)! }

    /// The local brew archive if it is embedded in the app
    private let brewArchiveURLLocal = Bundle.module.url(forResource: "appfair-homebrew", withExtension: "zip", subdirectory: "Bundle")

    /// The source of the brew command for [manual installation](https://docs.brew.sh/Installation#untar-anywhere)
    private let brewArchiveURLRemote = URL(string: "brew/zipball/HEAD", relativeTo: appfairBase)! // fork of https://github.com/Homebrew/brew/zipball/HEAD, same as: https://github.com/Homebrew/brew/archive/refs/heads/master.zip

    /// The source to the cask ruby definition file
    func caskSource(name: String) -> URL? {
        URL(string: name, relativeTo: caskSourceBase)?.appendingPathExtension("rb")
    }

    func caskMetadata(name: String) -> URL? {
        URL(string: name, relativeTo: caskMetadataBase)?.appendingPathExtension("json")
    }

    /// The previous location of homebrew installations: ~/Library/Caches/appfair-homebrew/
    private static let homebrewSupportFolderOLD = URL(fileURLWithPath: "appfair-homebrew/", isDirectory: true, relativeTo: try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))


    /// ~/Library/Application Support/app.App-Fair/
    private static let appFairSupportFolder = URL(fileURLWithPath: "app.App-Fair", isDirectory: true, relativeTo: try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))

    /// The given App Fair support folder name
    private static func appSupportFolder(named name: String) -> URL {
        URL(fileURLWithPath: name, isDirectory: true, relativeTo: appFairSupportFolder)
    }

    /// ~/Library/Application Support/app.App-Fair/appfair-homebrew/
    static let localAppSupportFolder: URL = appSupportFolder(named: "appfair-homebrew/")

    /// Standard homebrew download cache folder: `~Library/Caches/Homebrew/downloads/`
    static let caskDownloadCacheFolder: URL = URL(fileURLWithPath: "Homebrew/downloads/", isDirectory: true, relativeTo: try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))

    /// ~/Library/Application Support/app.App-Fair/Homebrew/Cask/
    static let caskAppSupportFolder: URL = appSupportFolder(named: "Homebrew/Cask/")

    /// The path where cask metadata and links are stored
    var localCaskroom: URL {
        URL(fileURLWithPath: "Caskroom", relativeTo: brewInstallRoot)
    }

    /// Whether there is a global installation of Homebrew available
    @available(*, deprecated, message: "use local brew install instead")
    static var globalBrewInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: brewCommand(at: globalBrewPath).path)
    }

    /// Whether the configured location is installed
    func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: Self.brewCommand(at: self.brewInstallRoot).path)
    }

    /// The home installation path for homebrew.
    @available(*, deprecated, message: "only differs when brew is installed from the install script")
    var brewInstallHome: URL {
        ProcessInfo.isArmMac ? brewInstallRoot : brewInstallRoot.appendingPathComponent("Homebrew")
    }


    /// Either `/opt/homebrew/.git` (ARM) or `/usr/local/Homebrew/.git` (Intel)
    @available(*, deprecated, message: "only works when brew is installed with .git folder")
    var brewGitFolder: URL? {
        URL(fileURLWithPath: ".git", relativeTo: brewInstallHome)
    }

    /// Returns the currently installed version of Homebrew, simply by scanning the git tags folder and using the most recent element.
    ///
    /// For example, `3.1.7` will be returned for the latest tag: `"/opt/homebrew/./.git/refs/tags/3.1.7"`
    @available(*, deprecated, message: "only works when brew is installed with .git folder")
    func installedBrewVersion() throws -> (version: String, updated: Date)? {
        // from brew.sh:
        // HOMEBREW_VERSION="$("${HOMEBREW_GIT}" -C "${HOMEBREW_REPOSITORY}" describe --tags --dirty --abbrev=7 2>/dev/null)"

        // we just scan the git tags folder manually and use the latest one
        // e.g.: "/opt/homebrew/./.git/refs/tags/3.1.7"
        let tagsFolder = URL(fileURLWithPath: "refs/tags", relativeTo: brewGitFolder)
        let children = try tagsFolder.fileChildren(deep: false, skipHidden: true, keys: [.contentModificationDateKey])
        if let mostRecent = children.sorting(by: \.contentModificationDateKey).last {
            return (mostRecent.lastPathComponent, mostRecent.modificationDate ?? .distantPast)
        } else {
            // no child folder elements
            return nil
        }
    }

    static let `default`: HomebrewInventory = HomebrewInventory()

    private var fsobserver: FileSystemObserver? = nil

    private init() {
        watchCaskroomFolder()
    }

    func resetAppStorage() {
        self.caskAPIEndpoint = HomebrewDefaults.caskAPIEndpoint
        self.brewInstallRoot = HomebrewDefaults.brewInstallRoot
        self.useSystemHomebrew = HomebrewDefaults.useSystemHomebrew
        self.quarantineCasks = HomebrewDefaults.quarantineCasks
        self.installDependencies = HomebrewDefaults.installDependencies
        self.zapDeletedCasks = HomebrewDefaults.zapDeletedCasks
        self.allowCasksWithoutApp = HomebrewDefaults.allowCasksWithoutApp
        self.ignoreAutoUpdatingAppUpdates = HomebrewDefaults.ignoreAutoUpdatingAppUpdates
        self.requireCaskChecksum = HomebrewDefaults.requireCaskChecksum
        self.forceInstallCasks = HomebrewDefaults.forceInstallCasks
        self.permitGatekeeperBypass = HomebrewDefaults.permitGatekeeperBypass
        self.manageCaskDownloads = HomebrewDefaults.manageCaskDownloads
        self.enableBrewAnalytics = HomebrewDefaults.enableBrewAnalytics
        self.enableBrewSelfUpdate = HomebrewDefaults.enableBrewSelfUpdate
    }

    /// The path to the `homebrew` command
    var localBrewCommand: String {
        let url = URL(fileURLWithPath: "bin/brew", relativeTo: useSystemHomebrew ? Self.globalBrewPath : brewInstallRoot)
        var cmd = url.path
        if cmd.contains(" ") {
            cmd = "'" + cmd + "'" // commands with a space (e.g., ~/Library/Application Support/appfair-homebrew/Homebrew/bin/brew) need to be quotes to be able to be run
        }
        return cmd
    }

    /// Fetch the available casks and stats, and integrate them with the locally-installed casks
    func refreshAll(clearCatalog: Bool) async throws {
        if enableHomebrew == false {
            dbg("skipping cask refresh because not isEnabled")
            return
        }

        if clearCatalog {
            self.casks = []
            self.appcasks = nil
            self.appstats = nil
        }

        self.updateInProgress += 1
        defer { self.updateInProgress -= 1 }
        async let installedCasks = scanInstalledCasks()
        async let casks = fetchCasks()
        async let appcasks = fetchAppCasks()
        async let appstats = fetchAppStats()

        //(self.stats, self.appcasks, self.installedCasks, self.casks) = try await (stats, appcasks, installedCasks, casks)
        self.installedCasks = try await installedCasks
        self.appcasks = try await appcasks
        self.appstats = try await appstats
        let caskResponse = try await casks
        self.casks = caskResponse.casks
        self.catalogUpdated = caskResponse.response?.lastModifiedDate

        self.objectWillChange.send()
    }

    /// Fetches the cask list and populates it in the `casks` property
    func fetchCasks() async throws -> (casks: Array<CaskItem>, response: URLResponse?) {
        dbg("loading cask list")
        let url = self.caskList
        let request = URLRequest(url: url, cachePolicy: cachePolicy)
        let (data, response) = try await URLSession.shared.fetch(request: request)
        try response?.validateHTTPCode()

        dbg("loaded cask JSON", data.count.localizedByteCount(), "from url:", url)
        let casks = try Array<CaskItem>(json: data)
        dbg("loaded", casks.count, "casks")
        return (casks, response)
    }

    /// Fetches the cask stats and populates it in the `stats` property
    fileprivate func fetchAppStats(statsURL: URL? = nil) async throws -> CaskStats {
        let url = statsURL ?? self.caskStats30
        dbg("loading cask stats:", url.absoluteString)
        let data = try await URLRequest(url: url, cachePolicy: cachePolicy).fetch()

        dbg("loaded cask stats", data.count.localizedByteCount(), "from url:", url)
        return try CaskStats(json: data)
    }

    fileprivate func fetchAppCasks() async throws -> AppCatalog {
        dbg("loading appcasks")
        let url = appfairCaskAppsURL
        let data = try await URLRequest(url: url, cachePolicy: cachePolicy).fetch()
        dbg("loaded cask JSON", data.count.localizedByteCount(), "from url:", url)
        let appcasks = try AppCatalog.parse(jsonData: data)
        dbg("loaded appcasks:", appcasks.apps.count)
        return appcasks
    }

    private func scanInstalledCasks() throws -> [CaskItem.ID : Set<String>] {
        // manually scan the installed files in /opt/homebrew/Caskroom/*/* to get the names and versions of the installed apps. E.g.,
        // /opt/homebrew/Caskroom/bon-mot/0.2.25/Bon Mot.app
        // /opt/homebrew/Caskroom/cloud-cuckoo-prerelease/0.8.150/Cloud Cuckoo.app
        // /opt/homebrew/Caskroom/discord/0.0.264/Discord.app
        // /opt/homebrew/Caskroom/figma/104.1.0/Figma.app
        // /opt/homebrew/Caskroom/firefox/94.0.1/Firefox.app

        let fm = FileManager.default

        // E.g.: ["firefox": ["94.0.1", "95.0.2"]]
        // ["telegram": Set(["8.4.1,225774"]), "app-fair": Set(["0.7.31"]), "visual-studio-code": Set(["1.62.2"]), "discord": Set(["0.0.264"]), "sita-sings-the-blues": Set(["0.0.24"]), "tune-out": Set(["0.8.349"]), "app-fair-prerelease": Set(["0.6.216"]), "slack": Set(["4.22.0"]), "transmission": Set(["3.00"]), "bon-mot-prerelease": Set(["1.1.16"]), "firefox": Set(["94.0.1", "95.0.2"]), "tune-out-prerelease": Set(["0.8.352"]), "minecraft": Set(["973,1"]), "microsoft-auto-update": Set(["4.40.21101001"]), "bon-mot": Set(["0.2.25"]), "vlc": Set(["3.0.16"]), "figma": Set(["107.1.0"]), "microsoft-edge": Set(["95.0.1020.44"]), "next-edit-prerelease": Set(["0.1.10"]), "cloud-cuckoo-prerelease": Set(["0.8.150"]), "zoom": Set(["5.8.3.2240"])]

        var tokenVersions: [CaskItem.ID: Set<String>] = [:]

        let dir = self.localCaskroom
        if fm.isDirectory(url: dir) == true {
            for caskFolder in try dir.fileChildren(deep: false, skipHidden: true) {
                let dirName = caskFolder.lastPathComponent // the name of the file is the token

                // get the list of child versions. E.g.:
                // /opt/homebrew/Caskroom/firefox/.metadata/
                // /opt/homebrew/Caskroom/firefox/94.0.1/
                // /opt/homebrew/Caskroom/firefox/95.0.2/

                let subfiles = try caskFolder.fileChildren(deep: false, skipHidden: false)
                    .filter { fm.isDirectory(url: $0) == true }
                var names = Set(subfiles.map(\.lastPathComponent)) // e.g.: .metadata, 94.0.1, 95.0.2
                if names.remove(".metadata") != nil { // only handle folders with a metadata dir
                    // TODO: how to handle non-homebrew (e.g., appfair/app) casks? All the taps seem to go into /opt/homebrew/Caskroom/, so there doesn't seem to be a way to distinguish between different cask sources?
                    let token = "homebrew/cask/" + dirName
                    tokenVersions[token] = names
                }
            }
        }

        dbg("scanned installed casks:", tokenVersions.keys.sorted()) // tokenVersions)
        return tokenVersions
    }

    func caskEnvironment() -> String {
        var cmd = ""

        //#if DEBUG // always leave on debugging output to help with error reporting
        cmd += "HOMEBREW_DEBUG=1 "
        //#endif

        // we always use the API for fetching casks to avoid having to clone the whole cask repo
        cmd += "HOMEBREW_INSTALL_FROM_API=1 "

        // don't lookup failure reasons on GitHub
        cmd += "HOMEBREW_NO_GITHUB_API=1 "

        // don't be cute
        cmd += "HOMEBREW_NO_EMOJI=1 "

        if self.requireCaskChecksum == true {
            // this probably only affects curl options for non-integrated downloading
            cmd += "HOMEBREW_NO_INSECURE_REDIRECT=1 "
        }

        if self.enableBrewAnalytics == false {
            // see: https://docs.brew.sh/Analytics#opting-out
            cmd += "HOMEBREW_NO_ANALYTICS=1 "
        }

        if self.enableBrewSelfUpdate == false {
            // see: https://docs.brew.sh/Manpage
            cmd += "HOMEBREW_NO_AUTO_UPDATE=1 "
        }


        return cmd
    }

    private func run(command: String, toolName: String, askPassAppInfo: CaskItem? = nil) async throws -> String {

        // Installers and updaters may sometimes require a password, but we don't want to run every brew command as an administrator (via AppleScript's `with administrator privileges`), since most installations should not require root (see: https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-bad)

        // without SUDO_ASKPASS, priviedged operations can fail with: sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper
        // sudo: a password is required
        // Error: Failure while executing; `/usr/bin/sudo -E -- /bin/rm -f -- /Library/LaunchDaemons/com.microsoft.autoupdate.helper.plist` exited with 1. Here's the output:
        // sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper

        // from https://github.com/Homebrew/homebrew-cask/issues/77258#issuecomment-588552316
        var cmd = command
        var scpt: URL? = nil

        let appName = askPassAppInfo?.name.first ?? askPassAppInfo?.token ?? "the app"
        if askPassAppInfo != nil {
            let title = "Administrator Password Required (Homebrew)"
                .replacingOccurrences(of: "\"", with: "'")
            let prompt = """
            The Homebrew \(toolName) for the “\(appName)” package needs an administrator password to complete the requested operation:

              \(command)

            Enter the password only if you trust this application to perform system-level installation operations.

            Alternatively, you can manually run the above command in a Terminal.app shell.
            """
                .replacingOccurrences(of: "\"", with: "'")

            let askPassScript = """
#!/usr/bin/osascript
return text returned of (display dialog "\(prompt)" with title "\(title)" default answer "" buttons {"Cancel", "OK"} default button "OK" with hidden answer)
"""

            let scriptFile = URL.tmpdir
                .appendingPathComponent("askpass-" + cmd.utf8Data.sha256().hex())
                .appendingPathExtension("scpt")
            dbg("creating sudo script:", scriptFile)
            scpt = scriptFile
            try askPassScript.write(to: scriptFile, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o777)], ofItemAtPath: scriptFile.path) // set the executable bit
            cmd = "SUDO_ASKPASS=" + scriptFile.path + " " + cmd
        }

        cmd = caskEnvironment() + cmd

        defer {
            // clean up any askpass script we may have generated
            if let scpt = scpt, FileManager.default.isWritableFile(atPath: scpt.path) {
                //dbg("cleaning up:", scpt.path)
                try? FileManager.default.removeItem(at: scpt)
            }
        }

        dbg("performing command:", cmd)
        do {
            guard let result = try await NSUserScriptTask.fork(command: cmd) else {
                throw AppError("No output from brew command")
            }
            dbg("command output:", result)
            return result
        } catch {
            throw AppError(String(format: NSLocalizedString("Error running %@", bundle: .module, comment: "error message title when a tool fails to run"), toolName), failureReason: String(format: NSLocalizedString("The %@ for %@ failed to complete successfully.", bundle: .module, comment: "error message body when a tool fails to run"), toolName, appName), underlyingError: error)
        }
    }

    func downloadCaskInfo(_ downloadURL: URL, _ cask: CaskItem, _ candidateURL: URL, _ expectedHash: String?, progress: Progress?) async throws {
        dbg("downloading:", downloadURL.absoluteString)

        let cacheDir = Self.caskDownloadCacheFolder
        dbg("checking cache:", cacheDir.path)
        try? FileManager.default.createDirectory(at: Self.caskAppSupportFolder, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil) // do not create the folder – if we do so, homebrew won't seem to set up its own directory structure and we'll see errors like: `Download failed on Cask 'iterm2' with message: No such file or directory @ rb_file_s_symlink - (../downloads/a8b31e8025c88d4e76323278370a2ae1a6a4b274a53955ef5fe76b55d5a8a8fe--iTerm2-3_4_15.zip, ~/Library/Application Support/app.App-Fair/Homebrew/Cask/iterm2--3.4.15.zip`

        /// `HOMEBREW_CACHE/"downloads/#{url_sha256}--#{resolved_basename}"`
        let targetURL = URL(fileURLWithPath: candidateURL.cachePathName, relativeTo: cacheDir)

        //let size = try await URLSession.shared.fetchExpectedContentLength(url: downloadURL)
        //dbg("fetchExpectedContentLength:", size)

        async let (downloadedArtifact, downloadSha256) = downloadArtifact(url: downloadURL, headers: [:], progress: progress)
        let actualHash = try await downloadSha256.hex()

        dbg("comparing SHA-256 expected:", expectedHash, "with actual:", expectedHash)
        if let expectedHash = expectedHash, expectedHash != actualHash {
            throw AppError("Invalid SHA-256 Hash", failureReason: "The downloaded SHA-256 (\(expectedHash) hash did not match the expected hash (\(expectedHash)).")
        }

        // dbg("moving:", downloadedArtifact.path, "to:", targetURL.path)
        // overwrite any previous cached version
        let artifact = try await downloadedArtifact
        let _ = try? FileManager.default.trash(url: targetURL)
        try FileManager.default.moveItem(at: artifact, to: targetURL)
        dbg("moved:", artifact.path, "to:", targetURL.path)
        try Task.checkCancellation()
    }

    /// Installs the given `AppCatalogItem` using the `brew` command. The release must be a valid Homebrew release.
    ///
    /// - Parameters:
    ///   - item: the catalog item to install
    ///   - parentProgress: optional progress for reporting download progress
    ///   - update: whether the action should be an update or an initial install
    ///   - quarantine: whether the installation process should quarantine the installed app(s), which will trigger a Gatekeeper check and user confirmation dialog when the app is first launched.
    ///   - force: whether we should force install the package, which will overwrite any other version that is currently installed regardless of its source.
    ///   - verbose: whether to verbosely report progress
    func install(item: AppInfo, progress parentProgress: Progress?, update: Bool = true, verbose: Bool = true) async throws {
        guard let cask = item.cask else {
            return dbg("not a cask:", item)
        }
        dbg(cask)

        // fetch the cask info so we can determine the actual URL to download (the catalog URL will not always contain the correct URL and checksum due to https://github.com/Homebrew/brew/issues/12786)
        guard var candidateURL = cask.url.flatMap(URL.init) else {
            return dbg("no URL for cask")
        }
        var sha256 = cask.checksum
        var caskArg = cask.token

        // make sure Homebrew is installed; if not, install it locally from the embedded appfair-homebrew.zip
        let _ = try await installHomebrew(retainCasks: true)

        // evaluate the cask to assess what the actual URL & checksum will be (working around https://github.com/Homebrew/brew/issues/12786)
        if let sourceURL = self.caskSource(name: cask.token) {
            do {
                try await fetchCaskInfo(sourceURL, cask, &candidateURL, &sha256, &caskArg)
            } catch {
                // this is non-fatal: we will just use the default URL
                dbg("error trying to fetch and parse cask info:", error)
            }
        }

        // also download any dependencies; note that this only traverses a single level of cask dependencies, so casks with dependencies like sonarr-menu.rb -> sonarr.rb -> mono-mdk.rb will still fail
        for depToken in (cask.depends_on?.cask ?? []) {
            let downloadFolder = self.caskInfoFolder
            if let depURL = self.caskSource(name: depToken) {
                dbg("downloading dependency token:", depToken, "from:", depURL.absoluteString)
                let caskDepPath = URL(fileURLWithPath: depURL.lastPathComponent, relativeTo: downloadFolder)
                try await URLSession.shared.fetch(request: URLRequest(url: depURL, cachePolicy: cachePolicy)).data.write(to: caskDepPath)
            }
        }

        let (downloadURL, expectedHash) = (candidateURL, sha256)

        if expectedHash == nil && self.requireCaskChecksum == true {
            throw AppError("Missing cryptographic checksum", failureReason: "The download has no SHA-256 checksum set and so its authenticity cannot be verified.")
        }

        // default config is to use: HOMEBREW_CACHE=$HOME/Library/Application Support/app.App-Fair/Homebrew

        if self.manageCaskDownloads == true {
            try Task.checkCancellation()
            try await downloadCaskInfo(downloadURL, cask, candidateURL, expectedHash, progress: parentProgress)
        }

        var cmd = (self.localBrewCommand as NSString).abbreviatingWithTildeInPath

        let op = update ? "upgrade" : "install" // could use "reinstall", but it doesn't seem to work with `HOMEBREW_INSTALL_FROM_API` when there is no local .git checkout
        cmd += " " + op
        if verbose { cmd += " --verbose" }

        if self.forceInstallCasks {
            cmd += " --force"
        }

        if !self.installDependencies {
            cmd += " --skip-cask-deps"
        }

        if self.quarantineCasks {
            cmd += " --quarantine"
        } else {
            cmd += " --no-quarantine"
        }

        if self.requireCaskChecksum != false {
            cmd += " --require-sha"
        }

        cmd += " --cask " + "'" + caskArg + "'" // handle spaces in cask arg

        let result = try await run(command: cmd, toolName: update ? .init("updater") : .init("installer"), askPassAppInfo: cask)

        // count the install
        if let installCounter = URL(string: "appcasks/releases/download/cask-\(cask.token)/cask-install", relativeTo: appfairBase) {
            dbg("counting install:", installCounter.absoluteString)
            let _ = try? await URLSession.shared.fetch(request: URLRequest(url: installCounter, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 600))
        }

        dbg("result of command:", cmd, ":", result)
        // manually re-scan to update the installed status of the item
        withAnimation {
            rescanInstalledCasks()
        }
    }

    /// The folder that will store cask information so that `brew info` will be able to find it
    fileprivate var caskInfoFolder: URL {
        URL(fileURLWithPath: "Library/Taps/homebrew/homebrew-cask/Casks/", isDirectory: true, relativeTo: brewInstallRoot)
    }

    /// Downloads the cash info for the given URL and parses it, extracting the `url` and `checksum` properties.
    fileprivate func fetchCaskInfo(_ sourceURL: URL, _ cask: CaskItem?, _ candidateURL: inout URL, _ sha256: inout String?, _ caskArg: inout String) async throws {
        // must be downloaded exactly here or `brew --info --cask <path>` will fail
        let downloadFolder = caskInfoFolder
        try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true, attributes: nil) // ensure it exists

        // the cask path is the same as the download name
        let caskPath = URL(fileURLWithPath: sourceURL.lastPathComponent, relativeTo: downloadFolder)

        dbg("downloading cask info from:", sourceURL.absoluteString, "to:", caskPath.path)
        try await URLSession.shared.fetch(request: URLRequest(url: sourceURL, cachePolicy: cachePolicy)).data.write(to: caskPath)

        // don't delete the local cask, since we want to re-use it for install
        // defer { try? FileManager.default.removeItem(at: caskPath) }

        var cmd = localBrewCommand
        cmd += " info --json=v2 --cask "
        cmd += "'" + caskPath.path + "'" // handle spaces in path
        let result = try await run(command: cmd, toolName: .init("info"), askPassAppInfo: cask)
        dbg("brew info result:", result)

        struct BrewInstallOutput : Decodable {
            // var formulae: [Formulae] // unused but seems to always be included
            var casks: [CaskItem]
        }

        let installInfo = try BrewInstallOutput(json: result.utf8Data)
        if let installCask = installInfo.casks.first,
           let caskURLString = installCask.url,
           let caskURL = URL(string: caskURLString) {
            if candidateURL != caskURL {
                // we parsed a different URL, which suggests that the system varies from the default catalog (usually arm vs. intel, but possibly also language)
                dbg("downloading:", caskURL.absoluteString, "(\(installCask.checksum ?? "no checksum"))", "instead of:", candidateURL, "(\(sha256 ?? "no checksum"))")
                candidateURL = caskURL
                sha256 = installCask.checksum
                caskArg = caskPath.path
            }
        }
    }


    func delete(item: AppInfo, verbose: Bool = true) async throws {
        guard let cask = item.cask else {
            return dbg("not a cask:", item)
        }

        dbg(cask.token)
        var cmd = localBrewCommand
        let op = "remove"
        cmd += " " + op
        if self.forceInstallCasks { cmd += " --force" }
        if self.zapDeletedCasks { cmd += " --zap" }
        if verbose { cmd += " --verbose" }
        cmd += " --cask " + cask.token
        let result = try await run(command: cmd, toolName: .init("uninstaller"), askPassAppInfo: cask)
        dbg("result:", result)
    }

    @ViewBuilder func icon(for item: AppInfo, useInstalledIcon: Bool = false) -> some View {
        if useInstalledIcon, let path = try? self.installedPath(for: item) {
            // note: “The returned image has an initial size of 32 pixels by 32 pixels.”
            let icon = NSWorkspace.shared.icon(forFile: path.path)
            Image(uxImage: icon).resizable()
        } else if let _ = item.catalogMetadata.iconURL {
            item.catalogMetadata.iconImage() // use the icon URL if it has been set (e.g., using appcasks metadata)
        } else if let baseURL = item.catalogMetadata.developerName.flatMap(URL.init(string:)) {
            // otherwise fallback to using the favicon for the home page
            FaviconImage(baseURL: baseURL, fallback: {
                EmptyView()
            })
        } else {
            FairSymbol.questionmark_square_dashed
        }
    }

    fileprivate func findAppLink(in children: [URL]) -> URL? {
        for appURL in children {
            dbg("checking install child:", appURL.path)
            if appURL.pathExtension == "app"
                && FileManager.default.isExecutableFile(atPath: appURL.path) {
                // try to resolve the symbolic link (e.g., /opt/homebrew/Caskroom/discord/0.0.264/Discord.app -> /Applications/Discord.app so revealing the app will show it in the destination context
                let linkPath = try? FileManager.default.destinationOfSymbolicLink(atPath: appURL.path)
                dbg("executable:", appURL.path, linkPath)

                if let linkPath = linkPath {
                    return URL(fileURLWithPath: linkPath)
                } else {
                    return appURL
                }
            }
        }

        return nil
    }

    func installedPath(for item: AppInfo) throws -> URL? {
        let token = item.catalogMetadata.bundleIdentifier.caskToken ?? ""
        let caskDir = URL(fileURLWithPath: token, relativeTo: self.localCaskroom)
        let versionDir = URL(fileURLWithPath: item.catalogMetadata.version ?? "", relativeTo: caskDir)
        if FileManager.default.isDirectory(url: versionDir) == true {
            let children = try versionDir.fileChildren(deep: false, skipHidden: true)
            if let link = findAppLink(in: children) {
                return link
            }

            // go down one more level, to handle zip/dmgs that contained a top-level set of directories, e.g., ~/Library/Application Support/app.App-Fair/appfair-homebrew/Homebrew/Caskroom/lockrattler/4.32,2022.01/lockrattler432/LockRattler.app
            for child in children {
                if FileManager.default.isDirectory(url: child) == true {
                    dbg("checking sub-child:", child.path)
                    let subChildren = try child.fileChildren(deep: false, skipHidden: true)
                    if let link = findAppLink(in: subChildren) {
                        return link
                    }
                }
            }

            dbg("no app found in:", versionDir.path, "children:", children.map(\.lastPathComponent))
        }

        // fall back to scanning for the app artifact and looking in the /Applications folder
        if let cask = casks.first(where: { $0.token == token }) {
            for appName in cask.appArtifacts {
                let appURL = URL(fileURLWithPath: appName, relativeTo: FairAppInventory.applicationsFolderURL)
                dbg("checking app path:", appURL.path)
                if FileManager.default.isExecutableFile(atPath: appURL.path) {
                    return appURL
                }
            }
        }
        return nil
    }

    func reveal(item: AppInfo) async throws {
        let installPath = try self.installedPath(for: item)
        dbg(item.id, installPath?.path)
        if let installPath = installPath, FileManager.default.isExecutableFile(atPath: installPath.path) {
            dbg("revealing:", installPath.path)
            NSWorkspace.shared.activateFileViewerSelecting([installPath])
        } else {
            throw AppError("Could not find install path for “\(item.catalogMetadata.name)”")
        }
    }

    func launch(item: AppInfo) async throws {
        // if we allow bypassing the gatekeeper check for unquarantined apps, then we need to first check to see if the app is quarantined before we launch it
        let gatekeeperCheck = permitGatekeeperBypass == true

        let installPath = try self.installedPath(for: item)
        dbg(item.id, installPath?.path)
        guard let installPath = installPath, FileManager.default.isExecutableFile(atPath: installPath.path) else {
            // only packages that contain dmg/zips of .app files are linked to the /Applications/Name.app; applications installed using package installers don't reference their target app installation, except possibly in the delete stanza of the my-app.rb file. E.g.:
            // pkg "My App.pkg"
            // uninstall pkgutil: "app.MyApp.plist",
            //           delete:  "/Applications/My App.app"
            //
            // how should we try to identify the app to launch? we don't want to have to try to parse the

            throw AppError("Could not find install path for “\(item.catalogMetadata.name)”")
        }

        // if we want to check for gatekeeper permission, and if the file is quarantined and it fails the gatekeeper check, offer the option to de-quarantine the app before launching
        if try gatekeeperCheck
            && (FileManager.default.isQuarantined(at: installPath)) == true {
            do {
                dbg("performing gatekeeper check for quarantined path:", installPath.path)
                let result = try Process.spctlAssess(appURL: installPath)
                if result.exitCode == 3 { // “spctl exits zero on success, or one if an operation has failed.  Exit code two indicates unrecognized or unsuitable arguments.  If an assessment operation results in denial but no other problem has occurred, the exit code is three.” e.g.: gatekeeper check failed: (exitCode: 3, stdout: [], stderr: ["/Applications/VSCodium.app: rejected", "source=Unnotarized Developer ID"])
                    dbg("gatekeeper check failed:", result)
                    if (await prompt(.warning, messageText: NSLocalizedString("Unidentified Developer", bundle: .module, comment: "warning dialog title"),
                                     informativeText: String(format: NSLocalizedString("The app “%@” is from an unidentified developer and has been quarantined.\n\nIf you trust the publisher of the app at %@, you may override the quarantine for this app in order to launch it.", bundle: .module, comment: "warning dialog body"), item.catalogMetadata.name, item.homepage?.absoluteString ?? ""),
                                     accept: NSLocalizedString("Launch", bundle: .module, comment: "warning dialog launch anyway button title"))) == false {
                        dbg("cancelling launch due to unidentified developer")
                        return
                    }

                    // ideally, we would white-list the app with spctl, but gatekeeper seems to randomly reject the request, and even when it succeeds, it seems to randomly reset the permission again in the futurel
                    //try Process.spctlEnable(appURL: installPath)
                    //try Process.removeQuarantine(appURL: installPath)

                    // so instead, take the nuclear option and just clear the quarantine bits on the app
                    dbg("clearing quarantine attribute from:", installPath.path)
                    try FileManager.default.clearQuarantine(at: installPath)
                }
            } catch {
                dbg("gatekeeper check failed:", error)
                // try to proceed anyway
            }

        }

        dbg("launching:", installPath.path)

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.promptsUserIfNeeded = true
        cfg.activates = true
        try await NSWorkspace.shared.openApplication(at: installPath, configuration: cfg)
    }

    /// Un-installs the local copy of Homebrew (by simply deleting the local install root)
    func uninstallHomebrew() async throws {
        try FileManager.default.trash(url: self.brewInstallRoot)
    }

    /// Downloads and installs Homebrew from the source zip
    /// - Returns: `true` if we installed Homebrew, `false` if it was already installed
    @discardableResult func installHomebrew(force: Bool = false, fromLocalOnly: Bool = false, retainCasks: Bool) async throws -> Bool {
        // migrate old location from: ~/Library/Caches/appfair-homebrew
        // to new location: ~/Library/Application Support/app.App-Fair/appfair-homebrew
        if FileManager.default.isDirectory(url: Self.homebrewSupportFolderOLD) == true {
            dbg("migrating home brew support from:", HomebrewDefaults.brewInstallRoot.path)
            do {
                try FileManager.default.createDirectory(at: Self.appFairSupportFolder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: Self.homebrewSupportFolderOLD, to: Self.localAppSupportFolder)
            } catch {
                dbg("error migrating homebrew support folder:", error)
            }
        }

        if force || (FileManager.default.isDirectory(url: HomebrewDefaults.brewInstallRoot) != true) {
            let appSupportFolder = Self.localAppSupportFolder
            try FileManager.default.createDirectory(at: appSupportFolder, withIntermediateDirectories: true, attributes: [:])
            try await installBrew(to: HomebrewDefaults.brewInstallRoot, fromLocalOnly: fromLocalOnly, retainCasks: retainCasks)
            return true
        } else {
            return false
        }
    }

    /// The docs recommend to use “the default prefix. Some things may not build when installed elsewhere” and “Pick another prefix at your peril!”, but downloading to a local cache URL seems to work fine.
    /// - Parameters:
    ///   - brewHome: the home into which to install brew
    ///   - fromLocalOnly: whether to only permit using the local cache of the brew archive zip
    ///   - retainCasks: whether to retain existing casks when updating to a new brew version
    private func installBrew(to brewHome: URL, fromLocalOnly: Bool, retainCasks: Bool) async throws {
        let fm = FileManager.default

        let fromURL, downloadedArtifact: URL
        let removeArtifact: Bool
        if let localURL = self.brewArchiveURLLocal, FileManager.default.fileExists(atPath: localURL.path) {
            fromURL = localURL
            downloadedArtifact = localURL
            removeArtifact = false
        } else if fromLocalOnly {
            throw AppError("Could not install from local artifact")
        } else {
            fromURL = self.brewArchiveURLRemote
            let (downloaded, response) = try await URLSession.shared.download(request: URLRequest(url: fromURL), memoryBufferSize: 1024 * 64, consumer: nil, parentProgress: nil)
            dbg("received download response:", response)
            downloadedArtifact = downloaded
            removeArtifact = true
        }

        dbg("unpacked brew package from:", fromURL.absoluteString, downloadedArtifact.fileSize()?.localizedByteCount()) // "response:", response)

        if retainCasks == false && FileManager.default.isDirectory(url: brewHome) == true {
            try fm.removeItem(at: brewHome) // clear any previous installation
        }

        try fm.unzipItem(at: downloadedArtifact, to: brewHome, trimBasePath: true, overwrite: retainCasks == true)
        dbg("extracted brew package to:", brewHome)

        if removeArtifact {
            try fm.removeItem(at: downloadedArtifact) // don't remove the local artifact, since we may need it later
        }

        // no re-start the FS watcher for the new folders
        // we do this mutliple times because the install process creates the folder eagerly before the install starts, and so it will be subject to the amount of time the install takes
        watchCaskroomFolder(delays: [0, 1, 2, 5, 10, 30])
    }

    /// Returns whether Homebrew is installed in the expected local path
    func isHomebrewInstalled() -> Bool {
        Self.homebrewCommandExists(at: self.brewInstallRoot)
    }

    /// Setup a watch for the cache folder
    private func watchCaskroomFolder(delays: [Int] = [0]) {
        if !self.isHomebrewInstalled() {
            return dbg("homebrew not installed")
        }

        let caskroomFolder = self.localCaskroom

        try? FileManager.default.createDirectory(at: caskroomFolder, withIntermediateDirectories: true, attributes: nil)

        // directory must exist or `DispatchSource.makeFileSystemObjectSource` will crash
        if FileManager.default.isDirectory(url: caskroomFolder) != true {
            return dbg("not a folder:", caskroomFolder.path)
        }

        dbg("checking brew observer in:", caskroomFolder.path)

        // set up a file-system observer for the install folder, which will refresh the installed apps whenever any changes are made; this allows external processes like homebrew to update the installed app
        self.fsobserver = FileSystemObserver(URL: caskroomFolder, queue: .main) {
            dbg("changes detected in cask folder:", caskroomFolder.path)
            // we need a small delay here because brew seems to create the directory eagerly before it unpacks and moves the app, which means there is often a signifcant delay between when the change occurs and the app version is available there
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
                    self.rescanInstalledCasks()
                }
            }
        }
    }

    /// Performs a scan of the installed casks and updates the local cache
    @MainActor func rescanInstalledCasks() {
        do {
            self.installedCasks = try self.scanInstalledCasks()
        } catch {
            dbg("error scanning for installed casks:", error)
        }
    }
}

private extension AppCatalogItem {
    var abbreviatedToken: String {
        let token = self.id.rawValue
        if let lastSlash = token.lastIndex(of: "/") {
            return token[lastSlash...].description
        } else {
            return token
        }
    }
}

extension HomebrewInventory {
    /// Re-builds the AppInfo collection.
    private func updateAppInfo() {
        // an index of [token: extraInfo]
        let appcaskInfo: [String: [AppCatalogItem]] = (appcasks?.apps ?? [])
            .grouping(by: \.abbreviatedToken)

        let ancillaryStats = appstats?.formulae ?? [:]

        // the position of the cask in the ranks, which is used to control the initial sort order
        let caskRanks: [String : Int] = (appcasks?.apps ?? [])
            .enumerated()
            .grouping(by: \.element.abbreviatedToken)
            .compactMapValues(\.first?.offset)

        // dbg("casks:", caskMap.keys.sorted())
        var infos: [AppInfo] = []

        //dbg("checking installed casks:", installedCasks.keys.sorted())
        //dbg("checking all casks:", casks.map(\.id).sorted())

        func downloadStatsCount(for token: String) -> Int? {
            ancillaryStats[token]?.first?.count
        }

        for cask in self.casks {
            // skips casks that don't have any download URL
            guard let downloadURL = cask.url.flatMap(URL.init(string:)) else {
                continue
            }

            // the short cask token (e.g. "firefox")
            let caskTokenShort = cask.token

            // the long cask token (e.g. "homebrew/cask/firefox")
            let caskTokenFull = cask.id
            let caskid = CaskIdentifier(caskTokenFull)

            let caskInfo = appcaskInfo[caskTokenShort]

            let downloadCount = caskInfo?.first?.downloadCount
            let ancillaryDownloadCount = downloadStatsCount(for: caskTokenShort)
            // dbg("downloads for:", caskTokenShort, "downloads:", downloads, "ancillaryDownloadCount:", ancillaryDownloadCount)

            let downloads = (downloadCount ?? 0) + (ancillaryDownloadCount ?? 0)

            let readmeURL = caskInfo?.first?.readmeURL
            let releaseNotesURL = caskInfo?.first?.releaseNotesURL

            // TODO: extract installed Plist and check bundle identifier?
            //let installed = installedCasks[caskTokenShort]?.first
            //dbg("installed info for:", caskTokenShort, installed)

            //dbg("download count for:", caskid, downloads)
            guard let caskHomepage = cask.homepage.flatMap(URL.init(string:)) else {
                dbg("skipping cask with no home page:", cask.homepage)
                continue
            }

            // TODO: we should de-proritize the privileged domains so the publisher fork will always take precedence
            let appcask = caskInfo?.first { item in
                item.homepage?.host == "appfair.app"
                || item.homepage?.host == "www.appfair.app"
                || item.homepage?.host == caskHomepage.host
            }

            //dbg("appcaskInfo for:", caskid, appcask)

            let name = cask.name.first ?? caskTokenShort

            let versionDate: Date? = nil // how to obtain this? we could look at the mod date on, e.g., /opt/homebrew/Library/Taps/homebrew/homebrew-cask/Casks/signal.rb, but they seem to only be synced with the last update

            let item = AppCatalogItem(name: name, bundleIdentifier: caskid, subtitle: cask.desc ?? "", developerName: caskHomepage.absoluteString, localizedDescription: cask.desc ?? "", size: 0, version: cask.version, versionDate: versionDate, downloadURL: downloadURL, iconURL: appcask?.iconURL, screenshotURLs: appcask?.screenshotURLs, versionDescription: appcask?.versionDescription, tintColor: appcask?.tintColor, beta: false, sourceIdentifier: appcask?.sourceIdentifier, categories: appcask?.categories, downloadCount: downloads, impressionCount: appcask?.impressionCount, viewCount: appcask?.viewCount, starCount: nil, watcherCount: nil, issueCount: nil, sourceSize: nil, coreSize: nil, sha256: cask.checksum, permissions: nil, metadataURL: self.caskMetadata(name: cask.token), readmeURL: readmeURL, releaseNotesURL: releaseNotesURL, homepage: caskHomepage)

            let info = AppInfo(catalogMetadata: item, cask: cask)
            infos.append(info)
        }

        var sortedInfos = infos

        //dbg("caskRanks", caskRanks)

        // when unsorted, use the position in the appcask ranking for presentation raking
        if self.sortOrder.isEmpty {
            sortedInfos = sortedInfos.reversed().sorted(by: { info1, info2 in
                guard let id1 = info1.cask?.token else { return false }
                guard let id2 = info2.cask?.token else { return true }

                let rank1 = caskRanks[id1]
                let rank2 = caskRanks[id2]

                // un-ranked casks fall back to being sorted by the download stats
                if rank1 == nil && rank2 == nil {
                    let dl1 = downloadStatsCount(for: id1)
                    let dl2 = downloadStatsCount(for: id2)
                    return (dl1 ?? 0) > (dl2 ?? 0)
                }

                guard let rank1 = rank1 else {
                    return rank2 == nil
                }
                guard let rank2 = rank2 else {
                    return true
                }

                return rank1 < rank2
            })
        } else {
            sortedInfos = sortedInfos.sorted(using: self.sortOrder)
        }

        dbg("sorted:", infos.count, "first:", sortedInfos.first?.id.rawValue, "last:", sortedInfos.last?.id.rawValue)

        // avoid triggering unnecessary changes
        if self.appInfos != sortedInfos {
             withAnimation { // this animation seems to cancel loading of thumbnail images the first time the screen is displayed if the image takes a long time to load (e.g., for large thumbnails)
                self.appInfos = sortedInfos
                     .filter { info in
                         allowCasksWithoutApp == true || info.cask?.appArtifacts.isEmpty == false
                     }
             }
        }
    }

    var visibleAppInfos: [AppInfo] {
        appInfos
        // this is too slow to do dynamically; in the future maybe cache it but for now we'll filter up-front, at the cost that we won't dybamically change the filtered values when the property is changed
//            .filter { info in
//                allowCasksWithoutApp == true || info.cask?.appArtifacts.isEmpty == false
//            }
    }

    /// Updates the appCategories index whenever the appInfos property changes
    func updateAppCategories() {
        appCategories.removeAll()
        for app in visibleAppInfos {
            for cat in app.displayCategories {
                appCategories[cat, default: []].append(app)
            }
        }
    }

    func arrangedItems(sidebarSelection: SidebarSelection?, sortOrder: [KeyPathComparator<AppInfo>], searchText: String) -> [AppInfo] {
        let infos = visibleAppInfos
            .filter({ matchesSelection(item: $0, sidebarSelection: sidebarSelection) })
            .filter({ matchesSearch(item: $0, searchText: searchText) })

        if sidebarSelection?.item.isLocalFilter == true {
            // installed and updated apps are sorted by name
            return infos.sorted(using: [KeyPathComparator(\AppInfo.catalogMetadata.name, order: .forward)])
        } else {
            return infos
        }
        //.sorted(using: sortOrder + [KeyPathComparator(\AppInfo.catalogMetadata.downloadCount, order: .reverse)]) // sorting each time is very slow; we should instead update a cache of the sorted changes
    }

    func matchesSearch(item: AppInfo, searchText: String) -> Bool {
        let txt = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // searching for a specific cask is an exact match
        if txt.hasPrefix("homebrew/cask/") {
            return item.cask?.tapToken == txt
        }

        if txt.count < minimumSearchLength {
            return true
        }

        func matches(_ string: String?) -> Bool {
            string?.localizedCaseInsensitiveContains(txt) == true
        }

        if matches(item.cask?.tapToken) { return true }
        if matches(item.cask?.homepage) { return true }

        if matches(item.catalogMetadata.name) { return true }
        if matches(item.catalogMetadata.subtitle) { return true }
        if matches(item.catalogMetadata.developerName) { return true }
        if matches(item.catalogMetadata.localizedDescription) { return true }

        return false
    }

    func matchesSelection(item: AppInfo, sidebarSelection: SidebarSelection?) -> Bool {
        switch sidebarSelection?.item {
        case .installed:
            return installedCasks[item.catalogMetadata.id.rawValue] != nil
        case .updated:
            return appUpdated(item: item)
        case .category(let cat):
            return item.catalogMetadata.categories?.contains(cat.metadataIdentifier) == true
        default:
            return true
        }
    }

    func apps(for category: AppCategory) -> [AppInfo] {
        appCategories[category] ?? []
    }

    func appInstalled(item: AppInfo) -> String? {
        installedCasks[item.id.rawValue]?.max() // max isn't the right thing to do here (since 1.10 < 1.90), but we want a consistent result
    }

    func appUpdated(item: AppInfo) -> Bool {
//        let versions = homeBrewInv.installedCasks[info.id.rawValue] ?? []
//        return info.catalogMetadata.version.flatMap(versions.contains) != true

        if let releaseVersion = item.catalogMetadata.version,
           let installedVersions = installedCasks[item.catalogMetadata.id.rawValue] {
            if self.ignoreAutoUpdatingAppUpdates == true && item.cask?.auto_updates == true {
                return false // show showing apps that mark themselves as auto-updating
            }
            //dbg(item.catalogMetadata.id, "releaseVersion:", releaseVersion, "installedCasks:", installedCasks)
            return installedVersions.contains(releaseVersion) == false
        } else {
            return false
        }
    }

    func versionNotInstalled(cask: CaskItem) -> Bool {
        if let installedCasks = installedCasks[cask.id] {
            return !installedCasks.contains(cask.version)
        } else {
            return false
        }
    }

    func updateCount() -> Int {
        return visibleAppInfos
            .filter({ info in
                if let cask = info.cask {
                    return self.versionNotInstalled(cask: cask)
                } else {
                    return false
                }
            })
            .filter({ info in
                appUpdated(item: info)
            })
            .count
    }

    func badgeCount(for item: SidebarItem) -> Text? {
        func fmt(_ number: Int) -> Text? {
            if number <= 0 { return nil }
            return Text(number, format: .number)
        }

        switch item {
        case .top:
            return fmt(visibleAppInfos.count)
        case .updated:
            return fmt(updateCount())
        case .installed:
            return fmt(installedCasks.count)
        case .recent:
            return nil
        case .category(let cat):
            return fmt(apps(for: cat).count)
        }
    }
}

extension HomebrewInventory {
    /// Fetches livecheck for the given cask
    func fetchLivecheck(for cask: String) async throws -> (strategy: String, url: URL)? {
        guard let caskSource = self.caskSource(name: cask) else {
            throw AppError("no metadata for package")
        }
        dbg("caskSource:", caskSource)
        let (data, _) = try await URLSession.shared.fetch(request: URLRequest(url: caskSource))

        let ruby = String(data: data, encoding: .utf8) ?? ""
        //dbg("retrieved cask for", cask, ":", ruby)
        guard let livecheck = HomebrewInventory.extractStanza(named: "livecheck", from: ruby) else {
            // throw AppError("unable to parse stanza")
            return nil // it is legal for an app to not have the livecheck stanza
        }

        guard let strategy = livecheck["strategy"] else {
            // throw AppError("unable to parse stanza for strategy property")
            return nil // some livechecks just have 'regex' with no 'strategy'
        }

        // note that this will fail when the appcast URL is composed of tokens (e.g.: "https://kapeli.com/Dash#{version.major}.xml")
        guard let lcURL = livecheck["url"], let url = URL(string: lcURL.trimmedEvenly(["'", "\""])) else {
            throw AppError("unable to parse stanza for url property")
        }

        return (strategy, url)
    }

    /// Parses the stanza name from the specified ruby code and returns a dictionary of the keys and values it sees.
    /// Note: this is not a full-feratures ruby parser, but just enough to extract static key/value definitions from some very well-formed ruby source
    static func extractStanza(named stanza: String, from rubyCode: String) -> [String: String]? {
        let lines = rubyCode.components(separatedBy: .newlines)
        let stanzaOpen = (stanza + " do")
        guard let lcBegin = lines.firstIndex(where: { $0.trimmed() == stanzaOpen }) else {
            dbg("no opening clause to stanza:", stanza)
            return nil
        }

        // the closing stanza should be "end" with matching indentation
        let stanzaClose = lines[lcBegin].replacingOccurrences(of: stanzaOpen, with: "end")

        guard let lcEnd = lines[lcBegin...].firstIndex(where: { $0 == stanzaClose }) else {
            dbg("no matching end segment to stanza:", stanza)
            return nil
        }

        if lcEnd <= lcBegin {
            dbg("bad stanza match range:", lcBegin, lcEnd)
            return nil
        }

        let stanzaContents = lines[lcBegin+1...lcEnd-1]

        //dbg("stanza clause:", stanzaContents)
        var props = [String: String]()
        for line in stanzaContents {
            if let key = line.trimmed().split(separator: " ").first, !key.isEmpty {
                // the value is everything after the key (with spaces trimmed)
                let value = line.trimmed()[key.endIndex...].trimmed()
                props[String(key)] = value
            }
        }
        return props
    }
}

typealias AppcastFeed = WebFeed<AppcastWebFeedAdditions>

/// Additional properties for various elements of a `WebFeed`.
enum AppcastWebFeedAdditions : WebFeedAdditions {
    typealias FeedAdditions = Never
    typealias ChannelAdditions = Never
    static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"


    /// Appcast-specific attributes for `<item>` nodes
    ///
    /// ```
    /// SUAppcastElementVersion = SUAppcastAttributeVersion;
    /// SUAppcastElementShortVersionString = SUAppcastAttributeShortVersionString;
    /// SUAppcastElementCriticalUpdate = @"sparkle:criticalUpdate";
    /// SUAppcastElementDeltas = @"sparkle:deltas";
    /// SUAppcastElementMinimumAutoupdateVersion = @"sparkle:minimumAutoupdateVersion";
    /// SUAppcastElementMinimumSystemVersion = @"sparkle:minimumSystemVersion";
    /// SUAppcastElementMaximumSystemVersion = @"sparkle:maximumSystemVersion";
    /// SUAppcastElementReleaseNotesLink = @"sparkle:releaseNotesLink";
    /// SUAppcastElementFullReleaseNotesLink = @"sparkle:fullReleaseNotesLink";
    /// SUAppcastElementTags = @"sparkle:tags";
    /// SUAppcastElementPhasedRolloutInterval = @"sparkle:phasedRolloutInterval";
    /// SUAppcastElementInformationalUpdate = @"sparkle:informationalUpdate";
    /// SUAppcastElementChannel = @"sparkle:channel";
    /// SUAppcastElementBelowVersion = @"sparkle:belowVersion";
    /// SUAppcastElementIgnoreSkippedUpgradesBelowVersion = @"sparkle:ignoreSkippedUpgradesBelowVersion";
    /// ```
    struct ItemAdditions : XMLNodeExpressible, Hashable {
        var version: String?
        var shortVersionString: String?
        var criticalUpdate: String?
        var minimumAutoupdateVersion: String?
        var minimumSystemVersion: String?
        var maximumSystemVersion: String?
        var releaseNotesLink: String?
        var fullReleaseNotesLink: String?
        var phasedRolloutInterval: String?
        var informationalUpdate: String?
        var channel: String?
        var belowVersion: String?
        var ignoreSkippedUpgradesBelowVersion: String?
        var tags: [FairCore.XMLNode]?
        var deltas: [AppcastFeed.Channel.Enclosure]?

        init?(node: FairCore.XMLNode) throws {
            let element = { node.childElements(named: $0, namespaceURI: sparkle).first?.childContentTrimmed }

            self.version = element("version")
            self.shortVersionString = element("shortVersionString")
            self.criticalUpdate = element("criticalUpdate")
            self.minimumAutoupdateVersion = element("minimumAutoupdateVersion")
            self.minimumSystemVersion = element("minimumSystemVersion")
            self.maximumSystemVersion = element("maximumSystemVersion")
            self.releaseNotesLink = element("releaseNotesLink")
            self.fullReleaseNotesLink = element("fullReleaseNotesLink")
            self.phasedRolloutInterval = element("phasedRolloutInterval")
            self.informationalUpdate = element("informationalUpdate")
            self.channel = element("channel")
            self.belowVersion = element("belowVersion")
            self.ignoreSkippedUpgradesBelowVersion = element("ignoreSkippedUpgradesBelowVersion")

            self.tags = node.childElements(named: "tags", namespaceURI: sparkle).flatMap(\.elementChildren).array()
            self.deltas = try node.childElements(named: "deltas", namespaceURI: sparkle).flatMap(\.elementChildren).compactMap(AppcastFeed.Channel.Enclosure.init)
        }
    }

    /// Appcast-specific attributes for `<enclosure>` nodes:
    ///
    /// ```
    /// SUAppcastAttributeDeltaFrom = @"sparkle:deltaFrom";
    /// SUAppcastAttributeDSASignature = @"sparkle:dsaSignature";
    /// SUAppcastAttributeEDSignature = @"sparkle:edSignature";
    /// SUAppcastAttributeShortVersionString = @"sparkle:shortVersionString";
    /// SUAppcastAttributeVersion = @"sparkle:version";
    /// SUAppcastAttributeOsType = @"sparkle:os";
    /// SUAppcastAttributeInstallationType = @"sparkle:installationType";
    /// ```
    struct EnclosureAdditions : XMLNodeExpressible, Hashable {
        var version: String?
        var shortVersionString: String?
        var edSignature: String?
        var dsaSignature: String?
        var deltaFrom: String?
        var installationType: String?
        var os: String?

        init?(node: FairCore.XMLNode) throws {
            let attr = { node.attributeValue(key: $0, namespaceURI: sparkle) }
            self.version = attr("version")
            self.shortVersionString = attr("shortVersionString")
            self.edSignature = attr("edSignature")
            self.dsaSignature = attr("dsaSignature")
            self.deltaFrom = attr("deltaFrom")
            self.installationType = attr("installationType")
            self.os = attr("os")
        }
    }
}

extension WebFeed.Channel.Item where Additions == AppcastWebFeedAdditions {

    /// https://sparkle-project.org/documentation/api-reference/Classes/SUAppcastItem.html#/c:objc(cs)SUAppcastItem(py)displayVersionString
    var displayVersionString: String? {

        enclosures.compactMap(\.shortVersionString).first
    }
}

extension WebFeed.Channel.Enclosure where Additions == AppcastWebFeedAdditions {
    var version: String? { additions?.version }
    var shortVersionString: String? { additions?.shortVersionString }
    var edSignature: String? { additions?.edSignature }
    var dsaSignature: String? { additions?.dsaSignature }
}

extension ProcessInfo {
    /// Returns `true` if we are running on an ARM Mac, even if we are running under Rosetta emulation
    static let isArmMac: Bool = {
        var cpu_type: cpu_type_t = 0
        var cpu_type_size = MemoryLayout.size(ofValue: cpu_type)
        if -1 == sysctlbyname("hw.cputype", &cpu_type, &cpu_type_size, nil, 0) {
            return false // should not happen
        }

        if (cpu_type & CPU_TYPE_ARM) == CPU_TYPE_ARM {
            return true
        }

        // When the app is running under Rosetta, hw.cputype reports an Intel CPU
        // We want to know the real CPU type, so we have to check for Rosetta
        // If we detect Rosetta, we are running on ARM
        var is_translated: Int = 0;
        var is_translated_size = MemoryLayout.size(ofValue: is_translated)
        if -1 == sysctlbyname("sysctl.proc_translated", &is_translated, &is_translated_size, nil, 0) {
            // if this call fails we are probably running on Intel
            return false
        }
        else if is_translated != 0 {
            // process is translated with Rosetta -> we must be on ARM
            return true
        }
        else {
            return false
        }
    }()
}

/// ```{"category":"cask_install","total_items":6190,"start_date":"2021-12-05","end_date":"2022-01-04","total_count":894812,"items":[{"number":1,"cask":"google-chrome","count":"34,530","percent":"3.86"},{"number":2,"cask":"iterm2","count":"31,096","percent":"3.48"},{"number":6190,"cask":"zulufx11","count":"1","percent":"0"}]}```
/// https://formulae.brew.sh/docs/api/#list-analytics-events-for-all-cask-formulae
private struct CaskStats : Equatable, Decodable {
    /// E.g., `cask_install`
    let category: String

    /// E.g., `6190`
    let total_items: Int

    /// E.g., `2021-12-05`
    let start_date: String

    /// E.g., `2022-01-04`
    let end_date: String

    /// E.g., `894812`
    let total_count: Int

    /// Note that the docs call this `items`(see [API Docs](https://formulae.brew.sh/docs/api/#response-5)), but the API returns `formulae`.
    let formulae: [String: [Stat]]

    /// `{"number":1,"cask":"google-chrome","count":"34,530","percent":"3.86"}`
    struct Stat : Equatable, Decodable {
        let cask: String
        let count: Int

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.cask = try values.decode(String.self, forKey: .cask)
            /// The `count` field should be a number, but is appears to be a numeric string (US localized with commas), but since it ought to be a number and maybe someday will be, also permit a number
            do {
                self.count = try values.decode(Int.self, forKey: .count)
            } catch {
                let stringCount = try values.decode(String.self, forKey: .count)
                self.count = Self.formatter.number(from: stringCount)?.intValue ?? 0
            }
        }

        enum CodingKeys : String, CodingKey {
            case cask
            case count
        }

        private static let formatter: NumberFormatter = {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.isLenient = true
            fmt.locale = Locale(identifier: "en_US")
            return fmt
        }()
    }
}

/// A Homebrew Cask, as defined by the API specification at [https://formulae.brew.sh/docs/api/#get-formula-metadata-for-a-cask-formula](https://formulae.brew.sh/docs/api/#get-formula-metadata-for-a-cask-formula)
struct CaskItem : Equatable, Decodable {
    /// The token of the cask. E.g., `alfred`
    let token: String

    /// E.g., `4.6.1,1274`
    let version: String

    /// E.g., `["Alfred"]`
    let name: [String]

    /// E.g., `"Application launcher and productivity software"`
    let desc: String?

    /// E.g., `https://www.alfredapp.com/`
    let homepage: String?

    /// E.g., `https://cachefly.alfredapp.com/Alfred_4.6.1_1274.dmg`
    let url: String?

    /// E.g., `alfred` or `appfair/app/bon-mot`
    let full_token: String

    /// E.g., `homebrew/cask` or `appfair/app`
    let tap: String?

    /// E.g., `https://nucleobytes.com/4peaks/index.html`
    let appcast: String?

    /// E.g., `5.8.3.2240`
    let installed: String? // always nil when taken from API

    // TODO
    // let versions": {},

    // let outdated: false // not relevent for API

    /// The SHA-256 hash of the artifact.
    private let sha256: String

    /// Returns the checksum unless it is the "no_check" constant or does not otherwise appear to be a checksum
    var checksum: String? {
        //let validCharacters = CharacterSet(charactersIn: "")
        sha256 == "no_check" || sha256.count != 64 ? nil : sha256
    }

    /// E.g.: `app has been officially discontinued upstream`
    let caveats: String?

    let auto_updates: Bool?

    // "artifacts":[["Signal.app"],{"trash":["~/Library/Application Support/Signal","~/Library/Preferences/org.whispersystems.signal-desktop.helper.plist","~/Library/Preferences/org.whispersystems.signal-desktop.plist","~/Library/Saved Application State/org.whispersystems.signal-desktop.savedState"],"signal":{}}]
    typealias ArtifactItem = XOr<Array<ArtifactNameTarget>>.Or<JSum>

    let artifacts: Array<ArtifactItem>?

    /// Either the raw name of an app, or the target of the app
    typealias ArtifactNameTarget = XOr<ArtifactTarget>.Or<String>

    /// A target for the app, typically part of a hetergeneous array when the installed name of the app differs from the canonical name of the app
    /// E.g.: `["Eclipse.app", { "target": "Nodeclipse.app" } ]`
    struct ArtifactTarget : Equatable, Decodable {
        var target: String
    }

    /// `depends_on` is used to declare dependencies and requirements for a Cask. `depends_on` is not consulted until install is attempted.
    let depends_on: DependsOn?

    struct DependsOn : Equatable, Decodable {
        let cask: [String]?

        /// E.g., `{"macos":{">=":["10.12"]}}`
        // let macOS: XOr<Array<String>>.Or<String>?
    }

    /// E.g.: `"conflicts_with":{"cask":["homebrew/cask-versions/1password-beta"]}`
    // let conflicts_with: null
    
    /// E.g.: `"container":"{:type=>:zip}"`
    // let container": null,

    /// Possible model for https://github.com/Homebrew/brew/issues/12786
//    private let files: [FileItem]?
//    private struct FileItem : Equatable, Decodable {
//        /// E.g., "arm64" or "x86"
//        let arch: String?
//        let url: String?
//        let sha256: String?
//    }
}


extension CaskItem : Identifiable {

    /// The ID of a `CaskItem` is the `tapToken`
    var id: String { tapToken }

    /// Returns the fully-qualified token. E.g., `homebrew/cask/iterm2`
    var tapToken: String {
        if full_token.contains("/") {
            return full_token
        } else {
            return (tap ?? "") + "/" + full_token
        }
    }

    /// The URL that points to the Hub's spec for the token.
    /// 
    /// e.g.: homebrew/cask/iterm2 or appfair/app/bon-mot
    var tapURL: URL? {
        let parts = tapToken.split(separator: "/")
        if parts.count == 3 {
            let base = parts[0]
            let cask = parts[1]
            let token = parts[2]
            return URL(string: "https://github.com/\(base)/\(base)-\(cask)/blob/HEAD/Casks/\(token).rb")
        } else {
            return nil
        }
    }

    /// Returns the list of artifacts that contain an ".app" path
    var appArtifacts: [String] {
        var appNames: [String] = []

        /// Extracts the target name from the `ArtifactNameTarget`
        func targetName(for nameTarget: ArtifactNameTarget) -> String {
            switch nameTarget {
            case .p(let x): return x.target
            case .q(let x): return x
            }
        }

        for artifactLists in (self.artifacts ?? []).compactMap({ $0.infer() as [ArtifactNameTarget]? }) {
            for var potentialAppName in artifactLists.map(targetName) {
                //dbg("checking app:", potentialAppName)
                // some artifacts are full paths to the binary, like: /Applications/Nextcloud.app/Contents/MacOS/nextcloudcmd
                while potentialAppName.count > 1 && !potentialAppName.hasSuffix(".app") {
                    potentialAppName = (potentialAppName as NSString).deletingLastPathComponent
                }
                if potentialAppName.hasSuffix(".app") {
                    appNames.append(potentialAppName)
                }
            }
        }
        return appNames
    }
}

/// A unique identifier for a bundle. Note that this overloads the "BundleIdentifier" concept, which may make more sense
typealias CaskIdentifier = BundleIdentifier

extension CaskIdentifier {
    /// Returns true if this is a homebrew cask (vs. a fairapp)
    var isCaskApp: Bool {
        rawValue.hasPrefix("homebrew/cask/")
    }

    var caskToken: String? {
        if rawValue.hasPrefix("homebrew/cask/") {
            return String(rawValue.dropFirst(14))
        } else {
            return nil
        }
    }
}
