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
import FairApp
import FairExpo
import Dispatch
import Security
import Foundation

#if os(macOS)
let displayExtensions: Set<String>? = ["zip"]
let catalogURL: URL = appfairCatalogURLMacOS
#endif

#if os(iOS)
let displayExtensions: Set<String>? = ["ipa"]
let catalogURL: URL = appfairCatalogURLIOS
#endif

/// Whether to remember the response to a prompt or not;
enum PromptSuppression : Int, CaseIterable {
    /// The user has not specified whether to remember the response
    case unset
    /// The user specified that the the response should always the confirmation response
    case confirmation
    /// The user specified that the the response should always be the destructive response
    case destructive
}

extension ObservableObject {
    /// Issues a prompt with the given parameters, returning whether the user selected OK or Cancel
    @MainActor func prompt(_ style: NSAlert.Style = .informational, window sheetWindow: NSWindow? = nil, messageText: String, informativeText: String? = nil, accept: String = NSLocalizedString("OK", bundle: .module, comment: "default button title for prompt"), refuse: String = NSLocalizedString("Cancel", bundle: .module, comment: "cancel button title for prompt"), suppressionTitle: String? = nil, suppressionKey: Binding<PromptSuppression>? = nil) async -> Bool {

        let window = sheetWindow ?? NSApp.currentEvent?.window ?? NSApp.keyWindow ?? NSApp.mainWindow

        if let suppressionKey = suppressionKey {
            switch suppressionKey.wrappedValue {
            case .confirmation: return true
            case .destructive: return false
            case .unset: break // show prompt
            }
        }

        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = messageText
        if let informativeText = informativeText {
            alert.informativeText = informativeText
        }
        alert.addButton(withTitle: accept)
        alert.addButton(withTitle: refuse)

        if let suppressionTitle = suppressionTitle {
            alert.suppressionButton?.title = suppressionTitle
        }
        alert.showsSuppressionButton = suppressionKey != nil

        let response: NSApplication.ModalResponse
        if let window = window {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal() // note that this tends to crash even when called from the main thread with: Assertion failure in -[NSApplication _commonBeginModalSessionForWindow:relativeToWindow:modalDelegate:didEndSelector:contextInfo:]
        }

        // remember the response if we have prompted to do so
        if let suppressionKey = suppressionKey, alert.suppressionButton?.state == .on {
            switch response {
            case .alertFirstButtonReturn: suppressionKey.wrappedValue = .confirmation
            case .alertSecondButtonReturn: suppressionKey.wrappedValue = .destructive
            default: break
            }
        }

        return response == .alertFirstButtonReturn
    }
}

private let showPreReleasesDefault = false
private let relaunchUpdatedAppsDefault = true
private let riskFilterDefault = AppRisk.risky
private let autoUpdateCatalogAppDefault = true
private let relaunchUpdatedCatalogAppDefault = PromptSuppression.unset

/// The manager for installing App Fair apps
@available(macOS 12.0, iOS 15.0, *)
@MainActor public final class FairAppInventory: ObservableObject, AppInventory {
    /// The list of currently installed apps of the appID to the Info.plist (or error)
    @Published private var installedApps: [BundleIdentifier : Result<Plist, Error>] = [:]

    /// The current catalog of apps
    @Published var catalog: [AppCatalogItem] = []

    /// The date the catalog was most recently updated
    @Published private(set) var catalogUpdated: Date? = nil

    /// The number of outstanding update requests
    @Published var updateInProgress: UInt = 0

    @AppStorage("showPreReleases") var showPreReleases = showPreReleasesDefault

    @AppStorage("relaunchUpdatedApps") var relaunchUpdatedApps = relaunchUpdatedAppsDefault

    @AppStorage("riskFilter") var riskFilter = riskFilterDefault

    @AppStorage("autoUpdateCatalogApp") public var autoUpdateCatalogApp = autoUpdateCatalogAppDefault

    /// Whether to automatically re-launch the catalog app when it has updated itself
    @AppStorage("relaunchUpdatedCatalogApp") var relaunchUpdatedCatalogApp = relaunchUpdatedCatalogAppDefault

    @Published public var errors: [AppError] = []

    /// Resets all of the `@AppStorage` properties to their default values
    func resetAppStorage() {
        self.showPreReleases = showPreReleasesDefault
        self.relaunchUpdatedApps = relaunchUpdatedAppsDefault
        self.riskFilter = riskFilterDefault
        self.autoUpdateCatalogApp = autoUpdateCatalogAppDefault
        self.relaunchUpdatedCatalogApp = relaunchUpdatedCatalogAppDefault
    }

    /// Register that an error occurred with the app manager
    func reportError(_ error: Error) {
        errors.append(error as? AppError ?? AppError(error))
    }

    static let `default`: FairAppInventory = FairAppInventory()

    private var fsobserver: FileSystemObserver? = nil

    private init() {
        if FileManager.default.isDirectory(url: Self.installFolderURL) == false {
            Task {
                try? await Self.createInstallFolder()
            }
        }

        // set up a file-system observer for the install folder, which will refresh the installed apps whenever any changes are made; this allows external processes like homebrew to update the installed app
        if FileManager.default.isDirectory(url: Self.installFolderURL) == true {
            self.fsobserver = FileSystemObserver(URL: Self.installFolderURL, queue: .main) {
                dbg("changes detected in app folder:", Self.installFolderURL.path)
                Task {
                    await self.scanInstalledApps()
                }
            }
        }
    }

    func refreshAll(clearCatalog: Bool) async throws {
        if clearCatalog {
            self.catalog = []
        }
        
        self.updateInProgress += 1
        defer { self.updateInProgress -= 1 }

        async let v0: () = scanInstalledApps()
        async let v1: () = fetchApps(cache: .reloadIgnoringLocalAndRemoteCacheData)
        let _ = await (v0, v1)
    }
}

/// An activity and progress
class CatalogOperation {
    let activity: CatalogActivity
    var progress: Progress

    init(activity: CatalogActivity, progress: Progress = Progress()) {
        self.activity = activity
        self.progress = progress
    }
}

enum CatalogActivity : CaseIterable, Equatable {
    case install
    case update
    case trash
    case reveal
    case launch
}


@available(macOS 12.0, iOS 15.0, *)
extension FairAppInventory {
    func fetchApps(cache: URLRequest.CachePolicy? = nil) async {
        do {
            dbg("loading catalog")
            let start = CFAbsoluteTimeGetCurrent()
            let (catalog, response) = try await FairHub.fetchCatalog(catalogURL: catalogURL, cache: cache)
            self.catalog = catalog.apps
            self.catalogUpdated = response.lastModifiedDate

            let end = CFAbsoluteTimeGetCurrent()
            dbg("fetched catalog:", catalog.apps.count, "in:", (end - start))
            if autoUpdateCatalogApp == true {
                try await updateCatalogApp()
            }
        } catch {
            Task { // otherwise warnings about accessing off of the main thread
                // errors here are not unexpected, since we can get a `cancelled` error if the view that initiated the `fetchApps` request
                dbg("received error:", error)
                // we tolerate a "cancelled" error because it can happen when a view that is causing a catalog load is changed and its request gets automaticallu cancelled
                if error.isURLCancelledError {
                } else {
                    self.reportError(error)
                }
            }
        }
    }

    /// The app info for the current app (which is the catalog browser app)
    var catalogAppInfo: AppCatalogItem? {
        appInfoItems(includePrereleases: false).first(where: { info in
            info.bundleIdentifier.rawValue == Bundle.main.bundleIdentifier
        })
    }

    /// If the catalog app is updated,
    private func updateCatalogApp(catalogAppBundle: Bundle = Bundle.main) async throws {
        // auto-update the App Fair app itself to the latest non-pre-release version
        guard let catalogApp = self.catalogAppInfo else {
            return dbg("could not locate current app in app list")
        }

        // if the release version is greater than the installed version, download and install it automatically
        // let installedCatalogVersion = installedVersion(for: catalogApp.id) // we should use the currently-running version as the authoritative version for checking
        let installedCatalogVersion = catalogAppBundle.bundleVersionString.flatMap { AppVersion(string: $0, prerelease: false) }

        dbg("checking catalog app update from installed version:", installedCatalogVersion?.versionString, "to:", catalogApp.releasedVersion?.versionString, "at:", catalogAppBundle.bundleURL.path)

        // only update the App Fair catalog manager app when it has been placed in the /Applications/ folder. This prevents updating while running while developing.
        #if DEBUG
        if catalogAppBundle.executablePath?.hasPrefix(Self.applicationsFolderURL.path) != true {
            // only skip update while debugging
            return dbg("skipping DEBUG update to catalog app:", catalogAppBundle.executablePath, "since it is not installed in the applications folder:", Self.applicationsFolderURL.path)
        }
        #endif

        if (catalogApp.releasedVersion ?? .min) > (installedCatalogVersion ?? .min) {
            try await install(item: catalogApp, progress: nil, update: true, removingURLAt: catalogAppBundle.bundleURL)
        }
    }

    /// All the app-info items, sorted and filtered based on whether to include pre-releases.
    ///
    /// - Parameter includePrereleases: when `true`, versions marked `beta` will superceed any non-`beta` versions.
    /// - Returns: the list of apps, including all the installed apps, as well as matching pre-leases
    func appInfoItems(includePrereleases: Bool) -> [AppCatalogItem] {

        // multiple instances of the same bundleID can exist for "beta" set to `false` and `true`;
        // the visibility of these will be controlled by whether we want to display pre-releases
        let bundleAppInfoMap: [BundleIdentifier: [AppCatalogItem]] = catalog
            .grouping(by: \.bundleIdentifier)

        // need to cull duplicates based on the `beta` flag so we only have a single item with the same CFBundleID
        let infos = bundleAppInfoMap.values.compactMap({ appInfos in
            appInfos
                .filter { item in
                    // "beta" apps are are included when the pre-release flag is set
                    includePrereleases == true || item.beta == false // || item.installedPlist != nil
                }
                .sorting(by: \.releasedVersion, ascending: false, noneFirst: true) // the latest release comes first
                .first // there can be only a single bundle identifier in the list for Identifiable
        })

        return infos.sorting(by: \.bundleIdentifier) // needs to return in constant order
    }

    /// The items arranged for the given category with the specifed sort order and search text
    func arrangedItems(sidebarSelection: SidebarSelection?, sortOrder: [KeyPathComparator<AppInfo>], searchText: String) -> [AppInfo] {
        self
            .appInfoItems(includePrereleases: showPreReleases || sidebarSelection?.item == .installed)
            .filter({ matchesExtension(item: $0) })
            .filter({ sidebarSelection?.item.isLocalFilter == true || matchesRiskFilter(item: $0) })
            .filter({ matchesSearch(item: $0, searchText: searchText) })
            .filter({ selectionFilter(sidebarSelection, item: $0) }) // TODO: fix categories for app item
            .map({ AppInfo(catalogMetadata: $0) })
            .sorted(using: sortOrder + categorySortOrder(category: sidebarSelection?.item))
    }

    func categorySortOrder(category: SidebarItem?) -> [KeyPathComparator<AppInfo>] {
        switch category {
        case .none:
            return []
        case .top:
            return [KeyPathComparator(\AppInfo.catalogMetadata.downloadCount, order: .reverse)]
        case .recent:
            return [KeyPathComparator(\AppInfo.catalogMetadata.versionDate, order: .reverse)]
        case .updated:
            return [KeyPathComparator(\AppInfo.catalogMetadata.versionDate, order: .reverse)]
        case .installed:
            return [KeyPathComparator(\AppInfo.catalogMetadata.name, order: .forward)]
        case .category:
            return [KeyPathComparator(\AppInfo.catalogMetadata.starCount, order: .reverse), KeyPathComparator(\AppInfo.catalogMetadata.downloadCount, order: .reverse)]
        }
    }

    func matchesExtension(item: AppCatalogItem) -> Bool {
        displayExtensions?.contains(item.downloadURL.pathExtension) != false
    }

    func matchesRiskFilter(item: AppCatalogItem) -> Bool {
        item.riskLevel <= riskFilter
    }

    func matchesSearch(item: AppCatalogItem, searchText: String) -> Bool {
        let txt = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if txt.count < minimumSearchLength {
            return true
        }

        func matches(_ string: String?) -> Bool {
            string?.localizedCaseInsensitiveContains(txt) == true
        }

        if matches(item.bundleIdentifier.rawValue) { return true }
        
        if matches(item.name) { return true }
        if matches(item.subtitle) { return true }
        if matches(item.developerName) { return true }
        if matches(item.localizedDescription) { return true }
        
        return false
    }

    /// The main folder for apps
    static var applicationsFolderURL: URL {
        (try? FileManager.default.url(for: .applicationDirectory, in: .localDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: "/Applications")
    }

    /// The folder where App Fair apps will be installed
    static var installFolderURL: URL {
        // we would like the install folder to be the same-named peer of the app's location, allowing it to run in `~/Downloads/` (which would place installed apps in `~/Downloads/App Fair`)
        // however, app translocation prevents it from knowing its location on first launch, and so we can't rely on being able to install as a peer without nagging the user to first move the app somewhere (thereby exhausting translocation)
        // Bundle.main.bundleURL.deletingPathExtension()
        URL(fileURLWithPath: Bundle.mainBundleName, relativeTo: applicationsFolderURL)
    }

    /// Launch the local installed copy of this app
    func launch(item: AppCatalogItem) async {
        do {
            dbg("launching:", item.name)
            guard let installPath = installedPath(for: item) else {
                throw Errors.appNotInstalled(item)
            }

            dbg("launching:", installPath)

#if os(macOS)
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true

            try await NSWorkspace.shared.openApplication(at: installPath, configuration: cfg)
#else
            throw Errors.launchAppNotSupported
#endif
        } catch {
            dbg("error performing launch for:", item, "error:", error)
            self.reportError(error)
        }
    }

    static let appSuffix = ".app"
    
    /// Returns the installed path for this app; this will always be
    /// `/Applications/Fair Ground/App Name.app`, except for the
    /// `Fair Ground.app` catalog app itself, which will be at:
    /// `/Applications/Fair Ground.app`.scanInstalledApps
    static func appInstallPath(for item: AppCatalogItem) -> URL {
        // e.g., "App Fair.app" matches "/Applications/App Fair"
        URL(fileURLWithPath: item.name + appSuffix, isDirectory: true, relativeTo: installFolderURL.lastPathComponent == item.name ? installFolderURL.deletingLastPathComponent() : installFolderURL)
    }

    /// The catalog app itself is the same as the name of the install path with the ".app" suffix
    static var catalogAppURL: URL {
        URL(fileURLWithPath: installFolderURL.lastPathComponent + appSuffix, relativeTo: installFolderURL.deletingLastPathComponent())
    }

    /// The bundle IDs for all the installed apps
    var installedBundleIDs: Dictionary<BundleIdentifier, Result<Plist, Error>>.Keys {
        installedApps.keys
    }

    func installedVersion(for id: BundleIdentifier) -> AppVersion? {
        installedInfo(for: id)?.appVersion
    }

    /// Returns the installed Plist for the given bundle identifier
    func installedInfo(for id: BundleIdentifier) -> Plist? {
        installedApps.values.first { result in
            result.successValue?.CFBundleIdentifier == id.rawValue
        }?.successValue
    }

    static func createInstallFolder() async throws {
        // always try to ensure the install folder is created (in case the user clobbers the app install folder while we are running)
        // FIXME: this will always fail, since the ownership & permissions of /Applications/ cannot be changed
        try await withPermission(installFolderURL.deletingLastPathComponent()) { _ in
            try FileManager.default.createDirectory(at: installFolderURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Attempts to perform the given action and adds any errors to the error list if they fail.
    func trying(block: () async throws -> ()) async {
        do {
            try await block()
        } catch {
            reportError(error)
        }
    }

    func scanInstalledApps() async {
        dbg()
        do {
            let start = CFAbsoluteTimeGetCurrent()
            try? await Self.createInstallFolder()
            var installPathContents = try FileManager.default.contentsOfDirectory(at: Self.installFolderURL, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .producesRelativePathURLs]) // producesRelativePathURLs are critical so these will match the url returned from appInstallPath
            installPathContents.append(Self.catalogAppURL)

            var installedApps = self.installedApps
            installedApps.removeAll() // clear the list
            for installPath in installPathContents {
                if installPath.pathExtension != "app" {
                    continue
                }
                if FileManager.default.isDirectory(url: installPath) != true {
                    continue
                }
                let infoPlist = installPath.appendingPathComponent("Contents/Info.plist")
                do {
                    let plist = try Plist(data: Data(contentsOf: infoPlist))
                    if let bundleID = plist.bundleID {
                        // here was can validate some of the app's metadata, version number, etc
                        installedApps[.init(bundleID)] = .success(plist)
                    }
                } catch {
                    dbg("error parsing Info.plist for:", installPath.path, error)
                    // installedApps[installPath] = .failure(error)
                }
            }

            self.installedApps = installedApps
            let end = CFAbsoluteTimeGetCurrent()
            dbg("scanned", installedApps.count, "apps in:", end - start, installedBundleIDs.map(\.rawValue))
        } catch {
            dbg("error performing re-scan:", error)
            self.reportError(error)
        }
    }

    /// The `appInstallPath`, or nil if it does not exist
    func installedPath(for item: AppCatalogItem) -> URL? {
        Self.appInstallPath(for: item).asDirectory
    }

    /// Trashes the local installed copy of this app
    func delete(item: AppCatalogItem, verbose: Bool = true) async throws {
        dbg("trashing:", item.name)
        guard let installPath = installedPath(for: item) else {
            throw Errors.appNotInstalled(item)
        }

        try await trash(installPath)
        // always re-scan after altering apps
        await scanInstalledApps()
    }

    /// Reveals the local installed copy of this app using the finder
    func reveal(item: AppCatalogItem) async throws {
        dbg("revealing:", item.name)
        guard let installPath = installedPath(for: item) else {
            throw Errors.appNotInstalled(item)
        }
        dbg("revealing:", installPath.path)

#if os(macOS)
        // NSWorkspace.shared.activateFileViewerSelecting([installPath]) // unreliable
        NSWorkspace.shared.selectFile(installPath.path, inFileViewerRootedAtPath: Self.installFolderURL.path)
#endif
    }

    /// Install or update the given catalog item.
    func install(item: AppCatalogItem, progress parentProgress: Progress?, update: Bool, verbose: Bool = true, removingURLAt: URL? = nil) async throws {
        let window = NSApp.currentEvent?.window

        if update == false, let installPath = installedPath(for: item) {
            throw Errors.appAlreadyInstalled(installPath)
        }

        try Task.checkCancellation()
        let (downloadedArtifact, downloadSha256) = try await downloadArtifact(url: item.downloadURL, progress: parentProgress)
        try Task.checkCancellation()

        // grab the hash of the download to compare against the fairseal
        dbg("comparing fairseal expected:", item.sha256, "with actual:", downloadSha256)
        if item.sha256 != downloadSha256.hex() {
            throw AppError("Invalid fairseal", failureReason: "The app's fairseal was not valid.")
        }

        try Task.checkCancellation()

        let t1 = CFAbsoluteTimeGetCurrent()
        let expandURL = downloadedArtifact.appendingPathExtension("expanded")

        let progress2 = Progress(totalUnitCount: 1)
        parentProgress?.addChild(progress2, withPendingUnitCount: 0)

        try FileManager.default.unzipItem(at: downloadedArtifact, to: expandURL, skipCRC32: false, progress: progress2, preferredEncoding: .utf8)
        try FileManager.default.removeItem(at: downloadedArtifact)
        try FileManager.default.clearQuarantine(at: expandURL)

        try Task.checkCancellation()

        let t2 = CFAbsoluteTimeGetCurrent()

        // try Process.removeQuarantine(appURL: expandURL) // xattr: [Errno 1] Operation not permitted: '/var/folders/app.App-Fair/CFNetworkDownload_XXX.tmp.expanded/Some App.app'

        let shallowFiles = try FileManager.default.contentsOfDirectory(at: expandURL, includingPropertiesForKeys: nil, options: [])
        dbg("unzipped:", downloadedArtifact.path, "to:", shallowFiles.map(\.lastPathComponent), "in:", t2 - t1)

        if shallowFiles.count != 1 {
            throw Errors.tooManyInstallFiles(item.downloadURL)
        }
        guard let expandedAppPath = shallowFiles.first(where: { $0.pathExtension == "app" }) else {
            throw Errors.noAppContents(item.downloadURL)
        }

        try Task.checkCancellation()

        // perform as much validation as possible before we attempt the install
        try self.validate(appPath: expandedAppPath, forItem: item)

        let installPath = Self.appInstallPath(for: item)
        let installFolderURL = installPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: installFolderURL, withIntermediateDirectories: true, attributes: nil)

        let destinationURL = installFolderURL.appendingPathComponent(expandedAppPath.lastPathComponent)

        // if we permit updates and it is already installed, trash the previous version
        if update && FileManager.default.isDirectory(url: destinationURL) == true {
            // TODO: first rename based on the old version number
            dbg("trashing:", destinationURL.path)
            try await trash(destinationURL)
        }

        try Task.checkCancellation()

        if let removingURLAt = removingURLAt {
            // if we've specified a URL that is being replaced, try to delete it; this is to support being able to update the App Fair.app from the Downloads folder; the app will be installed in /Applications, but the launched application should be the one that is deleted
            do {
                try await trash(removingURLAt)
            } catch {
                // tolerate errors, which may result from translocation issues
                dbg("error removingURLAt:", removingURLAt.path)
            }
            try Task.checkCancellation()
        }

        dbg("installing:", expandedAppPath.path, "into:", destinationURL.path)
        try await Self.withPermission(installFolderURL) { installFolderURL in
            // try FileManager.default.replaceItemAt(destinationURL, withItemAt: expandedAppPath)
            try FileManager.default.moveItem(at: expandedAppPath, to: destinationURL)
        }
        if let parentProgress = parentProgress {
            parentProgress.completedUnitCount = parentProgress.totalUnitCount - 1
        }

        // always re-scan after altering apps
        await scanInstalledApps()

        if let parentProgress = parentProgress {
            parentProgress.completedUnitCount = parentProgress.totalUnitCount
        }

        if self.relaunchUpdatedApps == true {
            // the catalog app is special, since re-launching requires quitting the current app
            let isCatalogApp = item.bundleIdentifier.rawValue == Bundle.main.bundleID

            @MainActor func relaunch() {
                dbg("re-launching app:", item.bundleIdentifier)
                terminateAndRelaunch(bundleID: item.bundleIdentifier, force: false, overrideLaunchURL: isCatalogApp ? destinationURL : nil)
            }

            if !isCatalogApp {
                // automatically re-launch any app that isn't a catalog app
                relaunch()
            } else {
                // if this is the catalog app, prompt the user to re-launch
                let response = await prompt(window: window,
                                            messageText: String(format: NSLocalizedString("App Fair has been updated", bundle: .module, comment: "app updated dialog title")),
                                            informativeText: String(format: NSLocalizedString("This app has been updated from %@ to the latest version %@. Would you like to re-launch it?", bundle: .module, comment: "app updated dialog body"), Bundle.main.bundleVersionString ?? "?", item.version ?? "?"),
                                            accept: NSLocalizedString("Re-launch", bundle: .module, comment: "app updated re-launch button text"),
                                            refuse: NSLocalizedString("Later", bundle: .module, comment: "app updated skip relaunch button text"),
                                            suppressionKey: $relaunchUpdatedCatalogApp)
                dbg("prompt response:", response)
                if response == true {
                    relaunch()
                }
            }
        }
    }

    private func trash(_ fileURL: URL) async throws {
        // perform privilege escalation if needed
        let trashedURL = try await Self.withPermission(fileURL) { fileURL in
            try FileManager.default.trash(url: fileURL)
        }
        dbg("trashed:", fileURL.path, "to:", trashedURL?.path)
    }

    /// Kills the process with the given `bundleID` and re-launches it.
    private func terminateAndRelaunch(bundleID: BundleIdentifier, force: Bool, overrideLaunchURL: URL? = nil) {
#if os(macOS)
        // re-launch the current app once it has been killed
        // note that NSRunningApplication cannot be used from a sandboxed app
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID.rawValue).first, let bundleURL = runningApp.bundleURL {
            dbg("runningApp:", runningApp)
            // when the app is this process (i.e., the catalog browser), we need to re-start using a spawned shell script
            let pid = runningApp.processIdentifier

            // spawn a script that waits for the pid to die and then re-launches it
            // we need to do this prior to attempting termination, since we may be terminating ourself
            let relaunch = "(while /bin/kill -0 \(pid) >&/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"\((overrideLaunchURL ?? bundleURL).path)\") &"
            Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", relaunch])

            // Note: “Sandboxed applications can’t use this method to terminate other applciations [sic]. This method returns false when called from a sandboxed application.”
            let terminated = force ? runningApp.forceTerminate() : runningApp.terminate()
            dbg(terminated ? "successful" : "unsuccessful", "termination")
        } else {
            dbg("no process identifier for:", bundleID)
        }
#endif // #if os(macOS)
    }

    /// Performs the given operation, and if it fails, try again after attempting a privileged operation to change the owner of the file to the current user.
    private static func withPermission<T>(_ fileURL: URL, recursive: Bool = false, block: (URL) throws -> T) async throws -> T {
        do {
            // attempt the operation without any privilege escalation first
            return try block(fileURL)
        } catch {
            #if os(macOS)
            func reauthorize(_ error: Error) async throws -> T {
                // we have a few options here:
                // 1. [SMJobBless](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) and an XPC helper; cumbersome, and has inherent security flaws as discussed at: [](https://blog.obdev.at/what-we-have-learned-from-a-vulnerability/)
                // 2. [AuthorizationExecuteWithPrivileges](https://developer.apple.com/documentation/security/1540038-authorizationexecutewithprivileg) deprecated and un-available in swift (although the symbol can be manually coerced)
                // 3. NSAppleScript using "with administrator privileges"

                let output = try await NSUserScriptTask.fork(command: "/usr/sbin/chown \(recursive ? "-R" : "") $USER '\(fileURL.path)'", admin: true)
                dbg("successfully executed script:", output)
                // now try-try the operation with the file's permissions corrected
                return try block(fileURL)
            }

            if let error = error as? CocoaError {
                if error.code == .fileReadNoPermission
                    || error.code == .fileWriteNoPermission {
                    // e.g.: withPermission: file permission error: CocoaError(_nsError: Error Domain=NSCocoaErrorDomain Code=513 "“Pan Opticon.app” couldn’t be moved to the trash because you don’t have permission to access it." UserInfo={NSURL=./Pan%20Opticon.app/ -- file:///Applications/App%20Fair/, NSUserStringVariant=(Trash), NSUnderlyingError=0x600001535680 {Error Domain=NSOSStatusErrorDomain Code=-5000 "afpAccessDenied: Insufficient access privileges for operation "}})
                    dbg("file permission error: \(error)")
                    return try await reauthorize(error)
                } else {
                    dbg("non-file permission error: \(error)")
                    // should we reauth for any error? E.g., `.fileWriteFileExists`? For now, be conservative and only attempt to change the permissions when we are sure the failure was due to a system file read/write error
                    // return try reauthorize(error)
                    throw error
                }
            }
            #endif
            throw error
        }
    }

    func validate(appPath: URL, forItem release: AppCatalogItem) throws {
        let appPathName = appPath.deletingPathExtension().lastPathComponent
        if appPathName != release.name {
            throw Errors.wrongAppName(appPathName, release.name)
        }
    }

    enum Errors : Error {
        /// Launching apps is not supported on this platform
        case launchAppNotSupported
        /// An operation assumed the app was not installed, but it was
        case appAlreadyInstalled(URL)
        /// The expected install path was not the name of the app to be installed
        case wrongAppName(String, String)
        /// An operation assumed the app was installed, but it wasn't
        case appNotInstalled(AppCatalogItem)
        /// A problem occurred with unzipping the file
        case unableToLoadZip(URL)
        /// When there are more install files than expected
        case tooManyInstallFiles(URL)
        /// When the zip archive is empty
        case noAppContents(URL)
    }
}

extension AppInventory {

    /// Downloads the artifact for the given catalog item.
    func downloadArtifact(url: URL, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0, headers: [String: String] = [:], progress parentProgress: Progress?) async throws -> (downloadedArtifact: URL, sha256: Data) {
        let t1 = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)

        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        parentProgress?.kind = .file
        parentProgress?.fileOperationKind = .downloading

        let hasher = SHA256Hasher()
        let (downloadedArtifact, response) = try await URLSession.shared.download(request: request, memoryBufferSize: 1024 * 64, consumer: hasher, parentProgress: parentProgress)
        let downloadSha256 = await hasher.final()

        let t2 = CFAbsoluteTimeGetCurrent()

        dbg("downloaded:", downloadedArtifact.fileSize()?.localizedByteCount(), t2 - t1, (response as? HTTPURLResponse)?.statusCode)
        return (downloadedArtifact, downloadSha256)
    }
}

extension FairHub {
#if swift(>=5.5)
    /// Fetches the `AppCatalog`
    @available(macOS 12.0, iOS 15.0, *)
    public static func fetchCatalog(catalogURL: URL, cache: URLRequest.CachePolicy? = nil) async throws -> (catalog: AppCatalog, response: URLResponse) {
        dbg("fetching async", catalogURL)

        var req = URLRequest(url: catalogURL)
        if let cache = cache { req.cachePolicy = cache }
        let (data, response) = try await URLSession.shared.data(for: req, delegate: nil)

        let catalog = try AppCatalog.parse(jsonData: data)

        return (catalog, response)
    }
#endif // swift(>=5.5)
}

@available(macOS 12.0, iOS 15.0, *)
extension FairAppInventory {
    typealias Item = URL

    func updateCount() -> Int {
        appInfoItems(includePrereleases: showPreReleases).filter { item in
            appUpdated(item: item)
        }
        .count
    }

    func appInstalled(item: AppCatalogItem) -> String? {
        installedInfo(for: item.bundleIdentifier)?.versionString
    }

    func appUpdated(item: AppCatalogItem) -> Bool {
        // (appPropertyList?.successValue?.appVersion ?? .max) < (info.releasedVersion ?? .min)
        (installedVersion(for: item.bundleIdentifier) ?? .max) < (item.releasedVersion ?? .min)
    }

}

// MARK: Sidebar

@available(macOS 12.0, iOS 15.0, *)
extension FairAppInventory {
    /// Returns true if the item was recently updated
    func isRecentlyUpdated(item: AppCatalogItem, interval: TimeInterval = (60 * 60 * 24 * 30)) -> Bool {
        (item.versionDate ?? .distantPast) > (Date() - interval)
    }

    func selectionFilter(_ selection: SidebarSelection?, item: AppCatalogItem) -> Bool {
        switch selection?.item {
        case .none:
            return true
        case .top:
            return true
        case .updated:
            return appUpdated(item: item)
        case .installed:
            return appInstalled(item: item) != nil
        case .recent:
            return isRecentlyUpdated(item: item)
        case .category(let category):
            return item.categories?.contains(category.rawValue) == true
        }
    }

    func badgeCount(for item: SidebarItem) -> Text? {
        switch item {
        case .top:
            return Text(appInfoItems(includePrereleases: showPreReleases).count, format: .number)
        case .recent:
            return Text(appInfoItems(includePrereleases: showPreReleases).filter({ isRecentlyUpdated(item: $0) }).count, format: .number)
        case .updated:
            return Text(updateCount(), format: .number)
        case .installed:
            return Text(installedBundleIDs.count, format: .number)
        case .category:
            return nil
        }
    }
}
