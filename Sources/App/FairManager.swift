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
import FairKit
import FairExpo
import Combine

extension Never : FacetView {
    public typealias FacetStore = FairManager
    public typealias FacetViewType = Never
    @ViewBuilder public func facetView(for store: FacetStore) -> Never {
        fatalError()
    }

}

open class FairManager: SceneManager, AppInventoryController {
    public static var bundle: Bundle = .module
    
    @AppStorage("themeStyle") var themeStyle = ThemeStyle.system

    @AppStorage("enableInstallWarning") public var enableInstallWarning: Bool = true
    @AppStorage("enableDeleteWarning") public var enableDeleteWarning: Bool = true
    @AppStorage("enableSponsorship") public var enableSponsorship: Bool = true

    /// The base domain of the provider for the hub
    @AppStorage("hubProvider") public var hubProvider = "github.com"
    /// The organization name of the hub
    @AppStorage("hubOrg") public var hubOrg = "appfair"
    /// The name of the base repository for the provider
    @AppStorage("hubRepo") public var hubRepo = "App"

    /// An optional authorization token for direct API usagefor the organization
    @AppStorage("hubToken") public var hubToken = ""

    /// Whether to try blocking launch telemetry reporting
    @AppStorage("appLaunchPrivacy") public var appLaunchPrivacy: Bool = false

    /// The duration to continue blocking launch telemtry after an app has been launched (since the OS retries for a certain amount of time if the initial connection fails)
    @AppStorage("appLaunchPrivacyDuration") public var appLaunchPrivacyDuration: TimeInterval = 60.0

    /// Whether links clicked in the embedded browser should open in a new browser window
    @AppStorage("openLinksInNewBrowser") var openLinksInNewBrowser: Bool = true

    /// Whether the embedded browser should use private browsing mode for untrusted sites
    @AppStorage("usePrivateBrowsingMode") var usePrivateBrowsingMode: Bool = true

    /// Whether to enable user-specified sources
    @AppStorage("enableUserSources") var enableUserSources: Bool = false

    /// The list of source URL strings to load as sources
    @AppStorage("userSources") var userSources: AppStorageArray<String> = []

    /// The inventories of app sources that are currently available
    @Published var inventories: AppInventoryList = .init()

//    /// The appManager, which should be extracted as a separate `EnvironmentObject`
//    @Published var fairAppInv: AppSourceInventory
//    /// The caskManager, which should be extracted as a separate `EnvironmentObject`
//    @Published var homeBrewInv: HomebrewInventory

    /// The apps that have been installed or updated in this session
    @Published var sessionInstalls: Set<AppInfo.ID> = []

    /// The current app exit observer for app launch privacy; it will be cleared when the observer expires
    @Published private var appLaunchPrivacyDeactivator: NSObjectProtocol? = nil

    /// The current activities that are taking place for each bundle identifier
    @Published var operations: [AppIdentifier: CatalogOperation] = [:]

    /// A cache for images that are loaded by this manager
    //let imageCache = Cache<URL, Image>()

    @Published public var errors: [AppError] = []

    //private var observers: [AnyCancellable] = []

    #if os(macOS)
    public typealias AppFacets = Never
    public typealias ConfigFacets = Never
    #endif

    public required init() {
        self.resetAppSources(load: nil)

//        /// The gloal quick actions for the App Fair
//        self.quickActions = [
//            QuickAction(id: "refresh-action", localizedTitle: NSLocalizedString("Refresh Catalog", comment: "action button title for refreshing the catalog")) { completion in
//                dbg("refresh-action")
//                Task {
//                    //await self.appManager.fetchApps(cache: .reloadIgnoringLocalAndRemoteCacheData)
//                    completion(true)
//                }
//            }
//        ]
    }

    public var bundle: Bundle { Bundle.module }
}

extension FairManager : AppManagement {

    public func install(_ appInfo: AppInfo, progress parentProgress: Progress?, downloadOnly: Bool, update: Bool, verbose: Bool) async throws {
        try await inventory(for: appInfo)?.install(appInfo, progress: parentProgress, downloadOnly: downloadOnly, update: update, verbose: verbose)
        sessionInstalls.insert(appInfo.id)
    }

    public func reveal(_ appInfo: AppInfo) async throws {
        try await inventory(for: appInfo)?.reveal(appInfo)
    }

    public func launch(_ appInfo: AppInfo) async throws {
        #if os(macOS)
        if self.appLaunchPrivacy {
            try await self.enableAppLaunchPrivacy()
        }
        #endif
        try await inventory(for: appInfo)?.launch(appInfo)
    }

    public func delete(_ appInfo: AppInfo, verbose: Bool) async throws {
        try await inventory(for: appInfo)?.delete(appInfo, verbose: verbose)
    }

    public func installedPath(for appInfo: AppInfo) async throws -> URL? {
        try await inventory(for: appInfo)?.installedPath(for: appInfo)
    }

}

extension FairManager { // }: AppInventory {
    public func refresh(reloadFromSource: Bool) async {
        await withTaskGroup(of: Void.self, returning: Void.self) { group in
            for inv in self.appInventories.shuffled() {
                let _ = group.addTaskUnlessCancelled {
                    await self.load(inventory: inv, reloadFromSource: reloadFromSource)
                }
            }
        }
    }
}

extension FairManager {

    /// Called when the user preference changes
    func loadUserSources(enable: Bool) {
        dbg(enable)
        resetAppSources(load: .medium)
    }

    /// Resets the in-memory list of app sources without touching the
    func resetAppSources(load: TaskPriority?, force: Bool = false) {
        if force == false {
            while self.inventories.count > 2 {
                // remove all but the first-two sources
                self.inventories.removeLast()
            }
        } else {
            // otherwise nuke everything and re-add all the sources manually
            self.inventories.removeAll()
        }

        #if os(macOS)
        // always ensure the ordering of the first two
        if self.inventories.count < 1 {
            _ = addInventory(HomebrewInventory(source: .homebrew, sourceURL: appfairCaskAppsURL), load: load)
        }
        #endif

        if self.inventories.count < 2 {
            _ = addAppSource(url: appfairCatalogURLMacOS, load: load, persist: false)
        }

        if enableUserSources {
            for source in self.userSources.compactMap(URL.init(string:)) {
                dbg("adding user source:", source.absoluteString)
                _ = addAppSource(url: source, load: load, persist: false)
            }
        }
    }

    /// Adds an app source to the list of inventories
    ///
    /// - Parameters:
    ///   - url: the url of the source
    ///   - load: whether to start a task to load the contents of the source
    ///   - persist: whether to save the URL in the persistent list of sources
    /// - Returns: whether the source was successfully added
    @discardableResult @MainActor func addAppSource(url: URL, load loadPriority: TaskPriority?, persist: Bool) -> AppSourceInventory? {
        let source = AppSource(rawValue: url.absoluteString)
        let inv = AppSourceInventory(source: source, sourceURL: url)
        let added = addInventory(inv, load: loadPriority)
        if added == false {
            return nil
        } else {
            if persist { // save the source in the user defaults
                userSources.append(url.absoluteString)
            }
            return inv
        }
    }

    /// Removed the inventory for the given source, both from the current inventories
    /// as well as from the persistent list saved in ``AppStorage``.
    @discardableResult func removeInventory(for removeSource: AppSource, persist: Bool) -> Bool {
        var found = false
        for (index, (inv, _)) in self.inventories.enumerated().reversed() {
            if removeSource == inv.source {
                self.inventories.remove(at: index)
                if persist {
                    self.userSources.removeAll { $0 == removeSource.rawValue }
                }
                found = true
            }
        }
        return found
    }

    @MainActor @discardableResult func addInventory(_ inventory: AppInventoryManagement, load loadPriority: TaskPriority?) -> Bool {
        if let _ = self.inventories.first(where: { inv, _ in
            inv.source == inventory.source
        }) {
            // the source of the inventory is the unique identifier
            return false
        }

        // track any changes to the inventory and broadcast their changes
        let observer = inventory.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        self.inventories.append((inventory, observer))

        if let loadPriority = loadPriority {
            Task(priority: loadPriority) {
                await self.load(inventory: inventory, reloadFromSource: true)
            }
        }

        return true
    }

    func arrangedItems(source: AppSource, sourceSelection: SourceSelection?, searchText: String) -> [AppInfo] {
        self.inventory(for: source)?.arrangedItems(sourceSelection: sourceSelection, searchText: searchText) ?? []
    }

    /// Returns true is there are any refreshes in progress
    var refreshing: Bool {
        self.appInventories.contains { $0.updateInProgress > 0 }
    }

    private func load(inventory: AppInventory, reloadFromSource: Bool) async {
        await self.trying {
            do {
                try await inventory.reload(fromSource: reloadFromSource)
            } catch {
                throw AppError(String(format: NSLocalizedString("Error Loading Catalog", comment: "error wrapper string when a catalog URL fails to load")), failureReason: String(format: NSLocalizedString("The catalog failed to load from the URL: %@", comment: "error wrapper string when a catalog URL fails to load"), inventory.sourceURL.absoluteString), underlyingError: error)
            }
        }
    }

    private func reportError(_ error: Error, functionName: StaticString, fileName: StaticString, lineNumber: Int) {
        dbg("error:", error, functionName: functionName, fileName: fileName, lineNumber: lineNumber)
        errors.append(error as? AppError ?? AppError(error))
    }
    
    func inactivate() {
        dbg("inactivating and clearing caches")
        clearCaches()
    }

    func clearCaches() {
        //imageCache.clear()
        //fairAppInv.imageCache.clear()
        //homeBrewInv.imageCache.clear()
        //URLSession.shared.invalidateAndCancel()
        URLSession.shared.configuration.urlCache?.removeAllCachedResponses()
        URLCache.shared.removeAllCachedResponses()
    }

    /// Attempts to perform the given action and adds any errors to the error list if they fail.
    func trying(functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line, block: () async throws -> ()) async {
        do {
            try await block()
        } catch {
            reportError(error, functionName: functionName, fileName: fileName, lineNumber: lineNumber)
        }
    }

    func updateCount() -> Int {
        appInventories.map({ $0.updateCount() }).reduce(0, { $0 + $1 })
    }

    /// The view that will summarize the app source in the detail panel when no app is selected.
    func sourceOverviewView(selection: SourceSelection, showText: Bool, showFooter: Bool) -> some View {
        let inv: AppInventory? = inventory(for: selection.source)
        let info = inv?.sourceInfo(for: selection.section)
        let label = info?.label
        let color = label?.tint ?? .accentColor

        return VStack(spacing: 0) {
            Group {
                Divider()
                    .background(color)
                    .padding(.top, 1)

                label
                    .foregroundColor(Color.primary)
                    //.font(.largeTitle)
                    .symbolVariant(.fill)
                    .font(Font.largeTitle)
                    //.font(self.sourceFont(sized: 40))
                    .frame(height: 60)

                Divider()
                    .background(color)
            }

            Spacer()
            
            ScrollView {
                Group {
                    if showText, let info = info {
                        info.overviewText.joined(separator: Text(verbatim: "\n\n"))
                                .font(Font.title2)
                    }
                    if let description = (inv as? AppSourceInventory)?.catalogSuccess?.localizedDescription {
                        Text(atx: description)
                    }
                }
                .padding()
            }
            .textSelection(.enabled) // bug: sometimes selecting will unwraps and converts to a single line

            Spacer()
            if showFooter, let info = info {
                ForEach(enumerated: info.footerText) { _, footerText in
                    footerText
                        .textSelection(.enabled)
                }
                    .font(.footnote)
            }
        }
    }


    /// The icon for the given item
    /// - Parameters:
    ///   - info: the info to check
    ///   - transition: whether to use a fancy transition
    /// - Returns: the icon
    @ViewBuilder func iconView(for appInfo: AppInfo, transition: Bool = false) -> some View {
        Group {
            inventory(for: appInfo.source)?.icon(for: appInfo)
        }
        //.transition(AnyTransition.scale(scale: 0.50).combined(with: .opacity)) // bounce & fade in the icon
        .transition(transition == false ? AnyTransition.opacity : AnyTransition.asymmetric(insertion: AnyTransition.opacity, removal: AnyTransition.scale(scale: 0.75).combined(with: AnyTransition.opacity))) // skrink and fade out the placeholder while fading in the actual icon

    }

    func installedVersion(_ appInfo: AppInfo) -> String? {
        inventory(for: appInfo)?.appInstalled(appInfo)
    }

    func appUpdated(_ appInfo: AppInfo) -> Bool {
        inventory(for: appInfo)?.appUpdated(appInfo) == true
    }
}

extension SourceSelection {

//    var sourceInfo: AppSourceInfo? {
//        switch self.source {
//        case .appSourceFairgroundMacOS, .appSourceFairgroundiOS:
//            switch self.item {
//            case .top:
//                return AppSourceInventory.SourceInfo.TopAppInfo()
//            case .recent:
//                return AppSourceInventory.SourceInfo.RecentAppInfo()
//            case .installed:
//                return AppSourceInventory.SourceInfo.InstalledAppInfo()
//            case .sponsorable:
//                return AppSourceInventory.SourceInfo.SponsorableAppInfo()
//            case .updated:
//                return AppSourceInventory.SourceInfo.UpdatedAppInfo()
//            case .category(let category):
//                return CategoryAppInfo(category: category)
//            }
//        case .homebrew:
//            switch self.item {
//            case .top:
//                return HomebrewInventory.SourceInfo.TopAppInfo()
//            case .recent:
//                return HomebrewInventory.SourceInfo.RecentAppInfo()
//            case .sponsorable:
//                return HomebrewInventory.SourceInfo.SponsorableAppInfo()
//            case .installed:
//                return HomebrewInventory.SourceInfo.InstalledAppInfo()
//            case .updated:
//                return HomebrewInventory.SourceInfo.UpdatedAppInfo()
//            case .category(let category):
//                return CategoryAppInfo(category: category)
//            }
//        default:
//            return nil
//        }
//    }

    struct CategoryAppInfo : AppSourceInfo {
        let category: AppCategoryType

        func tintedLabel(monochrome: Bool) -> TintedLabel {
            category.tintedLabel(monochrome: monochrome)
        }

        /// Subtitle text for this source
        var fullTitle: Text {
            Text("Category: \(category.text)", comment: "app category info: title pattern")
        }

        /// A textual description of this source
        var overviewText: [Text] {
            []
            // Text(wip("XXX"), comment: "app category info: overview text")
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
}

// MARK: App Launch Privacy support

#if os(macOS)
extension FairManager {
    static let appLaunchPrivacyToolName = "applaunchprivacy"

    /// The script that we will store in the Applications Script folder to block app launch snooping
    static let appLaunchPrivacyToolSource = Result {
        try Bundle.module.loadResource(named: appLaunchPrivacyToolName + "/alp.swift")
    }

    /// The executable that we will store in the Applications Script folder to block app launch snooping
    static let appLaunchPrivacyToolBinary = Result {
        try Bundle.module.loadResource(named: appLaunchPrivacyToolName + ".b64")
    }

    /// The script that we will store in the Applications Script folder to block app launch snooping
    static let appLaunchPrivacyTool = Result {
        URL(string: appLaunchPrivacyToolName, relativeTo: try FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
    }

    private func clearAppLaunchPrivacyObserver() {
        if let observer = self.appLaunchPrivacyDeactivator {
            // cancel the app exit observer
            NotificationCenter.default.removeObserver(observer)
            self.appLaunchPrivacyDeactivator = nil
        }
    }

    /// Disables App Launch Privacy mode
    func disableAppLaunchPrivacy() async throws {
        if let appLaunchPrivacyTool = try Self.appLaunchPrivacyTool.get() {
            dbg("disabling app launch privacy")
            let unblock = try await Process.exec(cmd: appLaunchPrivacyTool.path, "disable").expect()
            dbg(unblock.terminationStatus == 0 ? "successfully" : "unsuccessfully", "disabled app launch privacy:", unblock.stdout, unblock.stderr)
            if unblock.terminationStatus == 0 {
                clearAppLaunchPrivacyObserver()
            }
        }
    }

    /// Invokes the block launch telemetry script if it is installed and enabled
    func enableAppLaunchPrivacy(duration timeInterval: TimeInterval? = nil) async throws {
        let duration = timeInterval ?? self.appLaunchPrivacyDuration

        guard let appLaunchPrivacyTool = try Self.appLaunchPrivacyTool.get() else {
            throw AppError(String(format: NSLocalizedString("Could not find %@", comment: "error message when failed to find app launch privacy tool"), Self.appLaunchPrivacyToolName))
        }

        /// If we have launch telemetry blocking enabled, this will invoke the telemetry block script before executing the operation, and then disable it after the given time interval
        if FileManager.default.fileExists(atPath: appLaunchPrivacyTool.path) {
            dbg("invoking telemetry launch block script:", appLaunchPrivacyTool.path)
            let privacyEnabled = try await Process.exec(cmd: appLaunchPrivacyTool.path, "enable").expect()
            if privacyEnabled.terminationStatus != 0 {
                throw AppError(NSLocalizedString("Failed to block launch telemetry", comment: "error message"), failureReason: [privacyEnabled.stdout, privacyEnabled.stderr].compactMap(\.utf8String).joined())
            }

            // clear any previous observer
            clearAppLaunchPrivacyObserver()

            let observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { note in
                dbg("application exiting; disabling app launch privacy mode")
                Task {
                    do {
                        try await self.disableAppLaunchPrivacy()
                    } catch {
                        dbg("disableAppLaunchPrivacy error:", error)
                    }
                }
            }

            self.appLaunchPrivacyDeactivator = observer

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                Task {
                    do {
                        if observer.isEqual(self.appLaunchPrivacyDeactivator) {
                            dbg("disabling app launch privacy")
                            try await self.disableAppLaunchPrivacy()
                        } else {
                            dbg("app launch privacy timer marker became invalid; skipping disable")
                        }
                    } catch {
                        dbg("error unblocking launch telemetry:", error)
                    }
                }
            }
        }
    }

    /// Saves the telemetry script to the user's application folder
    func saveAppLaunchPrivacyTool(source: Bool) throws -> URL {
        dbg("installing script")

        guard let scriptFile = try FairManager.appLaunchPrivacyTool.get() else {
            throw CocoaError(.fileNoSuchFile)
        }

        // clear any previous script if it exists
        try? FileManager.default.removeItem(at: scriptFile)

        if source {
            let swiftFile = scriptFile.appendingPathExtension("swift")
            dbg("writing source to file:", swiftFile.path)
            try Self.appLaunchPrivacyToolSource.get().write(to: swiftFile)
            return swiftFile
        } else {
            let executableFile = scriptFile
            dbg("writing binary to file:", executableFile.path)
            let encodedTool = try Self.appLaunchPrivacyToolBinary.get()
            guard let decodedTool = Data(base64Encoded: encodedTool, options: [.ignoreUnknownCharacters]) else {
                throw AppError(String(format: NSLocalizedString("Unable to decode %@", comment: "error message"), Self.appLaunchPrivacyToolName))
            }
            try decodedTool.write(to: executableFile)
            return executableFile
        }
    }

    /// Installs a swift utility that will block telemetry. This needs to be a compiled program rather than a shell script, because we want to set the setuid bit on it to be able to invoke it without asking for the admin password every time.
    /// - Parameter compiler: the compiler to use to build the script (e.g., `"/usr/bin/swiftc"`), or `nil` to install the bundled binary directly
    func installAppLaunchPrivacyTool(compiler: String? = nil) async throws {
        let swiftFile = try saveAppLaunchPrivacyTool(source: true)
        let compiledOutput: URL

        if let compiler = compiler {
            compiledOutput = swiftFile.deletingPathExtension()

            let swiftCompilerInstalled = FileManager.default.isExecutableFile(atPath: compiler)

            if swiftCompilerInstalled {
                throw AppError(NSLocalizedString("Developer tools not found", comment: "error message"), failureReason: NSLocalizedString("This operation requires that the swift compiler be installed on the host machine in order to build the necessary tools. Please install Xcode in order to enable telemetry blocking.", comment: "error failure reason message"))
            }

            dbg("compiling script:", swiftFile.path, "to:", compiledOutput)

            let result = try await Process.exec(cmd: "/usr/bin/swiftc", "-o", compiledOutput.path, swiftFile.path).expect()
            if result.terminationStatus != 0 {
                throw AppError(String(format: NSLocalizedString("Error compiling %@", comment: "error message"), Self.appLaunchPrivacyToolName), failureReason: [result.stdout, result.stderr].compactMap(\.utf8String).joined(separator: "\n"))
            }
        } else {
            compiledOutput = try saveAppLaunchPrivacyTool(source: false)
        }

        // set the root uid bit on the script so we can execute it without asking for the password each time
        let setuid = "/usr/sbin/chown root '\(compiledOutput.path)' && /bin/chmod 4750 '\(compiledOutput.path)'"
        let _ = try await NSUserScriptTask.fork(command: setuid, admin: true)
    }

    /// Invoked when the `appLaunchPrivacy` setting changes
    func handleChangeAppLaunchPrivacy(enabled: Bool) {
        Task {
            await self.trying {
                do {
                    if enabled == true {
                        try await self.installAppLaunchPrivacyTool()
                    } else {
                        if let script = try? Self.appLaunchPrivacyTool.get() {
                            if FileManager.default.fileExists(atPath: script.path) {
                                dbg("removing script at:", script.path)
                                try FileManager.default.removeItem(at: script)
                            }
                            if FileManager.default.fileExists(atPath: script.appendingPathExtension("swift").path) {
                                dbg("removing script at:", script.path)
                                try FileManager.default.removeItem(at: script.appendingPathExtension("swift"))
                            }
                        }
                    }
                } catch {
                    // any failure to install should disable the toggle
                    self.appLaunchPrivacy = false
                    throw error
                }
            }
        }
    }


    @ViewBuilder func launchPrivacyButton() -> some View {
        if self.appLaunchPrivacy == false {
        } else if self.appLaunchPrivacyDeactivator == nil {
            Text("Ready", comment: "launch privacy activate toolbar button title when in the inactive state")
                .label(image: FairSymbol.shield_slash_fill.symbolRenderingMode(.hierarchical).foregroundStyle(Color.brown, Color.gray))
                .button {
                    await self.trying {
                        try await self.enableAppLaunchPrivacy()
                    }
                }
                .help(Text("App launch telemetry blocking is enabled but not currently active. It will automatically activate upon launching an app from the App Fair, or clicking this button will manually activate it and then deactivate in \(Text(duration: self.appLaunchPrivacyDuration))", comment: "launch privacy activate toolbar button tooltip when in the inactive state"))
        } else {
            Text("Active", comment: "launch privacy button toolbar button title when in the activate state")
                .label(image: FairSymbol.shield_fill.symbolRenderingMode(.hierarchical).foregroundStyle(Color.orange, Color.blue))
                .button {
                    await self.trying {
                        try await self.disableAppLaunchPrivacy()
                    }
                }
                .help(Text("App Launch Privacy is currently active for \(Text(duration: self.appLaunchPrivacyDuration)). Click this button to deactivate privacy mode.", comment: "launch privacy button toolbar button title when in the inactivate state"))
        }
    }
}
#endif

extension Error {
    /// Returns true if this error indicates that the user cancelled an operaiton
    var isURLCancelledError: Bool {
        (self as NSError).domain == NSURLErrorDomain && (self as NSError).code == -999
    }
}
