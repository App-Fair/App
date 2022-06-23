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
import Combine

@available(macOS 12.0, iOS 15.0, *)
@MainActor public final class FairManager: SceneManager {
    @AppStorage("themeStyle") var themeStyle = ThemeStyle.system

    @AppStorage("firstLaunchV1") public var firstLaunchV1 = true

    @AppStorage("enableInstallWarning") public var enableInstallWarning = true
    @AppStorage("enableDeleteWarning") public var enableDeleteWarning = true

    /// The base domain of the provider for the hub
    @AppStorage("hubProvider") public var hubProvider = "github.com"
    /// The organization name of the hub
    @AppStorage("hubOrg") public var hubOrg = appfairName
    /// The name of the base repository for the provider
    @AppStorage("hubRepo") public var hubRepo = Bundle.appfairDefaultAppName

    /// An optional authorization token for direct API usagefor the organization
    @AppStorage("hubToken") public var hubToken = ""

    /// Whether to try blocking launch telemetry reporting
    @AppStorage("appLaunchPrivacy") public var appLaunchPrivacy = false

    /// The duration to continue blocking launch telemtry after an app has been launched (since the OS retries for a certain amount of time if the initial connection fails)
    @AppStorage("appLaunchPrivacyDuration") public var appLaunchPrivacyDuration: TimeInterval = 60.0

    /// Whether links clicked in the embedded browser should open in a new browser window
    @AppStorage("openLinksInNewBrowser") var openLinksInNewBrowser = true

    /// The appManager, which should be extracted as a separate `EnvironmentObject`
    @Published var fairAppInv: FairAppInventory
    /// The caskManager, which should be extracted as a separate `EnvironmentObject`
    @Published var homeBrewInv: HomebrewInventory

    /// The apps that have been installed or updated in this session
    @Published var sessionInstalls: Set<AppInfo.ID> = []

    /// The current app exit observer for app launch privacy; it will be cleared when the observer expires
    @Published private var appLaunchPrivacyDeactivator: NSObjectProtocol? = nil

    /// The current activities that are taking place for each bundle identifier
    @Published var operations: [BundleIdentifier: CatalogOperation] = [:]

    private var observers: [AnyCancellable] = []

    required internal init() {
        self.fairAppInv = FairAppInventory.default
        self.homeBrewInv = HomebrewInventory.default

        super.init()

        // track any changes to fairAppInv and homeBrewInv and broadcast their changes
        self.observers.append(self.fairAppInv.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        self.observers.append(self.homeBrewInv.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })


        /// The gloal quick actions for the App Fair
        self.quickActions = [
            QuickAction(id: "refresh-action", localizedTitle: NSLocalizedString("Refresh Catalog", bundle: .module, comment: "action button title for refreshing the catalog")) { completion in
                dbg("refresh-action")
                Task {
                    //await self.appManager.fetchApps(cache: .reloadIgnoringLocalAndRemoteCacheData)
                    completion(true)
                }
            }
        ]
    }

    func refresh(clearCatalog: Bool) async throws {
        async let v1: () = fairAppInv.refreshAll(clearCatalog: clearCatalog)
        async let v2: () = homeBrewInv.refreshAll(clearCatalog: clearCatalog)
        let _ = try await (v1, v2) // perform the two refreshes in tandem
    }

    /// Attempts to perform the given action and adds any errors to the error list if they fail.
    func trying(block: () async throws -> ()) async {
        do {
            try await block()
        } catch {
            fairAppInv.errors.append(error as? AppError ?? AppError(error))
        }
    }

    func updateCount() -> Int {
        return fairAppInv.updateCount()
            + (homeBrewInv.enableHomebrew ? homeBrewInv.updateCount() : 0)
    }

    /// The icon for the given item
    /// - Parameters:
    ///   - info: the info to check
    ///   - transition: whether to use a fancy transition
    /// - Returns: the icon
    @ViewBuilder func iconView(for info: AppInfo, transition: Bool = false) -> some View {
        Group {
            if info.isCask == true {
                homeBrewInv.icon(for: info, useInstalledIcon: false)
            } else {
                info.catalogMetadata.iconImage()
            }
        }
        //.transition(AnyTransition.scale(scale: 0.50).combined(with: .opacity)) // bounce & fade in the icon
        .transition(transition == false ? AnyTransition.opacity : AnyTransition.asymmetric(insertion: AnyTransition.opacity, removal: AnyTransition.scale(scale: 0.75).combined(with: AnyTransition.opacity))) // skrink and fade out the placeholder while fading in the actual icon

    }

    func launch(_ info: AppInfo) async {
        await self.trying {
            if self.appLaunchPrivacy {
                try await self.enableAppLaunchPrivacy()
            }

            if info.isCask == true {
                try await homeBrewInv.launch(item: info)
            } else {
                await fairAppInv.launch(item: info.catalogMetadata)
            }
        }
    }

    func install(_ info: AppInfo, progress parentProgress: Progress?, manageDownloads: Bool? = nil, update: Bool = true, verbose: Bool = true) async {
        await self.trying {
            if info.isCask {
                try await homeBrewInv.install(item: info, progress: parentProgress, update: update)
            } else {
                try await fairAppInv.install(item: info.catalogMetadata, progress: parentProgress, update: update)
            }
            sessionInstalls.insert(info.id)
        }
    }

    func installedVersion(for item: AppInfo) -> String? {
        if item.isCask {
            return homeBrewInv.appInstalled(item: item)
        } else {
            return fairAppInv.appInstalled(item: item.catalogMetadata)
        }
    }

    func appUpdated(for item: AppInfo) -> Bool {
        if item.isCask {
            return homeBrewInv.appUpdated(item: item)
        } else {
            return fairAppInv.appUpdated(item: item.catalogMetadata)
        }
    }
}

// MARK: App Launch Privacy support

extension FairManager {
    static let appLaunchPrivacyToolName = "applaunchprivacy"

    /// The script that we will store in the Applications Script folder to block app launch snooping
    static let appLaunchPrivacyToolSource = Result {
        try Bundle.module.loadBundleResource(named: appLaunchPrivacyToolName + "/main.swift")
    }

    /// The executable that we will store in the Applications Script folder to block app launch snooping
    static let appLaunchPrivacyToolBinary = Result {
        try Bundle.module.loadBundleResource(named: appLaunchPrivacyToolName + ".b64")
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
    func disableAppLaunchPrivacy() throws {
        if let appLaunchPrivacyTool = try Self.appLaunchPrivacyTool.get() {
            dbg("disabling app launch privacy")
            let unblock = try Process.exec(cmd: appLaunchPrivacyTool.path, "disable")
            dbg(unblock.exitCode == 0 ? "successfully" : "unsuccessfully", "disabled app launch privacy:", unblock.stdout, unblock.stderr)
            if unblock.exitCode == 0 {
                clearAppLaunchPrivacyObserver()
            }
        }
    }

    /// Invokes the block launch telemetry script if it is installed and enabled
    func enableAppLaunchPrivacy(duration timeInterval: TimeInterval? = nil) async throws {
        let duration = timeInterval ?? self.appLaunchPrivacyDuration

        guard let appLaunchPrivacyTool = try Self.appLaunchPrivacyTool.get() else {
            throw AppError("Could not find \(Self.appLaunchPrivacyToolName)")
        }

        /// If we have launch telemetry blocking enabled, this will invoke the telemetry block script before executing the operation, and then disable it after the given time interval
        if FileManager.default.fileExists(atPath: appLaunchPrivacyTool.path) {
            dbg("invoking telemetry launch block script:", appLaunchPrivacyTool.path)
            let privacyEnabled = try Process.exec(cmd: appLaunchPrivacyTool.path, "enable")
            if privacyEnabled.exitCode != 0 {
                throw AppError("Failed to block launch telemetry", failureReason: (privacyEnabled.stdout + privacyEnabled.stderr).joined(separator: "\n"))
            }

            // clear any previous observer
            clearAppLaunchPrivacyObserver()

            let observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { note in
                dbg("application exiting; disabling app launch privacy mode")
                try? self.disableAppLaunchPrivacy()
            }

            self.appLaunchPrivacyDeactivator = observer

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                do {
                    if observer.isEqual(self.appLaunchPrivacyDeactivator) {
                        dbg("disabling app launch privacy")
                        try self.disableAppLaunchPrivacy()
                    } else {
                        dbg("app launch privacy timer marker became invalid; skipping disable")
                    }
                } catch {
                    dbg("error unblocking launch telemetry:", error)
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
                throw AppError("Unable to decode \(Self.appLaunchPrivacyToolName)")
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
                throw AppError("Developer tools not found", failureReason: "This operation requires that the swift compiler be installed on the host machine in order to build the necessary tools. Please install Xcode in order to enable telemetry blocking.")
            }

            dbg("compiling script:", swiftFile.path, "to:", compiledOutput)

            let result = try Process.exec(cmd: "/usr/bin/swiftc", "-o", compiledOutput.path, target: swiftFile)
            if result.exitCode != 0 {
                throw AppError("Error compiling \(Self.appLaunchPrivacyToolName)", failureReason: (result.stdout + result.stderr).joined(separator: "\n"))
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
            Text("Ready", bundle: .module, comment: "launch privacy activate toolbar button title when in the inactive state")
                .label(image: FairSymbol.shield_slash_fill.symbolRenderingMode(.hierarchical).foregroundStyle(Color.brown, Color.gray))
                .button {
                    await self.trying {
                        try await self.enableAppLaunchPrivacy()
                    }
                }
                .help(Text("App launch telemetry blocking is enabled but not currently active. It will automatically activate upon launching an app from the App Fair, or clicking this button will manually activate it and then deactivate in \(Text(duration: self.appLaunchPrivacyDuration))", bundle: .module, comment: "launch privacy activate toolbar button tooltip when in the inactive state"))
        } else {
            Text("Active", bundle: .module, comment: "launch privacy button toolbar button title when in the activate state")
                .label(image: FairSymbol.shield_fill.symbolRenderingMode(.hierarchical).foregroundStyle(Color.orange, Color.blue))
                .button {
                    await self.trying {
                        try self.disableAppLaunchPrivacy()
                    }
                }
                .help(Text("App Launch Privacy is currently active for \(Text(duration: self.appLaunchPrivacyDuration)). Click this button to deactivate privacy mode.", bundle: .module, comment: "launch privacy button toolbar button title when in the inactivate state"))
        }
    }
}

extension Error {
    /// Returns true if this error indicates that the user cancelled an operaiton
    var isURLCancelledError: Bool {
        (self as NSError).domain == NSURLErrorDomain && (self as NSError).code == -999
    }
}
