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

public struct AppSettingsView: View {
    @EnvironmentObject var fairManager: FairManager

    public enum Tabs: Hashable {
        case general
        case fairapps
        case homebrew
        case privacy
        case advanced
    }

    public var body: some View {
        TabView {
            GeneralSettingsView()
                .padding(20)
                .tabItem {
                    Text("General", comment: "general preferences tab title")
                        .label(image: FairSymbol.switch_2)
                        .symbolVariant(.fill)
                }
                .tag(Tabs.general)
            if let appSourceInv = fairManager.appSourceInventories.first {
                FairAppsSettingsView()
                    .environmentObject(appSourceInv)
                    .padding(20)
                    .tabItem {
                        Text("Fairapps", comment: "fairapps preferences tab title")
                            .label(image: appSourceInv.symbol)
                            .symbolVariant(.fill)
                    }
                    .tag(Tabs.fairapps)
            }
#if os(macOS)
            if let homeBrewInv = fairManager.homeBrewInv {
                HomebrewSettingsView()
                    .environmentObject(homeBrewInv)
                    .padding(20)
                    .tabItem {
                        Text("Homebrew", comment: "homebrew preferences tab title")
                            .label(image: HomebrewInventory.symbol)
                            .symbolVariant(.fill)
                    }
                    .tag(Tabs.homebrew)
            }
#endif
            PrivacySettingsView()
                .padding(20)
                .tabItem {
                    Text("Privacy", comment: "privacy preferences tab title")
                        .label(image: FairSymbol.hand_raised)
                        .symbolVariant(.fill)
                }
                .tag(Tabs.privacy)
            if let appSourceInv = fairManager.appSourceInventories.first {
                AdvancedSettingsView()
                    .environmentObject(appSourceInv)
                    .padding(20)
                    .tabItem {
                        Text("Advanced", comment: "advanced preferences tab title")
                            .label(image: FairSymbol.gearshape)
                            .symbolVariant(.fill)
                    }
                    .tag(Tabs.advanced)
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}

#if os(macOS)
struct HomebrewSettingsView: View {
    @EnvironmentObject var fairManager: FairManager
    @EnvironmentObject var homeBrewInv: HomebrewInventory

    @State private var homebrewOperationInProgress = false
    @State private var homebrewInstalled: Bool? = nil

    var body: some View {
        settingsForm
            .task {
                self.homebrewInstalled = homeBrewInv.isHomebrewInstalled()
            }
    }

    var settingsForm: some View {
        VStack {
            Form {
                HStack {
                    Toggle(isOn: $homeBrewInv.enableHomebrew) {
                        Text("Homebrew Casks", comment: "settings switch title for enabling homebrew cask support")
                    }
                    .onChange(of: homeBrewInv.enableHomebrew) { enabled in
                        if false && (enabled == false) { // un-installing also removes all the casks, and so re-installation won't know about existing apps; disable this behavior until we can find a different location for the Caskroom (and support migration from older clients)
                            // un-install the local homebrew cache if we ever disable it; this makes it so we don't need a local cache location
                            Task {
                                try await homeBrewInv.uninstallHomebrew()
                                self.homebrewInstalled = homeBrewInv.isHomebrewInstalled()
                            }
                        }
                    }
                }
                .toggleStyle(.switch)
                .help(Text("Adds homebrew Casks to the sources of available apps.", comment: "tooltip text for switch to enable homebrew support"))

                Group {
                    Group {
                        Toggle(isOn: $homeBrewInv.manageCaskDownloads) {
                            Text("Use integrated download manager", comment: "homebrew preference checkbox for enabling the integrated download manager")
                        }
                        .help(Text("Whether to use the built-in download manager to handle downloading and previewing Cask artifacts. This will permit Cask installation to be monitored and cancelled from within the app. Disabling this preference will cause brew to use curl for downloading, which will not report progress in the user-interface.", comment: "tooltip help text for preference to enable integrated download homebrew download manager"))

                        Toggle(isOn: $homeBrewInv.forceInstallCasks) {
                            Text("Install overwrites previous app installation", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Whether to overwrite a prior installation of a given Cask. This could cause a newer version of an app to be overwritten by an earlier version.", comment: "tooltip help text for preference"))

                        Toggle(isOn: $homeBrewInv.quarantineCasks) {
                            Text("Quarantine installed apps", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Marks apps installed with homebrew cask as being quarantined, which will cause a system gatekeeper check and user confirmation the first time they are run.", comment: "tooltip help text for homebrew preference checkbox"))

                        Toggle(isOn: $homeBrewInv.permitGatekeeperBypass) {
                            Text("Permit gatekeeper bypass", comment: "tooltip help text for homebrew preference")
                        }
                        .help(Text("Allows the launching of quarantined apps that are not signed and notarized. This will prompt the user for confirmation each time an app identified as not being signed before it will be launched.", comment: "tooltip help text for homebrew preference"))

                        Toggle(isOn: $homeBrewInv.installDependencies) {
                            Text("Automatically install dependencies", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Automatically attempt to install any required dependencies for a cask.", comment: "homebrew preference checkbox tooltip"))

                        Toggle(isOn: $homeBrewInv.ignoreAutoUpdatingAppUpdates) {
                            Text("Exclude auto-updating apps from updates list", comment: "homebrew preference checkbox")
                        }
                        .help(Text("If a cask marks itself as handling its own software updates internally, exclude the cask from showing up in the “Updated” section. This can help avoid showing redundant updates for apps that expect to be able to update themselves, but can also lead to these apps being stale when they are next launched.", comment: "homebrew preference checkbox tooltip"))

                        Toggle(isOn: $homeBrewInv.zapDeletedCasks) {
                            Text("Clear all app info on delete", comment: "homebrew preference checkbox")
                        }
                        .help(Text("When deleting apps, also try to delete all the info stored by the app, including preferences, user data, and other info. This operation is known as “zapping” the app, and it will attempt to purge all traces of the app from your system, with the possible side-effect of also removing infomation that could be useful if you were to ever re-install the app.", comment: "homebrew preference checkbox tooltip"))
                    }

                    Group {

                        Toggle(isOn: $homeBrewInv.allowCasksWithoutApp) {
                            Text("Show casks without app artifacts", comment: "homebrew preference checkbox")
                            //.label(.bolt)
                        }
                        .help(Text("This permits the installation of apps that don't list any launchable artifacts with an .app extension. Such apps will not be able to be launched directly from the App Fair app, but they may exist as system extensions or launch services.", comment: "homebrew preference checkbox tooltip"))

                        Toggle(isOn: $homeBrewInv.requireCaskChecksum) {
                            Text("Require cask checksum", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Requires that downloaded artifacts have an associated SHA-256 cryptographic checksum to verify that they match the version that was added to the catalog. This help ensure the integrity of the download, but may exclude some casks that do not publish their checksums, and so is disabled by default.", comment: "homebrew preference checkbox tooltip"))

                        Toggle(isOn: $homeBrewInv.enableBrewSelfUpdate) {
                            Text("Enable Homebrew self-update", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Allow Homebrew to update itself while installing other packages.", comment: "homebrew preference checkbox tooltip"))

                        // switching between the system-installed brew and locally cached brew doesn't yet work
#if DEBUG
#if false
                        Toggle(isOn: $homeBrewInv.useSystemHomebrew) {
                            Text("Use system Homebrew installation", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Use the system-installed Homebrew installation", comment: "homebrew preference checkbox tooltip"))
                        .disabled(!HomebrewInventory.globalBrewInstalled)
#endif
                        Toggle(isOn: $homeBrewInv.enableBrewAnalytics) {
                            Text("Enable installation telemetry", comment: "homebrew preference checkbox")
                        }
                        .help(Text("Permit Homebrew to send telemetry to Google about the packages you install and update. See https://docs.brew.sh/Analytics", comment: "homebrew preference checkbox tooltip"))
#endif
                    }
                    .disabled(homeBrewInv.enableHomebrew == false)
                }
            }

            Divider()

            Section {
                GroupBox {
                    VStack {
                        let brewPath = (homeBrewInv.brewInstallRoot.path as NSString).abbreviatingWithTildeInPath
                        Text("""
                            Homebrew is a repository of third-party applications and installers called “Casks”. These packages are installed and managed using the `brew` command and are typically placed in the `/Applications/` folder.

                            Homebrew Casks are not subject to the same sandboxing, entitlement disclosure, and source transparency requirements as App Fair fair-ground apps, and so should only be installed from trusted sources.

                            Read more at: [https://brew.sh](https://brew.sh)
                            Browse all Casks: [https://formulae.brew.sh/cask/](https://formulae.brew.sh/cask/)
                            Location: \(brewPath)
                            """, comment: "homebrew preference description")
                        // .textSelection(.enabled) // bug that causes lines to stop wrapping when text is selected
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .frame(height: 12)
                                .opacity(homebrewOperationInProgress ? 1.0 : 0.0)
                            Text("Reveal", comment: "homebrew preference button for showing locating of homebrew installation")
                                .button {
                                    NSWorkspace.shared.activateFileViewerSelecting([homeBrewInv.brewInstallRoot.absoluteURL]) // else: “NSURLs written to the pasteboard via NSPasteboardWriting must be absolute URLs.  NSURL 'Homebrew/ -- file:///Users/home/Library/Application Support/app.App-Fair/appfair-homebrew/' is not an absolute URL”
                                }
                                .disabled(isBrewInstalled == false)
                                .help(Text("Browse the Homebrew installation folder using the Finder", comment: "homebrew preference button tooltip"))

#if DEBUG

                            if isBrewInstalled {
                                Text("Reset Homebrew", comment: "button text on Homebrew preferences for resetting the Homebrew installation")
                                    .button {
                                        homebrewOperationInProgress = true
                                        await fairManager.trying {
                                            try await homeBrewInv.uninstallHomebrew()
                                            dbg("caskManager.uninstallHomebrew success")
                                            self.homebrewInstalled = homeBrewInv.isHomebrewInstalled()
                                        }
                                        self.homebrewOperationInProgress = false
                                    }
                                    .disabled(self.homebrewOperationInProgress)
                                    .help(Text("This will remove the version of Homebrew that is used locally by the App Fair. It will not affect any system-level Homebrew installation that may be present elsewhere. Homebrew can be re-installed again afterwards.", comment: "tooltip text for button to uninstall homebrew on brew preferences panel"))
                                    .padding()
                            } else {
                                Text("Setup Homebrew", comment: "button text on Homebrew preferences for installing Homebrew")
                                    .button {
                                        homebrewOperationInProgress = true
                                        await fairManager.trying {
                                            try await homeBrewInv.installHomebrew(force: true, retainCasks: false)
                                            dbg("caskManager.installHomebrew success")
                                            self.homebrewInstalled = homeBrewInv.isHomebrewInstalled()
                                        }
                                        self.homebrewOperationInProgress = false
                                    }
                                    .disabled(self.homebrewOperationInProgress)
                                    .help(Text("Download homebrew and set it up for use by the App Fair. It will be installed locally to the App Fair and will not affect any other version that may be installed on the system. This operation will be performed automatically if any cask is installed and there is no local version of Homebrew found on the system.", comment: "tooltip text for button to install homebrew on brew preferences panel"))
                                    .padding()

                            }
#endif
                        }
                    }
                    .frame(maxWidth: .infinity)
                } label: {
                    Text("About Homebrew Casks", comment: "homebrew preference group box title")
                        .font(.headline)
                }
            }
        }
    }

    var isBrewInstalled: Bool {
        // override locally so we can control state
        if let homebrewInstalled = homebrewInstalled {
            return homebrewInstalled
        }
        return homeBrewInv.isHomebrewInstalled()
    }
}
#endif // os(macOS)


struct FairAppsSettingsView: View {
    //@EnvironmentObject var fairManager: FairManager
    @EnvironmentObject var fairAppmacOSInv: AppSourceInventory

    @State var hoverRisk: AppRisk? = nil

    var body: some View {
        Form {
            HStack(alignment: .top) {
                AppRiskPicker(risk: $fairAppmacOSInv.riskFilter, hoverRisk: $hoverRisk)
                (hoverRisk ?? fairAppmacOSInv.riskFilter).riskSummaryText(bold: true)
                    .textSelection(.enabled)
                    .font(.body)
                    .frame(height: 150, alignment: .top)
                    .frame(maxWidth: .infinity)
            }

            Toggle(isOn: $fairAppmacOSInv.showPreReleases) {
                Text("Show Pre-Releases", comment: "fairapps preference checkbox")
            }
            .help(Text("Display releases that are not yet production-ready according to the developer's standards.", comment: "fairapps preference checkbox tooltip"))

            Text("Pre-releases are experimental versions of software that are less tested than stable versions. They are generally released to garner user feedback and assistance, and so should only be installed by those willing experiment.", comment: "fairapps preference description")
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

        }
    }
}



struct GeneralSettingsView: View {
    @EnvironmentObject var fairManager: FairManager
    @AppStorage("iconBadge") private var iconBadge = true

    var body: some View {
        Form {
            ThemeStylePicker(style: $fairManager.themeStyle)

            Toggle(isOn: $iconBadge) {
                Text("Badge App Icon with update count", comment: "fairapps preference checkbox")
            }
            .help(Text("Show the number of updates that are available to install.", comment: "fairapps preference checkbox tooltip"))

            Divider()

            Toggle(isOn: $fairManager.openLinksInNewBrowser) {
                Text("Open links in new browser window", comment: "fairapps preference checkbox for whether links in the embedded browser should be opened in a new browser")
            }
            .help(Text("When using the embedded browser, clicking on links should open in a new default browser window rather than in the embedded browser itself.", comment: "fairapps preference checkbox tooltip"))

            Toggle(isOn: $fairManager.usePrivateBrowsingMode) {
                Text("Use private browsing for untrusted sites", comment: "fairapps preference checkbox for whether the embedded browser should use private browsing mode")
            }
            .help(Text("When using the embedded browser and navigating to an untrusted site such as the landing page for an unknown catalog, use private browsing mode to prevent cookies and history from being persisted across sessions.", comment: "fairapps preference checkbox tooltip"))
        }
    }
}


/// The preferred theme style for the app
public enum ThemeStyle: String, CaseIterable {
    case system
    case light
    case dark
}

extension ThemeStyle : Identifiable {
    public var id: Self { self }

    public var label: Text {
        switch self {
        case .system: return Text("System", comment: "general preference for theme style in popup menu")
        case .light: return Text("Light", comment: "general preference for theme style in popup menu")
        case .dark: return Text("Dark", comment: "general preference for theme style in popup menu")
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}


struct ThemeStylePicker: View {
    @Binding var style: ThemeStyle

    var body: some View {
        Picker(selection: $style) {
            ForEach(ThemeStyle.allCases) { themeStyle in
                themeStyle.label
            }
        } label: {
            Text("Theme:", comment: "picker title for general preference for theme style")
        }
        .radioPickerStyle()
    }
}

struct AppRiskPicker: View {
    @Binding var risk: AppRisk
    @Binding var hoverRisk: AppRisk?

    var body: some View {
        Picker(selection: $risk) {
            ForEach(AppRisk.allCases) { appRisk in
                appRisk.riskLabel()
                    .brightness(hoverRisk == appRisk ? 0.2 : 0.0)
                    .onHover {
                        self.hoverRisk = $0 ? appRisk : nil
                    }
            }
        } label: {
            Text("Risk Exposure:", comment: "fairapps preference title for risk management")
        }
        .radioPickerStyle()
    }
}

////struct ExperimentalSettingsView: View {
//    @EnvironmentObject var fairManager: FairManager
//    @EnvironmentObject var fairAppmacOSInv: AppSourceInventory
//
//    var body: some View {
//    }
//}

extension View {
    func toggleStyleCheckbox() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #else
        self
        #endif
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject var fairManager: FairManager
    @EnvironmentObject var fairAppmacOSInv: AppSourceInventory


    var body: some View {
        VStack {
            Form {
                Group {
                    Toggle(isOn: $fairAppmacOSInv.autoUpdateCatalogApp) {
                        Text("Keep catalog app up to date", comment: "preference checkbox")
                    }
                    .help(Text("Automatically download and apply updates to the App Fair catalog browser app.", comment: "preference checkbox tooltip"))
                    .toggleStyleCheckbox()

                    Toggle(isOn: $fairAppmacOSInv.relaunchUpdatedApps) {
                        Text("Re-launch updated apps", comment: "preference checkbox")
                    }
                    .help(Text("Automatically re-launch an app when it has been updated. Otherwise, the updated version will be used after quitting and re-starting the app.", comment: "preference checkbox tooltip"))

                    Toggle(isOn: $fairManager.enableUserSources) {
                        Text("Enable additional sources", comment: "fairapps preference checkbox for whether user sources should be enabled")
                    }
                    .help(Text("Enable additional custom app sources, which can be added and removed from the sidebar with the plus and minus buttons.", comment: "fairapps preference checkbox tooltip"))

                    Toggle(isOn: $fairAppmacOSInv.enablePlatformConversion) {
                        Text("Enable platform conversion for download apps", comment: "fairapps preference checkbox for whether platform conversion should be enabled")
                    }
                    .help(Text("Enable additional custom app sources, which can be added and removed from the sidebar with the plus and minus buttons.", comment: "fairapps preference checkbox tooltip"))

                    Toggle(isOn: $fairManager.enableSponsorship) {
                        Text("Enable sponsorship links", comment: "preference checkbox")
                    }
                    .help(Text("Enable support for patronage and funding links for individual apps.", comment: "preference checkbox tooltip"))
                }

                Divider()

                Group {
                    Toggle(isOn: $fairManager.enableInstallWarning) {
                        Text("Require app install confirmation", comment: "preference checkbox")
                    }
                    .help(Text("Installing an app will present a confirmation alert to the user. If disabled, apps will be installed and updated without confirmation.", comment: "preference checkbox tooltip"))
                    .toggleStyleCheckbox()

                    Toggle(isOn: $fairManager.enableDeleteWarning) {
                        Text("Require app delete confirmation", comment: "preference checkbox")
                    }
                    .help(Text("Deleting an app will present a confirmation alert to the user. If disabled, apps will be deleted without confirmation.", comment: "preference checkbox tooltip"))
                    .toggleStyleCheckbox()
                }

                Divider()

                Text("Clear caches", comment: "button label for option to clear local cache data in the app settings")
                    .button {
                        fairManager.clearCaches()
                        //HTTPCookieStorage.shared.removeCookies(since: .distantPast)
                    }
                    .help(Text("Purges the local cache of icons and app descriptions", comment: "button help text for option to clear local cache data in the app settings"))

                Group {
                    HStack {
                        TextField(text: fairManager.$hubProvider) {
                            Text("Hub Host", comment: "advanced preference text field label for the GitHub host")
                        }
                    }
                    HStack {
                        TextField(text: fairManager.$hubOrg) {
                            Text("Organization", comment: "advanced preference text field label for the GitHub organization")
                        }
                    }
                    HStack {
                        TextField(text: fairManager.$hubRepo) {
                            Text("Repository", comment: "advanced preference text field label for the GitHub repository")
                        }
                    }
                    //                HStack {
                    //                    SecureField("Token", text: fairManager.$hubToken)
                    //                }
                    //
                    //                Text(atx: "The token is optional, and is only needed for development or advanced usage. One can be created at your [GitHub Personal access token](https://github.com/settings/tokens) setting").multilineTextAlignment(.trailing)

                    HelpButton(url: "https://github.com/settings/tokens")
                }
            }
            .padding(20)
        }
    }
}

extension Text {
    /// Creates a Text like "10 seconds", "2 hours"
    init(duration: TimeInterval, style: Date.ComponentsFormatStyle.Style = .wide) {
        self.init(Date(timeIntervalSinceReferenceDate: 0)..<Date(timeIntervalSinceReferenceDate: duration), format: .components(style: style))
    }
}

struct PrivacySettingsView : View {
    @EnvironmentObject var fairManager: FairManager

    @Namespace var namespace

    var body: some View {
        VStack {
#if os(macOS)
            Form {
                HStack {
                    Toggle(isOn: $fairManager.appLaunchPrivacy) {
                        Text("App Launch Privacy:", comment: "app privacy preference enable switch")
                    }
                    .toggleStyle(.switch)
                    .help(Text("By default, macOS reports every app launch event to a remote server, which could expose your activities to third parties. Enabling this setting will block this telemetry.", comment: "app privacy preference enable switch tooltip"))
                    .onChange(of: fairManager.appLaunchPrivacy) { enabled in
                        self.fairManager.handleChangeAppLaunchPrivacy(enabled: enabled)
                    }

                    Spacer()
                    fairManager.launchPrivacyButton()
                        .buttonStyle(.bordered)
                        .focusable(true)
                        .prefersDefaultFocus(in: namespace)
                }

                Picker(selection: $fairManager.appLaunchPrivacyDuration) {
                    Text(duration: 10.0).tag(10.0) // 10 seconds
                    Text(duration: 60.0).tag(60.0) // 60 seconds
                    Text(duration: 60.0 * 30).tag(60.0 * 30) // 1/2 hour
                    Text(duration: 60.0 * 60.0 * 1.0).tag(60.0 * 60.0 * 1.0) // 1 hour
                    Text(duration: 60.0 * 60.0 * 2.0).tag(60.0 * 60.0 * 2.0) // 2 hours
                    Text(duration: 60.0 * 60.0 * 12.0).tag(60.0 * 60.0 * 12.0) // 12 hours
                    Text(duration: 60.0 * 60.0 * 24.0).tag(60.0 * 60.0 * 24.0) // 24 hours

                    Text("Until App Fair Exit", comment: "app launch privacy preference menu label").tag(TimeInterval(60.0 * 60.0 * 24.0 * 365.0 * 100.0)) // 100 years is close enough to forever
                } label: {
                    Text("Duration:", comment: "app launch privacy activation duration menu title")
                }
                .help(Text("The amount of time that App Launch Privacy will remain enabled before it is automatically disabled. Exiting the App Fair app will always disable App Launch privacy mode.", comment: "app launch privacy duration menu tooltip"))
                .pickerStyle(.menu)
                .disabled(fairManager.appLaunchPrivacy == false)
                .fixedSize() // otherwise the picker expands greedily

                scriptPreviewRow()
            }
            .padding()
#endif


            Divider()

            GroupBox {
                Text("""
                    The macOS operating system reports all application launches to third-party servers. Preventing this tracking is accomplished by temporarily blocking network traffic to these servers during the launch of an application. Enabling this feature will require authenticating as an administrator.

                    App Launch Privacy will block telemetry from being sent when an app is opened using the App Fair's “Launch” button, or when it is manually enabled using the shield button.

                    Privacy mode will be automatically de-activated after the specified duration, as well as when quitting App Fair.app. Privacy mode should not be left permanently disabled, because it may prevent certificate revocation checks from taking place.
                    """, comment: "app launch privacy description text")
                .font(.body)
                .textSelection(.enabled) // bug that causes lines to stop wrapping when text is selected (seems to be fixed as of 12.4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
            } label: {
                Text("About App Launch Privacy", comment: "app launch privacy description group box title")
                    .font(.headline)
            }
        }
    }

    func scriptPreviewRow() -> some View {
        Group {
            #if os(macOS)
            let scriptURL = try? FairManager.appLaunchPrivacyTool.get()
            #else
            let scriptURL: URL? = nil
            #endif

            if let scriptURL = scriptURL {
                let scriptFolder = (scriptURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath

                if fairManager.appLaunchPrivacy == true {
                    HStack {
                        TextField(text: .constant(scriptFolder)) {
                            Text("Installed at:", comment: "app launch privacy text field label for installation location")
                        }
                        .textFieldStyle(.plain)
                        .textSelection(.disabled)
                        #if os(macOS)
                        .focusable(false)
                        #endif

                        Text("Show", comment: "app launch privacy button title for displaying location of installed script")
                            .button {
                                #if os(macOS)
                                NSWorkspace.shared.selectFile(scriptURL.appendingPathExtension("swift").path, inFileViewerRootedAtPath: scriptFolder)
                                #endif
                            }
                    }
                } else {
                    HStack {
                        TextField(text: .constant(scriptFolder)) {
                            Text("Install location:", comment: "app launch privacy text field title for script installation location")
                        }
                        .textFieldStyle(.plain)
                        .textSelection(.disabled)
                        #if os(macOS)
                        .focusable(false)
                        #endif

                        Text("Preview", comment: "app launch privacy button title for previewing location where script will be installed")
                            .button {
                                #if os(macOS)
                                if !FileManager.default.isReadableFile(atPath: scriptURL.path) {
                                    // save the script so we can preview it
                                    if let swiftFile = try? self.fairManager.saveAppLaunchPrivacyTool(source: true) {
                                        NSWorkspace.shared.selectFile(swiftFile.path, inFileViewerRootedAtPath: scriptFolder)
                                    }
                                }
                                #endif
                            }
                    }
                }
            }
        }
    }

}

