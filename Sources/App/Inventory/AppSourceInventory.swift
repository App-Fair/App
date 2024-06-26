/**
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as
 published by the Free Software Foundation, either version 3 of the
 License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Affero General Public License for more details.

 The full text of the GNU Affero General Public License can be
 found in the COPYING.txt file or at https://www.gnu.org/licenses/

 Linking this library statically or dynamically with other modules is
 making a combined work based on this library.  Thus, the terms and
 conditions of the GNU Affero General Public License cover the whole
 combination.

 As a special exception, the copyright holders of this library give you
 permission to link this library with independent modules to produce an
 executable, regardless of the license terms of these independent
 modules, and to copy and distribute the resulting executable under
 terms of your choice, provided that you also meet, for each linked
 independent module, the terms and conditions of the license of that
 module.  An independent module is a module which is not derived from
 or based on this library.  If you modify this library, you may extend
 this exception to your version of the library, but you are not
 obligated to do so.  If you do not wish to do so, delete this
 exception statement from your version.
 */
import FairApp
import FairExpo
import Dispatch
import Security
import Foundation
import OSLog

private let showPreReleasesDefault = false
private let relaunchUpdatedAppsDefault = true
private let riskFilterDefault = AppRisk.risky
private let autoUpdateCatalogAppDefault = true
private let relaunchUpdatedCatalogAppDefault = PromptSuppression.unset

/// A manager for installing from an AppSource catalog.
public final class AppSourceInventory: ObservableObject, AppInventory, AppManagement {
    //let catalog: AppCatalog
    public let source: AppSource

    /// The URL for this catalogs app source
    public let sourceURL: URL

    /// The list of currently installed apps of the appID to the Info.plist (or error)
    @Published private var installedApps: [AppIdentifier : Result<Plist, Error>] = [:]

    /// The current catalog of apps
    @Published internal var catalog: Result<AppCatalog, Error>? = nil

    /// The date the catalog was most recently updated
    @Published private(set) public var catalogUpdated: Date? = nil

    /// The number of outstanding update requests
    @Published public var updateInProgress: UInt = 0

    @AppStorage("showPreReleases") var showPreReleases = showPreReleasesDefault

    @AppStorage("relaunchUpdatedApps") var relaunchUpdatedApps = relaunchUpdatedAppsDefault

    @AppStorage("riskFilter") var riskFilter = riskFilterDefault

    @AppStorage("autoUpdateCatalogApp") public var autoUpdateCatalogApp = autoUpdateCatalogAppDefault

    /// Whether to automatically re-launch the catalog app when it has updated itself
    @AppStorage("relaunchUpdatedCatalogApp") var relaunchUpdatedCatalogApp = relaunchUpdatedCatalogAppDefault

    /// Whether to enable platform conversion for installed binaries
    @AppStorage("enablePlatformConversion") var enablePlatformConversion: Bool = false

    public func appList() async -> [AppInfo]? {
        catalogApps
    }

    /// Resets all of the `@AppStorage` properties to their default values
    func resetAppStorage() {
        self.showPreReleases = showPreReleasesDefault
        self.relaunchUpdatedApps = relaunchUpdatedAppsDefault
        self.riskFilter = riskFilterDefault
        self.autoUpdateCatalogApp = autoUpdateCatalogAppDefault
        self.relaunchUpdatedCatalogApp = relaunchUpdatedCatalogAppDefault
    }

    var isAppFairSource: Bool {
        sourceURL.isAppFairSource
    }

    /// Returns `true` if this is the central source for the catalog.
    var isRootCatalogSource: Bool {
        sourceURL == appfairCatalogURLMacOS
    }

    /// Returns the
    public var supportedSidebars: [SidebarSection] {
        SidebarSection.orderedSections.filter { sel in
            sel.shouldDisplay(sectionWithCount: itemCount(for: sel))
        }
    }

    var symbol: FairSymbol {
        if isAppFairSource {
            return FairSymbol.ticket
        } else {
            return FairSymbol.app_gift
        }
    }

    private var fsobserver: FileSystemObserver? = nil

    init(source: AppSource, sourceURL: URL) {
        self.source = source
        self.sourceURL = sourceURL
    }

    @MainActor func checkInstallFolder() async throws {
        let folder = try installFolderURL()
        if FileManager.default.isDirectory(url: folder) == false {
            try await self.createInstallFolder()
        }

        // set up a file-system observer for the install folder, which will refresh the installed apps whenever any changes are made; this allows external processes like homebrew to update the installed app
        if FileManager.default.isDirectory(url: folder) == true {
            self.fsobserver = FileSystemObserver(URL: folder, queue: .main) {
                dbg("changes detected in app folder:", folder.path)
                Task {
                    await self.scanInstalledApps()
                }
            }
        }
    }

    /// The catalog's success value
    ///
    /// - TODO: @available(*, deprecated, renamed: "catalog")
    var catalogSuccess: AppCatalog? {
        catalog?.successValue
    }

    /// A failed catalog load
    var catalogError: Error? {
        catalog?.failureValue
    }

    public var title: String {
        catalogSuccess?.name ?? NSLocalizedString("App Source", comment: "the default title of a fair apps catalog")
    }

    private var catalogApps: [AppInfo]? {
        catalogSuccess?.apps.map({ AppInfo(source: source, app: $0) })
    }

    @MainActor public func reload(fromSource reloadFromSource: Bool) async throws {
        let oldid = self.catalogSuccess?.identifier

        // resetting the catalog has some undesirable effects, like clearing the user's current selection

//        withAnimation {
//            // clear catalog first
//            self.catalog = nil
//        }

        self.updateInProgress += 1
        defer { self.updateInProgress -= 1 }

        do {
            let (catalog, response) = try await FairHub.fetchCatalog(sourceURL: sourceURL, locale: Locale.current, cache: reloadFromSource ? .reloadIgnoringLocalAndRemoteCacheData : .useProtocolCachePolicy)
            withAnimation {
                if self.catalogSuccess != catalog {
                    self.catalog = .success(catalog)
                }

                // The "Last-Modified" header isn't always sent, so default to .now
                self.catalogUpdated = response?.lastModifiedDate ?? .now
            }

            if isRootCatalogSource == true && autoUpdateCatalogApp == true {
                do {
                    try await updateCatalogApp()
                } catch {
                    dbg(3, "error updating catalog app:", error)
                }
            }

            if let newid = catalog.identifier, newid != oldid {
                try await checkInstallFolder()
            }

            await scanInstalledApps()
        } catch {
            // report the failure to load
            withAnimation {
                self.catalog = .failure(error)
            }
        }
    }

    public func label(for source: AppSource) -> Label<Text, Image> {
        func labelText() -> Text {
            let txt = {
                self.catalogSuccess?.name?.text()
            }

            let srcname = {
                // self.source.rawValue.text()
                self.sourceURL.host?.text()
            }

            if self.updateInProgress > 0 {
                return txt() ?? srcname() ?? Text("Loading…", comment: "app source title for sidebad section while loading")
            } else {
                return txt() ?? Text("App Source", comment: "app source sidebar section title")
            }
        }

        return Label {
            labelText()
        } icon: {
            self.symbol.image
        }
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

/// A type of activity for a given app
enum CatalogActivity : CaseIterable, Equatable {
    case install
    case download
    case update
    case trash
    case reveal
    case launch
}



/// The minimum number of characters before we will perform a search; helps improve performance for synchronous searches
let minimumSearchLength = 1

extension AppSourceInventory {
    /// The app info for the current app (which is the catalog browser app)
    var catalogAppInfo: AppInfo? {
        appInfoItems(includePrereleases: false).first(where: { info in
            info.app.bundleIdentifier == Bundle.main.bundleIdentifier
        })
    }

    /// If the catalog app is updated,
    @MainActor private func updateCatalogApp(catalogAppBundle: Bundle = Bundle.main) async throws {
        // auto-update the App Fair app itself to the latest non-pre-release version
        guard let catalogApp = self.catalogAppInfo else {
            return dbg("could not locate current app in app list")
        }

        // if the release version is greater than the installed version, download and install it automatically
        // let installedCatalogVersion = installedVersion(for: catalogApp.id) // we should use the currently-running version as the authoritative version for checking
        let installedCatalogVersion = catalogAppBundle.bundleVersionString.flatMap { SemVer(string: $0) }

        dbg("checking catalog app update from installed version:", installedCatalogVersion?.versionString, "to:", catalogApp.app.releasedVersion?.versionString, "at:", catalogAppBundle.bundleURL.path)

        // only update the App Fair catalog manager app when it has been placed in the /Applications/ folder. This prevents updating while running while developing.
#if DEBUG
        if catalogAppBundle.executablePath?.hasPrefix(Self.applicationsFolderURL.path) != true {
            // only skip update while debugging
            return dbg("skipping DEBUG update to catalog app:", catalogAppBundle.executablePath, "since it is not installed in the applications folder:", Self.applicationsFolderURL.path)
        }
#endif

        if (catalogApp.app.releasedVersion ?? .min) > (installedCatalogVersion ?? .min) {
            try await installApp(item: catalogApp, progress: nil, downloadOnly: false, update: true, removingURLAt: catalogAppBundle.bundleURL)
        }
    }

    /// All the app-info items, sorted and filtered based on whether to include pre-releases.
    ///
    /// - Parameter includePrereleases: when `true`, versions marked `beta` will superceed any non-`beta` versions.
    /// - Returns: the list of apps, including all the installed apps, as well as matching pre-releases
    func appInfoItems(includePrereleases: Bool) -> LazyFilterSequence<[AppInfo]> {
        (catalogApps ?? [])
            .filter { item in
                // "beta" apps are are included when the pre-release flag is set
                includePrereleases == true || item.app.beta != true
            }
            .uniquing(by: \.app.bundleIdentifier)
    }

    /// The items arranged for the given category with the specifed sort order and search text
    @MainActor public func arrangedItems(sourceSelection: SourceSelection?, searchText: String) -> [AppInfo] {
        self
            .appInfoItems(includePrereleases: showPreReleases || sourceSelection?.section == .installed)
            .filter({ self.matchesExtension(item: $0) })
            .filter({ sourceSelection?.section.isLocalFilter == true || self.matchesRiskFilter(item: $0) })
            .filter({ self.matchesSearch(item: $0, searchText: searchText) })
            .filter({ self.selectionFilter(sourceSelection, item: $0) }) // TODO: fix categories for app item
            .sorted(using: sortOrder(section: sourceSelection?.section))
    }

    func sortOrder(section: SidebarSection?) -> [KeyPathComparator<AppInfo>] {
        switch section {
        case .none:
            return []
        case .top:
            return [] // use server-defined ordering [KeyPathComparator(\AppInfo.catalogMetadata.downloadCount, order: .reverse)]
        case .sponsorable:
            return []
        case .recent:
            return [KeyPathComparator(\AppInfo.app.versionDate, order: .reverse)]
        case .updated:
            return [KeyPathComparator(\AppInfo.app.versionDate, order: .reverse)]
        case .installed:
            return [KeyPathComparator(\AppInfo.app.name, order: .forward)]
        case .category:
            return []
        }
    }

    func matchesExtension(item: AppInfo) -> Bool {
        //displayExtensions?.contains(item.app.downloadURL.pathExtension) != false
        true
    }

    func matchesRiskFilter(item: AppInfo) -> Bool {
        item.app.riskLevel <= riskFilter
    }

    func matchesSearch(item: AppInfo, searchText: String) -> Bool {
        let txt = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if txt.count < minimumSearchLength {
            return true
        }

        func matches(_ string: String?) -> Bool {
            string?.localizedCaseInsensitiveContains(txt) == true
        }

        if matches(item.app.bundleIdentifier) { return true }
        
        if matches(item.app.name) { return true }
        if matches(item.app.subtitle) { return true }
        if matches(item.app.developerName) { return true }
        if matches(item.app.localizedDescription) { return true }
        
        return false
    }

    /// The main folder for apps
    static var applicationsFolderURL: URL {
        (try? FileManager.default.url(for: .applicationDirectory, in: .localDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: "/Applications")
    }

    /// The root install folder for ths fairground.
    ///
    /// E.g., `/Applications/App Fair`
    var baseInstallFolderURL: URL {
        URL(fileURLWithPath: Bundle.mainBundleName, relativeTo: Self.applicationsFolderURL)
    }

    /// The folder where App Fair apps will be installed
    func installFolderURL() throws -> URL {
        // we would like the install folder to be the same-named peer of the app's location, allowing it to run in `~/Downloads/` (which would place installed apps in `~/Downloads/App Fair`)
        // however, app translocation prevents it from knowing its location on first launch, and so we can't rely on being able to install as a peer without nagging the user to first move the app somewhere (thereby exhausting translocation)
        // Bundle.main.bundleURL.deletingPathExtension()
        guard let catalog = self.catalog?.successValue else {
            throw catalog?.failureValue ?? AppError(NSLocalizedString("Catalog not yet loaded.", comment: "error message"))
        }
        let url = baseInstallFolderURL
        if self.isRootCatalogSource == false {
            if let id = catalog.identifier {
                return url.appendingPathComponent(id)
            } else {
                throw AppError(NSLocalizedString("No identifier in catalog.", comment: "error message"))
            }
        }
        return url
    }

    /// Launch the local installed copy of this app
    public func launch(_ item: AppInfo) async throws {
        dbg("launching:", item.app.name)
        guard let installPath = try await installedPath(for: item) else {
            throw Errors.appNotInstalled(item.app)
        }

        dbg("launching:", installPath)

#if os(macOS)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true

        try await NSWorkspace.shared.openApplication(at: installPath, configuration: cfg)
#else
        throw Errors.launchAppNotSupported
#endif
    }

    /// The artifact URL for the app
    func appArtifactPath(for item: AppCatalogItem) async throws -> URL {
        try await appInstallPath(for: item, appSuffix: item.isMobileApp ? "ipa" : "app")
    }

    /// Returns the installed path for this app; this will always be
    /// `/Applications/Fair Ground/App Name.app`, except for the
    /// `Fair Ground.app` catalog app itself, which will be at:
    /// `/Applications/Fair Ground.app`
    /// - Parameters:
    ///   - item: the item
    ///   - ext: the extension for the path
    func appInstallPath(for item: AppCatalogItem, appSuffix ext: String? = "app", mkdir: (URL) throws -> () = { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }) async throws -> URL {
        let appSuffix = ext ?? (item.isMobileApp != true || self.enablePlatformConversion == false ? "app" : "ipa")
        let folder = try installFolderURL()
        let dir = try installFolderURL().lastPathComponent == item.name ? folder.deletingLastPathComponent() : folder
        try mkdir(dir)

        // e.g., "App Fair.app" matches "/Applications/App Fair"
        return URL(fileURLWithPath: item.name, isDirectory: appSuffix == "app" ? true : false, relativeTo: dir).appendingPathExtension(appSuffix)
    }

    /// The catalog app itself is the same as the name of the install path with the ".app" suffix.
    ///
    /// E.g., this converts `/Applications/App Fair/` to `/Applications/App Fair.app`.
    var catalogAppURL: URL {
        URL(fileURLWithPath: baseInstallFolderURL.lastPathComponent + ".app", relativeTo: baseInstallFolderURL.deletingLastPathComponent())
    }

    /// The bundle IDs for all the installed apps
    var installedBundleIDs: Dictionary<AppIdentifier, Result<Plist, Error>>.Keys {
        installedApps.keys
    }

    func installedVersion(for id: AppIdentifier) -> AppVersion? {
        installedInfo(for: id)?.appVersion
    }

    /// Returns the installed Plist for the given bundle identifier
    func installedInfo(for id: AppIdentifier) -> Plist? {
        installedApps.values.first { result in
            result.successValue?.CFBundleIdentifier == id.rawValue
        }?.successValue
    }

    func createInstallFolder() async throws {
        // always try to ensure the install folder is created (in case the user clobbers the app install folder while we are running)
        // FIXME: this will always fail, since the ownership & permissions of /Applications/ cannot be changed
        try await Self.withPermission(installFolderURL().deletingLastPathComponent()) { _ in
            try FileManager.default.createDirectory(at: installFolderURL(), withIntermediateDirectories: true, attributes: nil)
        }
    }

    @MainActor func scanInstalledApps() async {
        do {
            let start = CFAbsoluteTimeGetCurrent()
            try? await self.createInstallFolder()
            var installPathContents = try FileManager.default.contentsOfDirectory(at: try installFolderURL(), includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .producesRelativePathURLs]) // producesRelativePathURLs are critical so these will match the url returned from appInstallPath
            installPathContents.append(self.catalogAppURL)

            var installedApps = self.installedApps
            installedApps.removeAll() // clear the list

            func addApp<T>(bundle: AppBundle<T>) {
                let plist = bundle.infoDictionary
                if let appID = plist.appIdentifier {
                    // here was can validate some of the app's metadata, version number, etc
                    installedApps[appID] = .success(plist)
                }
            }

            for installPath in installPathContents.shuffled() {
                do {
                    if installPath.pathExtension == "app" {
                        if FileManager.default.isDirectory(url: installPath) == true {
                            await addApp(bundle: try AppBundle(folderAt: installPath))
                        }
                    } else if installPath.pathExtension == "ipa" {
                        if FileManager.default.isDirectory(url: installPath) == false {
                            await addApp(bundle: try AppBundle(zipArchiveAt: installPath))
                        }
                    } else {
                        dbg("skipping unrecognized path extension:", installPath)
                    }
                } catch {
                    // we ignore errors so a corrup Info.plist doesn't prevent the rest of the apps from being scanned
                    dbg("error scanning:", installPath, "error:", error)
                    //installedApps[appID] = .failure(error)
                }
            }

            withAnimation {
                self.installedApps = installedApps
            }
            let end = CFAbsoluteTimeGetCurrent()
            dbg("scanned", installedApps.count, "apps from:", try? installFolderURL().path, "in:", end - start, installedBundleIDs.map(\.rawValue))
        } catch {
            dbg("error performing re-scan:", error)
            //self.reportError(error)
        }
    }

    /// The `appInstallPath`, or nil if it does not exist
    public func installedPath(for item: AppInfo) async throws -> URL? {
        try await appInstallPath(for: item.app)
    }

    /// Trashes the local installed copy of this app
    public func delete(_ item: AppInfo, verbose: Bool = true) async throws {
        dbg("trashing:", item.app.name)
        guard let installPath = try await installedPath(for: item) else {
            throw Errors.appNotInstalled(item.app)
        }

        // first clear the artifact download if it is present;
        // if we do have the original artifact (e.g., the .ipa file),
        // then we will tolerate failures in removing the expanded app,
        // since it may not exist
        var trashedArtifact = false
        if let appArtifactPath = try? await self.appArtifactPath(for: item.app) {
            do {
                try await trash(appArtifactPath)
                trashedArtifact = true
            } catch {
                dbg("error removing download artifact:", error)
            }
        }

        do {
            try await trash(installPath)
        } catch {
            if trashedArtifact == false {
                throw error
            } else {
                dbg("tolerating trash failure since original artifact was removed:", error)
            }
        }

        // always re-scan after altering apps
        await scanInstalledApps()
    }

    /// Reveals the local installed copy of this app using the finder
    public func reveal(_ item: AppInfo) async throws {
        dbg("revealing:", item.app.name)
        guard let installPath = try await installedPath(for: item) else {
            throw Errors.appNotInstalled(item.app)
        }

        func show(_ url: URL) throws {
            #if os(macOS)
            // NSWorkspace.shared.activateFileViewerSelecting([installPath]) // unreliable
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: try installFolderURL().path)
            #endif
        }

        if FileManager.default.fileExists(atPath: installPath.path) == true {
            dbg("revealing:", installPath.path)
            try show(installPath)
        } else {
            if let appArtifactPath = try? await appArtifactPath(for: item.app) {
                dbg("revealing artifact:", appArtifactPath.path)
                try show(appArtifactPath)
            }
        }
    }

    public func install(_ info: AppInfo, progress parentProgress: Progress?, downloadOnly: Bool, update: Bool, verbose: Bool) async throws {
        try await installApp(item: info, progress: parentProgress, downloadOnly: downloadOnly, update: update, verbose: verbose, removingURLAt: nil)
    }

    /// Install or update the given catalog item.
    @MainActor private func installApp(item info: AppInfo, progress parentProgress: Progress?, downloadOnly: Bool, update: Bool, verbose: Bool = true, removingURLAt: URL? = nil) async throws {
        let item = info.app
        #if os(macOS)
        let window = UXApplication.shared.currentEvent?.window
        #endif
        if update == false,
            let installPath = try await installedPath(for: info),
            installPath.pathIsDirectory == true {
            throw Errors.appAlreadyInstalled(installPath)
        }

        guard let downloadURL = item.downloadURL else {
            throw Errors.missingDownloadURL(item)
        }

        try Task.checkCancellation()
        let (downloadedArtifact, downloadSha256) = try await downloadArtifact(url: downloadURL, progress: parentProgress)
        try Task.checkCancellation()

        // grab the hash of the download to compare against the fairseal
        dbg(2, "comparing fairseal expected:", item.sha256, "with actual:", downloadSha256)
        if let sha256 = item.sha256, sha256 != downloadSha256.hex() {
            throw AppError(NSLocalizedString("Invalid checksum", comment: "error message when a checksum fails"), failureReason: NSLocalizedString("The app's checksum was not valid. This may indicate a network failure to download correctly, but it could also indicate the app's contents have been tampered with since it was sealed. It is recommended you do not install this app, and that you inform the app's vendor of the incicident.", comment: "error message failure reason when a checksum fails"))
        }

        try Task.checkCancellation()

        let t1 = CFAbsoluteTimeGetCurrent()
        //let expandURL = wip(downloadedArtifact.appendingPathExtension("expanded"))
        let expandURL = URL(fileURLWithPath: downloadedArtifact.appendingPathExtension("expanded").lastPathComponent, isDirectory: true, relativeTo: downloadedArtifact)

        let progress2 = Progress(totalUnitCount: 1)
        parentProgress?.addChild(progress2, withPendingUnitCount: 0)

        try FileManager.default.unzipItem(at: downloadedArtifact, to: expandURL, skipCRC32: false, progress: progress2, preferredEncoding: .utf8)
        try FileManager.default.clearQuarantine(at: expandURL)

        try Task.checkCancellation()

        let t2 = CFAbsoluteTimeGetCurrent()

        // try Process.removeQuarantine(appURL: expandURL) // xattr: [Errno 1] Operation not permitted: '/var/folders/app.App-Fair/CFNetworkDownload_XXX.tmp.expanded/Some App.app'

        let shallowFiles = try FileManager.default.contentsOfDirectory(at: expandURL, includingPropertiesForKeys: nil, options: [])
        dbg(2, "unzipped:", downloadedArtifact.path, "to:", shallowFiles.map(\.lastPathComponent), "in:", t2 - t1)

//        if shallowFiles.count != 1 {
//            throw Errors.tooManyInstallFiles(item.downloadURL)
//        }

        let bundle = try await AppBundle(folderAt: expandURL)
        let (expandedAppPath, infoURL) = try bundle.appInfoURLs()
        dbg("expandedAppPath:", expandedAppPath.path, "infoURL:", infoURL.path, "expandURL:", expandURL)
        try bundle.validatePaths()

        try Task.checkCancellation()

        if downloadOnly {
            try FileManager.default.moveItem(at: downloadedArtifact, to: await appArtifactPath(for: item))
        } else {
            try FileManager.default.removeItem(at: downloadedArtifact)
        }


        if info.isMobileApp {
            #if os(macOS)
            let canConvertMobileApp = self.enablePlatformConversion && ProcessInfo.isArmMac
            if !canConvertMobileApp {
                // TODO: simply stop after copying the ipa
                return
            }

            // update the app to be able to run on mac
            let _ = try await bundle.setCatalystPlatform()
            #endif
        } else {
            // perform as much validation as possible before we attempt the install
            try self.validate(appPath: expandedAppPath, forItem: item)
        }

        let installPath = try await self.appInstallPath(for: item)

        let installFolderURL = installPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: installFolderURL, withIntermediateDirectories: true, attributes: nil)

        let destinationURL = installFolderURL.appendingPathComponent(expandedAppPath.lastPathComponent)
        dbg(2, "destinationURL:", destinationURL.path)

        // if we permit updates and it is already installed, trash the previous version
        if update && FileManager.default.isDirectory(url: destinationURL) == true {
            // TODO: first rename based on the old version number
            dbg(2, "trashing:", destinationURL.path)
            try await trash(destinationURL)
        }

        try Task.checkCancellation()

        if let removingURLAt = removingURLAt {
            // if we've specified a URL that is being replaced, try to delete it; this is to support being able to update the App Fair.app from the Downloads folder; the app will be installed in /Applications, but the launched application should be the one that is deleted
            do {
                try await trash(removingURLAt)
            } catch {
                // tolerate errors, which may result from translocation issues
                dbg(2, "error removingURLAt:", removingURLAt.path)
            }
            try Task.checkCancellation()
        }

        dbg(2, "installing:", expandedAppPath.path, "into:", destinationURL.path)
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

        #if os(macOS)
        if self.relaunchUpdatedApps == true, let bundleIdentifier = item.bundleIdentifier {
            let bundleID = AppIdentifier(bundleIdentifier)
            // the catalog app is special, since re-launching requires quitting the current app
            let isCatalogApp = bundleID.rawValue == Bundle.main.bundleID

            func relaunch() {
                dbg(2, "re-launching app:", bundleID)
                terminateAndRelaunch(bundleID: bundleID, force: false, overrideLaunchURL: isCatalogApp ? destinationURL : nil)
            }

            if !isCatalogApp {
                // automatically re-launch any app that isn't a catalog app
                relaunch()
            } else {
                // if this is the catalog app, prompt the user to re-launch
                let response = await prompt(window: window,
                                            messageText: String(format: NSLocalizedString("App Fair has been updated", comment: "app updated dialog title")),
                                            informativeText: String(format: NSLocalizedString("This app has been updated from %@ to the latest version %@. Would you like to re-launch it?", comment: "app updated dialog body"), Bundle.main.bundleVersionString ?? "?", item.version ?? "?"),
                                            accept: NSLocalizedString("Re-launch", comment: "app updated re-launch button text"),
                                            refuse: NSLocalizedString("Later", comment: "app updated skip relaunch button text"),
                                            suppressionKey: $relaunchUpdatedCatalogApp)
                dbg("prompt response:", response)
                if response == true {
                    relaunch()
                }
            }
        }
        #endif
    }

    private func trash(_ fileURL: URL) async throws {
        // perform privilege escalation if needed
        let trashedURL = try await Self.withPermission(fileURL) { fileURL in
            try FileManager.default.trash(url: fileURL)
        }
        dbg("trashed:", fileURL.path, "to:", trashedURL?.path)
    }

    /// Kills the process with the given `bundleID` and re-launches it.
    private func terminateAndRelaunch(bundleID: AppIdentifier, force: Bool, overrideLaunchURL: URL? = nil) {
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
        /// When the app catalog item does not list a URL
        case missingDownloadURL(AppCatalogItem)
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
        let (downloadedArtifact, response) = try await request.download(consumer: hasher, parentProgress: parentProgress)
        let downloadSha256 = await hasher.final()

        let t2 = CFAbsoluteTimeGetCurrent()

        dbg("downloaded:", downloadedArtifact.fileSize()?.localizedByteCount(), t2 - t1, (response as? HTTPURLResponse)?.statusCode)
        return (downloadedArtifact, downloadSha256)
    }
}

extension FairHub {
#if swift(>=5.5)
    /// Fetches the `AppCatalog`
        public static func fetchCatalog(sourceURL: URL, locale: Locale?, injectSourceURL: Bool = true, cache: URLRequest.CachePolicy? = nil) async throws -> (catalog: AppCatalog, response: URLResponse?) {
        dbg("fetching catalog at:", sourceURL)
        let start = CFAbsoluteTimeGetCurrent()

        var req = URLRequest(url: sourceURL)
        if let cache = cache { req.cachePolicy = cache }
        let (data, response) = try await URLSession.shared.fetch(request: req)
        //dbg(wip("catalog data:"), data.utf8String)

        let end = CFAbsoluteTimeGetCurrent()
        dbg("fetched catalog at:", sourceURL, data.count.localizedByteCount(), "in:", (end - start))

        var catalog = try AppCatalog.parse(jsonData: data)
        dbg("parsed catalog apps at:", sourceURL, catalog.apps.count)

        #warning("TODO: re-enable localization")
//        if let locale = locale {
//            // localize the catalog for the requested locale
//            catalog = try await catalog.localized(into: locale)
//        }

        if injectSourceURL == true && catalog.sourceURL == nil {
            catalog.sourceURL = sourceURL
        }

        return (catalog, response)
    }
#endif // swift(>=5.5)
}

extension AppSourceInventory {
    typealias Item = URL

    public func updateCount() -> Int {
        appInfoItems(includePrereleases: showPreReleases)
            .filter { item in self.appUpdated(item) }
            .count
    }

    func sponsorableCount() -> Int {
        appInfoItems(includePrereleases: showPreReleases).filter { item in
            self.appSponsorable(item)
        }.count
    }

    public func appInstalled(_ item: AppInfo) -> String? {
        installedInfo(for: AppIdentifier(item.app.bundleIdentifier ?? wip("")))?.versionString
    }

    public func appUpdated(_ item: AppInfo) -> Bool {
        // (appPropertyList?.successValue?.appVersion ?? .max) < (info.releasedVersion ?? .min)
        (installedVersion(for: AppIdentifier(item.app.bundleIdentifier ?? wip(""))) ?? .max) < (item.app.releasedVersion ?? .min)
    }

}

// MARK: Sidebar

extension AppSourceInventory {

    @MainActor func selectionFilter(_ selection: SourceSelection?, item: AppInfo) -> Bool {
        switch selection?.section {
        case .none:
            return true
        case .top:
            return true
        case .updated:
            return appUpdated(item)
        case .sponsorable:
            return appSponsorable(item)
        case .installed:
            return appInstalled(item) != nil
        case .recent:
            return isRecentlyUpdated(item)
        case .category(let category):
            return item.app.categories?.contains(category) == true
        }
    }

    /// The number of items for the given section
    func itemCount(for section: SidebarSection) -> Int? {
        switch section {
        case .top:
            return appInfoItems(includePrereleases: showPreReleases).count
        case .recent:
            return catalog == nil ? nil : appInfoItems(includePrereleases: showPreReleases).filter({ self.isRecentlyUpdated($0) }).count
        case .sponsorable:
            return catalog == nil ? nil : sponsorableCount()
        case .installed:
            return catalog == nil ? nil : installedBundleIDs.count
        case .updated:
            return catalog == nil ? nil : updateCount()
        case .category:
            return nil
        }
    }

    @MainActor public func badgeCount(for section: SidebarSection) -> Text? {
        itemCount(for: section)?.textNumber()
    }    
}

private var catalogDescriptionText: Text? {
    Text("Fairground apps are created through the appfair.net process. They are 100% open-source and disclose all their permissions in their App Fair catalog entry.", comment: "fairapps catalog description for header text of detail view")
}

private var externalSourceDescriptionText: Text? {
    nil
    //Text("External source", comment: "catalog description for header text of app source")
}

private extension URL {
    var isAppFairSource: Bool {
        host == "appfair.net" || host?.hasSuffix(".appfair.net") == true
    }
}

private let defaultAppSource = Text("App Source", comment: "fairapps top apps info: full title")

private extension AppCatalog {
    var catalogTitle: Text {
        name?.text() ?? defaultAppSource
    }

    /// Returns true if this catalog is from an App Fair source
    ///
    /// - TODO: identify fairground
    var isAppFairSource: Bool {
        sourceURL?.isAppFairSource == true
    }
}

extension AppSourceInventory {
    public func icon(for info: AppInfo) -> AppIconView {
        AppIconView(content: .init(IconView(info: info)))
    }

    struct IconView : View, Equatable {
        let info: AppInfo

        var body: some View {
            Group {
                if let url = info.app.iconURL {
    //                if let cachedImage = self.imageCache[url] {
    //                    cachedImage
    //                } else {
                        AsyncImage(url: url, scale: 1.0, transaction: Transaction(animation: .easeIn)) {
                            imageContent(phase: $0)
                                .mask(RoundedRectangle(cornerRadius: 10, style: .continuous)) // TODO: should corner radius be relative to the size of the icon?
                        }
    //                }
                } else {
                    fallbackIcon(grayscale: 1.0)
                }
            }
            .aspectRatio(contentMode: .fit)

        }

        func imageContent(phase: AsyncImagePhase) -> some View {
            Group {
                switch phase {
                case .success(let image):
                    //let _ = iconCache.setObject(ImageInfo(image: image), forKey: iconURL as NSURL)
                    //let _ = dbg("success image for:", self.name, image)
                    let img = image
                        .resizable()
                    img
                case .failure(let error):
                    //let _ = dbg("error image for:", info.app.name, error)
                    if !error.isURLCancelledError { // happens when items are scrolled off the screen
                        let _ = dbg("error fetching icon from:", info.app.iconURL?.absoluteString, "error:", error.isURLCancelledError ? "Cancelled" : error.localizedDescription)
                    }
                    fallbackIcon(grayscale: 0.9)
                        .help(error.localizedDescription)
                case .empty:
                    fallbackIcon(grayscale: 0.5)

                @unknown default:
                    fallbackIcon(grayscale: 0.8)
                }
            }
        }

        @ViewBuilder func fallbackIcon(grayscale: Double) -> some View {
            let baseColor = info.app.itemTintColor()
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(baseColor)
                .opacity(0.5)
                .grayscale(grayscale)
        }
    }
}

extension AppSourceInventory {
    public func sourceInfo(for section: SidebarSection) -> AppSourceInfo? {
        sourceInformation(for: section)
    }

    func sourceInformation(for section: SidebarSection) -> AppSourceInfo {
        switch section {
        case .top:
            struct TopAppInfo : AppSourceInfo {
                let catalog: AppCatalog?
                let symbol: FairSymbol
                let tint: Color

                func tintedLabel(monochrome: Bool) -> TintedLabel {
                    TintedLabel(title: Text("Apps", comment: "fairapps sidebar category title"), symbol: symbol, tint: monochrome ? nil : tint, mode: monochrome ? .monochrome : .multicolor)
                }

                /// Subtitle text for this source
                var fullTitle: Text {
                    catalog?.catalogTitle ?? defaultAppSource
                }

                /// A textual description of this source
                var overviewText: [Text] {
                    [
                        catalog?.isAppFairSource == true ? catalogDescriptionText : externalSourceDescriptionText,
                        catalog?.isAppFairSource == true ? Text("Apps installed from the Fairground catalog are guaranteed to run in a sandbox, meaning that access to resources like the filesystem, network, and devices are mediated through a security layer that mandates that their permissions be documented, disclosed, and approved by the user. Fairground apps publish a “risk level” summarizing the number of permission categories the app requests.", comment: "fairapps top apps info: overview text") : nil,
                    ]
                        .compacted()
                }

                var footerText: [Text] {
                    if let catalog = catalog {
                        if catalog.isAppFairSource == true {
                            return [Text("Learn more about the fairground process at [https://appfair.net](https://appfair.net)", comment: "fairground top apps info: footer link text")]
                        } else {
                            if let appLink = catalog.homepage ?? catalog.sourceURL {
                                let href = appLink.absoluteString
                                return [Text(AttributedString(localized: "Learn more about this app source at [\(href)](\(href))", comment: "app source catalog info footer"))]
                            } else {
                                return []
                            }
                        }
                    } else {
                        return []
                    }
                }

                /// A list of the features of this source, which will be displayed as a bulleted list
                var featureInfo: [(FairSymbol, Text)] {
                    []
                }
            }

            return TopAppInfo(catalog: catalogSuccess, symbol: self.symbol, tint: isAppFairSource ? .accentColor : FairIconView.iconColor(name: sourceURL.absoluteString))
        case .recent:

            struct RecentAppInfo : AppSourceInfo {
                let catalog: AppCatalog?

                func tintedLabel(monochrome: Bool) -> TintedLabel {
                    TintedLabel(title: Text("Recent", comment: "fairapps sidebar category title"), symbol: .clock_fill, tint: monochrome ? nil : Color.yellow, mode: monochrome ? .monochrome : .multicolor)
                }

                /// Subtitle text for this source
                var fullTitle: Text {
                    [
                        catalog?.catalogTitle,
                        Text("Recent", comment: "fairapps recent apps info: full title")
                    ]
                        .compacted()
                        .joined(separator: Text(verbatim: ": "))
                }

                /// A textual description of this source
                var overviewText: [Text] {
                    [
                        catalog?.isAppFairSource == true ? catalogDescriptionText : externalSourceDescriptionText,
                        catalog?.isAppFairSource == true ? Text("Recent apps contain those applications that have been newly released or updated within the past month.", comment: "fairapps recent apps info: overview text") : nil,
                    ]
                        .compacted()
                }

                var footerText: [Text] {
                    []
                    // Text(wip("XXX"), comment: "homebrew recent apps info: overview text")
                }

                /// A list of the features of this source, which will be displayed as a bulleted list
                var featureInfo: [(FairSymbol, Text)] {
                    []
                }
            }

            return RecentAppInfo(catalog: catalogSuccess)
        case .installed:

            struct InstalledAppInfo : AppSourceInfo {
                let catalog: AppCatalog?

                func tintedLabel(monochrome: Bool) -> TintedLabel {
                    TintedLabel(title: Text("Installed", comment: "fairapps sidebar category title"), symbol: .externaldrive_fill, tint: monochrome ? nil : Color.orange, mode: monochrome ? .monochrome : .multicolor)
                }

                /// Subtitle text for this source
                var fullTitle: Text {
                    [
                        catalog?.catalogTitle,
                        Text("Installed", comment: "fairapps installed apps info: full title")
                    ]
                        .compacted()
                        .joined(separator: Text(verbatim: ": "))
                }

                /// A textual description of this source
                var overviewText: [Text] {
                    [
                        catalog?.isAppFairSource == true ? catalogDescriptionText : externalSourceDescriptionText,
                        catalog?.isAppFairSource == true ? Text("The installed apps section contains all the apps that are currently installed from this catalog.", comment: "fairapps installed apps info: overview text") : nil,
                    ]
                        .compacted()
                }

                var footerText: [Text] {
                    []
                    // Text(wip("XXX"), comment: "homebrew recent apps info: overview text")
                }

                /// A list of the features of this source, which will be displayed as a bulleted list
                var featureInfo: [(FairSymbol, Text)] {
                    []
                }
            }

            return InstalledAppInfo(catalog: catalogSuccess)
        case .sponsorable:

            struct SponsorableAppInfo : AppSourceInfo {
                let catalog: AppCatalog?

                func tintedLabel(monochrome: Bool) -> TintedLabel {
                    TintedLabel(title: Text("Sponsorable", comment: "fairapps sidebar category title"), symbol: .heart, tint: monochrome ? nil : Color.red, mode: monochrome ? .monochrome : .palette)
                }

                /// Subtitle text for this source
                var fullTitle: Text {
                    [
                        catalog?.catalogTitle,
                        Text("Sponsorable", comment: "fairapps sponsorable apps info: full title")
                    ]
                        .compacted()
                        .joined(separator: Text(verbatim: ": "))
                }

                /// A textual description of this source
                var overviewText: [Text] {
                    [
                        catalog?.isAppFairSource == true ? catalogDescriptionText : externalSourceDescriptionText,
                        catalog?.isAppFairSource == true ? Text("The sponsorable apps section contains apps that have listed themselves as being available for patronage.", comment: "fairapps sponsorable apps info: overview text") : nil,
                    ]
                        .compacted()
                }

                var footerText: [Text] {
                    [
                        Text("Learn more about sponsorable apps at [appfair.app#sponsorable](https://appfair.app#sponsorable)", comment: "fairapps sponsorable apps info: overview text")
                    ]
                }

                /// A list of the features of this source, which will be displayed as a bulleted list
                var featureInfo: [(FairSymbol, Text)] {
                    []
                }
            }

            return SponsorableAppInfo(catalog: catalogSuccess)
        case .updated:
            struct UpdatedAppInfo : AppSourceInfo {
                let catalog: AppCatalog?

                func tintedLabel(monochrome: Bool) -> TintedLabel {
                    TintedLabel(title: Text("Updated", comment: "fairapps sidebar category title"), symbol: .arrow_down_app_fill, tint: monochrome ? nil : Color.green, mode: monochrome ? .monochrome : .multicolor)
                }

                /// Subtitle text for this source
                var fullTitle: Text {
                    [
                        catalog?.catalogTitle,
                        Text("Updated", comment: "fairapps updated apps info: full title")
                    ]
                        .compacted()
                        .joined(separator: Text(verbatim: ": "))
                }

                /// A textual description of this source
                var overviewText: [Text] {
                    [
                        catalog?.isAppFairSource == true ? catalogDescriptionText : externalSourceDescriptionText,
                        catalog?.isAppFairSource == true ? Text("The updated apps section contains all the apps that are currently installed from this catalog and that currently have updates available.", comment: "fairapps installed apps info: overview text") : nil,
                    ]
                        .compacted()
                }

                var footerText: [Text] {
                    []
                    // Text(wip("XXX"), comment: "homebrew recent apps info: overview text")
                }

                /// A list of the features of this source, which will be displayed as a bulleted list
                var featureInfo: [(FairSymbol, Text)] {
                    []
                }
            }
            return UpdatedAppInfo(catalog: catalogSuccess)
        case .category(let category):
            return CategoryAppInfo(category: category)
        }
    }
}
