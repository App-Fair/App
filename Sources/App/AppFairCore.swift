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
import Combine

/// The source of the apps
public enum AppSource: String, CaseIterable {
    case homebrew
    case fairapps
}

extension AppSource : Identifiable {
    public var id: Self { self }
}

@available(macOS 12.0, iOS 15.0, *)
public extension AppSource {
    var label: Label<Text, Image> {
        switch self {
        case .fairapps:
            return Label { Text("Fairground", bundle: .module, comment: "app source title for fairground apps") } icon: { symbol.image }
        case .homebrew:
            return Label { Text("Homebrew", bundle: .module, comment: "app source title for homebrew apps") } icon: { symbol.image }
        }
    }

    var symbol: FairSymbol {
        switch self {
        case .fairapps:
            return .ticket
        case .homebrew:
            return .shippingbox_fill
        }
    }
}

struct AppInfo : Identifiable, Equatable {
    /// The catalog item metadata
    var catalogMetadata: AppCatalogItem

    /// The associated homebrew cask
    var cask: CaskItem?

    /// We are idenfitied as a cask item if we have no version date (which casks don't include in their metadata)
    var isCask: Bool {
        cask != nil
    }

    /// The bundle ID of the selected app (e.g., "app.App-Name")
    var id: AppCatalogItem.ID {
        catalogMetadata.id
    }

    /// Returns the homepage for the info URL
    var homepage: URL? {
        if let cask = self.cask {
            if let homepage = cask.homepage {
                if let url = URL(string: homepage) {
                    return url
                }
            }

            return nil
        } else {
            return catalogMetadata.homepage
        }
    }

    /// The categories as should be displayed in the UI; this will collapes sub-groups (i.e., game categories) into their parent groups.
    var displayCategories: [AppCategory] {
        catalogMetadata.appCategories
            .map { cat in
                switch cat {
                case .business: return .business
                case .developertools: return .developertools
                case .education: return .education
                case .entertainment: return .entertainment
                case .finance: return .finance
                case .graphicsdesign: return .graphicsdesign
                case .healthcarefitness: return .healthcarefitness
                case .lifestyle: return .lifestyle
                case .medical: return .medical
                case .music: return .music
                case .news: return .news
                case .photography: return .photography
                case .productivity: return .productivity
                case .reference: return .reference
                case .socialnetworking: return .socialnetworking
                case .sports: return .sports
                case .travel: return .travel
                case .utilities: return .utilities
                case .video: return .video
                case .weather: return .weather

                case .games: return .games

                case .actiongames: return .games
                case .adventuregames: return .games
                case .arcadegames: return .games
                case .boardgames: return .games
                case .cardgames: return .games
                case .casinogames: return .games
                case .dicegames: return .games
                case .educationalgames: return .games
                case .familygames: return .games
                case .kidsgames: return .games
                case .musicgames: return .games
                case .puzzlegames: return .games
                case .racinggames: return .games
                case .roleplayinggames: return .games
                case .simulationgames: return .games
                case .sportsgames: return .games
                case .strategygames: return .games
                case .triviagames: return .games
                case .wordgames: return .games
                }
            }
    }
}

extension Plist {
    /// The value of the `CFBundleIdentifier` key
    var bundleID: String? {
        self.CFBundleIdentifier
    }

    /// The value of the `CFBundleShortVersionString` key
    var versionString: String? {
        self.CFBundleShortVersionString
    }

    /// The value of the `CFBundleVersion` key
    var buildNumber: String? {
        self.CFBundleVersion
    }

    /// The semantic version for the `CFBundleShortVersionString` key.
    var appVersion: AppVersion? {
        versionString.flatMap({ AppVersion.init(string: $0, prerelease: false) })
    }
}


public typealias AppIdentifier = BundleIdentifier

// TODO: potentially separate these into separate types
// typealias AppIdentifier = XOr<BundleIdentifier>.Or<CaskIdentifier>

extension AppCatalogItem : Identifiable {
    public var id: AppIdentifier { bundleIdentifier }
}


#if os(macOS)
@available(macOS 12.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct SimpleTableView : View {
    struct TableRowValue : Identifiable {
        var id = UUID()
        var num = Int.random(in: 0...100)
        var str = UUID().uuidString
    }

    @State var selection: TableRowValue.ID? = nil
    @State var items: [TableRowValue] = (1...100).map({ SimpleTableView.TableRowValue(num: $0) })
    @State var sortOrder = [KeyPathComparator(\TableRowValue.num)]

    var body: some View {
        Table(items, selection: $selection, sortOrder: $sortOrder, columns: {
            TableColumn("String", value: \.str)
        })
    }
}
#endif

/// The current selected instance
@available(macOS 12.0, iOS 15.0, *)
enum Selection {
    case app(AppInfo)
}

@available(macOS 12.0, iOS 15.0, *)
struct AppFairCommands: Commands {
    @FocusedBinding(\.selection) private var selection: Selection??
    @FocusedBinding(\.sidebarSelection) private var sidebarSelection: SidebarSelection??

//    @FocusedBinding(\.reloadCommand) private var reloadCommand: (() async -> ())?

    var fairManager: FairManager

    var body: some Commands {

//        switch selection {
//        case .app(let app):
//        case .run(let run):
//        case .none:
//        case .some(.none):
//        }

//        CommandMenu("Fair") {
//            Button("Find") {
//                fairAppInv.activateFind()
//            }
//            .keyboardShortcut("F")
//        }

//        CommandGroup(before: .newItem) {
//            ShareAppButton()
//        }

        CommandMenu(Text("Sources", bundle: .module, comment: "menu title for fairground sources actions")) {

            Section {
                let items = SidebarSelection.homebrewItems
                navitem(items.0.sel).keyboardShortcut(items.0.key)
                navitem(items.1.sel).keyboardShortcut(items.1.key)
                navitem(items.2.sel).keyboardShortcut(items.2.key)
            } header: {
                Text("Homebrew", bundle: .module, comment: "source menu header text for section with homebrew catalog selection options")
            }

            Section {
                let items = SidebarSelection.fairappsItems
                navitem(items.0.sel).keyboardShortcut(items.0.key)
                navitem(items.1.sel).keyboardShortcut(items.1.key)
                navitem(items.2.sel).keyboardShortcut(items.2.key)
                navitem(items.3.sel).keyboardShortcut(items.3.key)
            } header: {
                Text("Fairground", bundle: .module, comment: "source menu header text for section with fairground catalog selection options").font(Font.caption)
            }

            Text("Refresh Catalogs", bundle: .module, comment: "menu title for refreshing the app catalog")
                .button(action: reloadAll)
                .keyboardShortcut("R")
//                .disabled(reloadCommand == nil)
        }
    }

    func navitem(_ selection: SidebarSelection) -> some View {
        Button {
            sidebarSelection = selection
        } label: {
            selection.sourceInfo.tintedLabel(monochrome: true).title
        }
    }

    func reloadAll() {
        Task {
            await fairManager.trying {
                try await fairManager.refresh(clearCatalog: false)
            }
        }
    }
}

/// The reason why an action failed
public enum AppFailure {
    case reloadFailed

    var failureReason: LocalizedStringKey? {
        switch self {
        case .reloadFailed: return "Reload Failed"
        }
    }
}

extension Picker {
    /// On macOS, sets the style as a radio picker style.
    /// On other platforms, has no effect.
    func radioPickerStyle() -> some View {
        #if os(macOS)
        self.pickerStyle(RadioGroupPickerStyle())
        #else
        self
        #endif
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct HelpButton : View {
    let url: String
    @Environment(\.openURL) var openURL

    public var body: some View {
        Button(role: .none, action: {
            if let url = URL(string: url) {
                openURL(url)
            }
        }) {
            //FairSymbol.questionmark_circle_fill
            FairSymbol.questionmark
        }
        .buttonStyle(.bordered)
    }

}

extension View {
    /// Redacts the view when the given condition is true
    @ViewBuilder public func redacting(when condition: Bool) -> some View {
        if condition {
            self.redacted(reason: .placeholder)
        } else {
            self
        }
    }
}

extension View {
    /// Applies a modifier to the view that matches a static directive.
    /// This is used to invoke methods that may be conditionally available.
    ///
    /// Example:
    ///
    /// ```
    /// List {
    ///     ForEach(elements, content: elementView)
    /// }
    /// .conditionally {
    ///     #if os(macOS)
    ///     $0.listStyle(.bordered(alternatesRowBackgrounds: true))
    ///     #endif
    /// }
    /// ```
    public func conditionally<V: View>(content matchingStaticCondition: (Self) -> (V)) -> V {
        matchingStaticCondition(self)
    }

    /// - See: ``View/conditionally(matchingStaticCondition:)``
    public func conditionally(content notMatchingStaticCondition: (Self) -> (Void)) -> Self {
        // this is the fall-through that simply returns the view itself.
        self
    }

    /// Centers this view in an `HStack` with spacers.
    /// - Parameters:
    ///   - alignment: the alignment to apply to the stack
    ///   - minLength: the minimum size of the spacers
    /// - Returns: the view centered in an `HStack` surrounded by `Spacer` views
    public func hcenter(alignment: VerticalAlignment = .center, minLength: CoreGraphics.CGFloat? = nil) -> some View {
        HStack(alignment: alignment) {
            Spacer(minLength: minLength)
            self
            Spacer(minLength: minLength)
        }
    }

    /// Centers this view in an `VStack` with spacers.
    /// - Parameters:
    ///   - alignment: the alignment to apply to the stack
    ///   - minLength: the minimum size of the spacers
    /// - Returns: the view centered in an `VStack` surrounded by `Spacer` views
    public func vcenter(alignment: HorizontalAlignment = .center, minLength: CoreGraphics.CGFloat? = nil) -> some View {
        VStack(alignment: alignment) {
            Spacer(minLength: minLength)
            self
            Spacer(minLength: minLength)
        }
    }

}

public extension View {
    /// Returns a `Bool` binding that indicates whether another binding is `null`
    func nullifyingBoolBinding<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: {
            binding.wrappedValue != nil
        }, set: { newValue in
            if newValue == false {
                binding.wrappedValue = .none
            }
        })
    }

    @available(macOS 12.0, iOS 15.0, *)
    func displayingFirstAlert<E: LocalizedError>(_ errorBinding: Binding<[E]>) -> some View {
        let presented: Binding<Bool> = Binding(get: {
            !errorBinding.wrappedValue.isEmpty
        }, set: { newValue in
            if newValue == false && !errorBinding.wrappedValue.isEmpty {
                errorBinding.wrappedValue.remove(at: 0)
            }
        })

        let firstError = errorBinding.wrappedValue.first

        return sheet(isPresented: presented) {
            VStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 55, height: 55, alignment: .center)
                    .padding()

                if let errorDescription = firstError?.errorDescription {
                    Text(errorDescription)
                        .font(Font.headline)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }

                if let failureReason = firstError?.failureReason {
                    Text(failureReason)
                        .font(Font.subheadline)
                        .textSelection(.enabled)
                        .lineLimit(5)
                }

                if let recoverySuggestion = firstError?.recoverySuggestion {
                    Text(recoverySuggestion)
                        .font(Font.subheadline)
                        .textSelection(.enabled)
                        .lineLimit(5)
                }

                if let underlyingError = (firstError as NSError?)?.underlyingErrors.first
                ?? (firstError as? AppError)?.underlyingError {
                    DisclosureGroup {
                        TextEditor(text: .constant(underlyingError.localizedDescription))
                            .textSelection(.disabled)
                            .font(Font.body.monospaced())
                            .focusable(false)
                            .frame(maxHeight: 200)
                    } label: {
                        Text("More Info", bundle: .module, comment: "error dialog disclosure button title for showing more information")
                    }
                }

                Button {
                    errorBinding.wrappedValue.removeFirst()
                } label: {
                    Text("OK", bundle: .module, comment: "error dialog button to dismiss the error").padding()
                }
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: 250)
            .padding()
//            .background(Material.thin)
            //.alert(Text(title), isPresented: .constant(true), actions: { EmptyView() }, message: { Text(message) })
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
extension View {
    /// Creates a button with the given optional async action.
    ///
    /// This is intended to be used with something like:
    ///
    /// ```
    /// @FocusedBinding(\.reloadCommand) private var reloadCommand: (() async -> ())?
    ///
    /// Text("Reload", bundle: .module, comment: "help text")
    ///     .label(symbol: "arrow.triangle.2.circlepath.circle")
    ///     .button(command: reloadCommand)
    /// ```
    ///
    /// The button will be disabled when the action is `nil`.
    func button(command: (() async -> ())?) -> some View {
        button {
            Task {
                await command?()
            }
        }
        .disabled(command == nil)
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct RootView : View {
    public var body: some View {
        NavigationRootView()
    }
}

struct SidebarSelection : Hashable {
    let source: AppSource
    let item: SidebarItem
}

enum SidebarItem : Hashable {
    case top
    case updated
    case installed
    case recent
    case category(_ category: AppCategory)

    /// The persistent identifier for this grouping
    var id: String {
        switch self {
        case .top:
            return "top"
        case .updated:
            return "updated"
        case .installed:
            return "installed"
        case .recent:
            return "recent"
        case .category(let category):
            return "category:" + category.rawValue
        }
    }

    /// True indicates that this sidebar specifies to filter for locally-installed packages
    var isLocalFilter: Bool {
        switch self {
        case .updated:
            return true
        case .installed:
            return true
        case .top:
            return false
        case .recent:
            return true
        case .category:
            return false
        }
    }
}


@available(macOS 12.0, iOS 15.0, *)
struct NavigationRootView : View {
    @EnvironmentObject var fairManager: FairManager

    @FocusedBinding(\.reloadCommand) private var reloadCommand: (() async -> ())?

    @State var selection: AppInfo.ID? = nil
    /// Indication that the selection should be scrolled to
    @State var scrollToSelection: Bool = false

    /// The current selection in the sidebar, defaulting to the `top` item of the initial `AppSource`.
    @State var sidebarSelection: SidebarSelection? = SidebarSelection(source: AppSource.allCases.first!, item: .top)
    //@State var sidebarSelection: SidebarSelection? = nil

    @SceneStorage("displayMode") var displayMode: TriptychOrient = TriptychOrient.allCases.first!
    @AppStorage("iconBadge") private var iconBadge = true
    //@SceneStorage("source") var source: AppSource = AppSource.allCases.first!

    @State var searchText: String = ""

    public var body: some View {
        triptychView
            .displayingFirstAlert($fairManager.fairAppInv.errors)
            .toolbar(id: "NavToolbar") {
//                ToolbarItem(placement: .navigation) {
//                    Button(action: toggleSidebar) {
//                        FairSymbol.sidebar_left.image
//                    })
//                }

                ToolbarItem(id: "AppPrivacy", placement: .automatic, showsByDefault: true) {
                    fairManager.launchPrivacyButton()
                }

                ToolbarItem(id: "ReloadButton", placement: .automatic, showsByDefault: true) {
                    Text("Reload", bundle: .module, comment: "refresh catalog toolbar button title")
                        .label(image: FairSymbol.arrow_triangle_2_circlepath.symbolRenderingMode(.hierarchical).foregroundStyle(Color.teal, Color.yellow, Color.blue))
                        .button {
                            await fairManager.trying {
                                try await fairManager.refresh(clearCatalog: false) // TODO: true when option or control key is down?
                            }
                        }
                        .hoverSymbol(activeVariant: .fill)
                        .help(Text("Refresh the app catalogs", bundle: .module, comment: "refresh catalog toolbar button tooltip"))
                }


                ToolbarItem(id: "DisplayModePicker", placement: .automatic, showsByDefault: false) {
                    DisplayModePicker(mode: $displayMode)
                }
            }
            .task(priority: .userInitiated) {
                dbg("refreshing fairground")
                await fairManager.trying {
                    try await fairManager.refresh(clearCatalog: false)
                }
            }
            .task(priority: .low) {
                do {
                    try await fairManager.homeBrewInv.installHomebrew(force: true, fromLocalOnly: true, retainCasks: true)
                } catch {
                    dbg("error unpacking homebrew in local cache:", error)
                }
            }
            .onChange(of: fairManager.updateCount()) { updateCount in
                if iconBadge == true {
                    UXApplication.shared.setBadge(updateCount)
                }
            }
            .onChange(of: iconBadge) { iconBadge in
                // update the badge when the setting changes
                UXApplication.shared.setBadge(iconBadge ? fairManager.updateCount() : 0)
            }
            .onChange(of: sidebarSelection) { selection in
                if selection?.item != .top { // only clear when switching away from the "popular" tab
                    searchText = "" // clear search whenever the sidebar selection changes
                }
            }
            .handlesExternalEvents(preferring: [], allowing: ["*"]) // re-use this window to open external URLs
            .onOpenURL(perform: handleURL)
    }

    /// Handles opening the URL schemes suppored by this app.
    ///
    /// Supported schemes:
    ///
    ///   1. `appfair://app/App-Name`: selects the "Apps" outline and searches for "app.App-Name"
    ///   1. `appfair://cask/token`: selects the "Casks" outline and searches for "homebrew/cask/token"
    func handleURL(_ url: URL) {
        let components = url.pathComponents
        dbg("handling app URL", url.absoluteString, "scheme:", url.scheme, "action:", components)
        if let scheme = url.scheme, scheme == "appfair" {
            var path = ([url.host ?? ""] + url.pathComponents)
                .filter { !$0.isEmpty && $0 != "." && $0 != "/" }

            if path.count < 1 {
                dbg("invalid URL path", path)
                return
            }

            if path.count == 2 && path.first == "cask" {
                path.insert("homebrew", at: 0)
            }

            let isCask = path.first == "homebrew"
            let searchID = path.joined(separator: isCask ? "/" : ".") // "homebrew/cask/iterm2" vs. "app/Tidal-Zone"

            let bundleID = BundleIdentifier(searchID)

            // random crashes seem to happen without dispatching to main
            self.searchText = bundleID.rawValue // needed to cause the item to appear
            self.sidebarSelection = SidebarSelection(source: isCask ? .homebrew : .fairapps, item: .top)

            // without the async, we crash with: 2022-01-16 15:59:21.205139-0500 App Fair[44011:2933267] [General] *** __boundsFail: index 2 beyond bounds [0 .. 1] … [NSSplitViewController removeSplitViewItem:] … s7SwiftUI22AppKitNavigationBridgeC10showDetail33_7420C33EDE6D7EA74A00CE41E680CEAELLySbAA0E18DestinationContentVF
            DispatchQueue.main.async {
                self.selection = bundleID
                dbg("selected app ID", self.selection)
//                        DispatchQueue.main.async {
//                            self.scrollToSelection = true // if the catalog item is offscreen, then the selection will fail, so we need to also refine the current search to the bundle id
//                        }
            }
        }
    }

    /// The currently selected source for the sidebar
    var sidebarSource: AppSource? {
        return sidebarSelection?.source
    }

    public var triptychView : some View {
        TriptychView(orient: $displayMode) {
            SidebarView(selection: $selection, scrollToSelection: $scrollToSelection, sidebarSelection: $sidebarSelection, displayMode: $displayMode, searchText: $searchText)
                .focusedSceneValue(\.sidebarSelection, $sidebarSelection)
        } list: {
            if let sidebarSource = sidebarSource {
                AppsListView(source: sidebarSource, sidebarSelection: sidebarSelection, selection: $selection, scrollToSelection: $scrollToSelection, searchTextSource: $searchText)
            } else {
                EmptyView() // TODO: better placeholder view for un-selected sidebar item
            }
        } table: {
            #if os(macOS)
            if let sidebarSource = sidebarSource {
                AppsTableView(source: sidebarSource, selection: $selection, sidebarSelection: sidebarSelection, searchText: $searchText)
            } else {
                EmptyView()
            }
            #endif
        } content: {
            AppDetailView(sidebarSelection: $sidebarSelection)
        }
        // warning: this spikes CPU usage when idle
//        .focusedSceneValue(\.reloadCommand, .constant({
//            await fairAppInv.fetchApps(cache: .reloadIgnoringLocalAndRemoteCacheData)
//        }))
    }
}

#if os(macOS)
@available(macOS 12.0, iOS 15.0, *)
public struct AppTableDetailSplitView : View {
    let source: AppSource
    @Binding var selection: AppInfo.ID?
    @Binding var searchText: String
    @Binding var sidebarSelection: SidebarSelection?

    @ViewBuilder public var body: some View {
        VSplitView {
            AppsTableView(source: source, selection: $selection, sidebarSelection: sidebarSelection, searchText: $searchText)
                .frame(minHeight: 150)
            AppDetailView(sidebarSelection: $sidebarSelection)
                .layoutPriority(1.0)
        }
    }
}
#endif


extension SidebarSelection {
    /// The default font to use to render headlines for this catalog type
    func sourceFont(sized size: CGFloat) -> Font {
        switch self.source {
        case .homebrew:
            switch self.item {
            case .top, .updated, .installed, .recent:
                return Font.system(size: size, weight: .regular, design: .monospaced)
            case .category(_):
                return Font.system(size: size, weight: .regular, design: .default)
            }
        case .fairapps:
            switch self.item {
            case .top, .updated, .installed, .recent:
                return Font.system(size: size, weight: .regular, design: .rounded)
            case .category(_):
                return Font.system(size: size, weight: .regular, design: .default)
            }
        }
    }

    /// The view that will summarize the app source in the detail panel when no app is selected.
    func sourceOverviewView(showText: Bool) -> some View {
        var label = sourceInfo.tintedLabel(monochrome: false)
        let color = label.tint ?? .accentColor
        label.title = sourceInfo.fullTitle

        return VStack(spacing: 0) {
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

            if showText, let overview = sourceInfo.overviewText {
                ScrollView {
                    overview
                        .font(Font.title2)
                        .padding()
                        .padding()
                }
                    // .textSelection(.enabled) // unwraps and converts to a single line when selecting
            }
        }
    }

}

@available(macOS 12.0, iOS 15.0, *)
public struct AppDetailView : View {
    @Binding var sidebarSelection: SidebarSelection?
    @FocusedBinding(\.selection) private var selection: Selection??

    @ViewBuilder public var body: some View {
        VStack {
            switch selection {
            case .app(let app):
                CatalogItemView(info: app)
            case .some(.none), .none:
                emptySelectionView()
            }
        }
    }

    @ViewBuilder func emptySelectionView() -> some View {
        VStack {
            if sidebarSelection == nil {
                Text("Welcome to the App Fair", bundle: .module, comment: "header text for detail screen with no selection")
                    .font(Font.system(size: 40, weight: .regular, design: .rounded))
                    .padding()

                Text("The App Fair enables browsing, installing, and updating apps from community sources.", bundle: .module, comment: "header sub-text for detail screen with no selection")
                    .font(Font.title)
                    .padding()
            }

            if let sidebarSelection = sidebarSelection {
                let showOverviewText = { true }()
                sidebarSelection.sourceOverviewView(showText: showOverviewText)
                    .font(.body)
                Spacer()

                if !showOverviewText {
                    Text("No Selection", bundle: .module, comment: "placeholder text for detail panel indicating there is no app currently selected")
                        .font(Font.title)
                        .foregroundColor(Color.secondary)
                    Spacer()
                }
            } else {
                let sb1 = SidebarSelection(source: .homebrew, item: .top)
                let sb2 = SidebarSelection(source: .fairapps, item: .top)
                HStack(spacing: 0) {
                    sb1.sourceOverviewView(showText: true)
                    sb2.sourceOverviewView(showText: true)
                }
                HStack {
                    Spacer()
                    browseButton(sb1)
                    Spacer()
                    Spacer()
                    browseButton(sb2)
                    Spacer()
                }
                .padding()
                HStack {
                    Spacer()
                    sb1.sourceInfo.footerText
                        .font(.footnote)
                    Spacer()
                    Spacer()
                    sb2.sourceInfo.footerText
                        .font(.footnote)
                    Spacer()
                }
            }
        }
    }

    func browseButton(_ sidebarSelection: SidebarSelection) -> some View {
        Button {
            withAnimation {
                self.sidebarSelection = sidebarSelection
                self.selection = .some(.none)
            }
        } label: {
            Text("Browse \(sidebarSelection.sourceInfo.fullTitle)", bundle: .module, comment: "format pattern for the label of the button at the bottom of the category info screen")
        }
    }

}

/// A label that tints its image
@available(macOS 12.0, iOS 15.0, *)
public struct TintedLabel : View, Equatable {
    //@Environment(\.colorScheme) var colorScheme
    public var title: Text
    public let symbol: FairSymbol
    public var tint: Color? = nil
    public var mode: RenderingMode?

    public var body: some View {
        Label(title: { title }) {
            if let tint = tint {
                if let mode = mode {
                    symbol.image
                        .symbolRenderingMode(mode.symbolRenderingMode)
                        .foregroundStyle(tint)
                } else {
                    symbol.image
                        .fairTint(simple: true, color: tint)
                }
            } else {
                symbol.image
            }
        }
    }

    /// An equatable form of the struct based SymbolRenderingMode instances
    public enum RenderingMode : Equatable {
        case monochrome
        case hierarchical
        case multicolor
        case palette

        /// The instance of `SymbolRenderingMode` that matches this renderig mode.
        var symbolRenderingMode: SymbolRenderingMode {
            switch self {
            case .monochrome: return SymbolRenderingMode.monochrome
            case .hierarchical: return SymbolRenderingMode.hierarchical
            case .multicolor: return SymbolRenderingMode.multicolor
            case .palette: return SymbolRenderingMode.palette
            }
        }
    }
}

extension View {
    /// The custom tinting style for the App Fair
    @available(macOS 12.0, iOS 15.0, *)
    @ViewBuilder func fairTint(simple: Bool, color: Color) -> some View {
        if simple {
            foregroundStyle(.linearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom))
                .opacity(0.8)
        } else {
            foregroundStyle(
                .linearGradient(colors: [color.opacity(0.5), color], startPoint: .top, endPoint: .bottom),
                .linearGradient(colors: [color.opacity(0.5), .green], startPoint: .top, endPoint: .bottom),
                .linearGradient(colors: [color.opacity(0.5), .blue], startPoint: .top, endPoint: .bottom)
            )
//                .brightness(scheme == .light ? -0.3 : 0.3) // brighten the image a bit
        }
    }
}

extension SwiftUI.Color {
    /// Adjusrs the given components of the color
    @available(*, deprecated, message: "must handle color space conversion") // else: “-getHue:saturation:brightness:alpha: not valid for the NSColor Catalog color: #$customDynamic 2939580E-3E73-4C4B-B435-371CEF86B9D1; need to first convert colorspace.”
    func adjust(hue: Double = 0.0, saturation: Double = 0.0, brightness: Double = 0.0, alpha: Double = 0.0) -> Color {
        var h = CGFloat(0.0)
        var s = CGFloat(0.0)
        var b = CGFloat(0.0)
        var a = CGFloat(0.0)
        UXColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        h += hue
        s += saturation
        b += brightness
        a += alpha
        return Color(hue: h, saturation: s, brightness: b, opacity: a)

    }
}

/// A view that passes its enabled state to the given content closure
public struct EnabledView<V: View> : View {
    @Environment(\.isEnabled) var isEnabled
    public let content: (Bool) -> V

    public init(@ViewBuilder content: @escaping (Bool) -> V) {
        self.content = content
    }

    public var body: some View {
        content(isEnabled)
    }
}


@available(macOS 12.0, iOS 15.0, *)
struct SidebarView: View {
    @EnvironmentObject var fairManager: FairManager
    @Binding var selection: AppInfo.ID?
    @Binding var scrollToSelection: Bool
    @Binding var sidebarSelection: SidebarSelection?
    @Binding var displayMode: TriptychOrient
    @Binding var searchText: String

    private func sectionHeader(label: Label<Text, Image>, updating: Bool) -> some View {
        HStack {
            label.labelStyle(.titleOnly)
            if updating {
                Spacer()
                ProgressView()
                    .controlSize(.mini)
                    .padding(.trailing, 18)
            }
        }
    }

    var body: some View {
        List {
            ForEach(AppSource.allCases, id: \.self) { source in
                switch source {
                case .homebrew:
                    if fairManager.homeBrewInv.enableHomebrew {
                        Section {
                            homebrewItems()
                                .symbolVariant(.fill)
                        } header: {
                            sectionHeader(label: source.label, updating: fairManager.homeBrewInv.updateInProgress != 0)
                         }
                    }

                case .fairapps:
                    Section {
                        fairappsItems()
                            .symbolVariant(.fill)
                    } header: {
                        sectionHeader(label: source.label, updating: fairManager.fairAppInv.updateInProgress != 0)

                    }
                }
            }

            // categories section
            // TODO: merge homebrew and fairapps into single category
            if fairManager.homeBrewInv.enableHomebrew {
                Section {
                    ForEach(AppCategory.allCases) { cat in
                        if fairManager.homeBrewInv.apps(for: cat).isEmpty == false {
                            navitem(SidebarSelection(source: .homebrew, item: .category(cat)))
                        }
                    }
                    .symbolVariant(.fill)
                } header: {
                    sectionHeader(label: Label(title: { Text("Categories", bundle: .module, comment: "sidebar section header title for homebrew app categories") }, icon: { FairSymbol.list_dash.image }), updating: fairManager.homeBrewInv.updateInProgress != 0)
                }
            }
        }
        //.symbolVariant(.none)
        .symbolRenderingMode(.hierarchical)
        //.symbolVariant(.circle) // note that these can be stacked
        //.symbolVariant(.fill)
        //.symbolRenderingMode(.multicolor)
        .listStyle(.automatic)
        .toolbar(id: "SidebarView") {
            tool(source: .fairapps, .top)
            tool(source: .fairapps, .recent)
            tool(source: .fairapps, .updated)
            tool(source: .fairapps, .installed)

//            tool(.category(.entertain))
//            tool(.category(.research))
//            tool(.category(.create))
//            tool(.category(.game))
//            tool(.category(.live))
//            tool(.category(.work))
        }
    }

    func homebrewItems() -> some View {
        Group {
            let items = SidebarSelection.homebrewItems
            navitem(items.0.sel)
            navitem(items.1.sel)
            navitem(items.2.sel)
        }
    }

    func fairappsItems() -> some View {
        Group {
            let items = SidebarSelection.fairappsItems
            navitem(items.0.sel)
            navitem(items.1.sel)
            navitem(items.2.sel)
            navitem(items.3.sel)
        }
    }

    func navitem(_ selection: SidebarSelection) -> some View {
        let label = selection.sourceInfo.tintedLabel(monochrome: false)
        var navtitle = label.title
        if !searchText.isEmpty {
            navtitle = Text("\(navtitle): \(Text(searchText))", bundle: .module, comment: "formatting string separating navigation title from search text")
        }
        return NavigationLink(tag: selection, selection: $sidebarSelection, destination: {
            navigationDestinationView(item: selection)
                .navigationTitle(navtitle)
        }, label: {
            label.badge(badgeCount(for: selection))
        })
    }

    func badgeCount(for item: SidebarSelection) -> Text? {
        switch item.source {
        case .fairapps:
            return fairManager.fairAppInv.badgeCount(for: item.item)
        case .homebrew:
            return fairManager.homeBrewInv.badgeCount(for: item.item)
        }
    }

    @ViewBuilder func navigationDestinationView(item: SidebarSelection) -> some View {
        switch displayMode {
        case .list:
            AppsListView(source: item.source, sidebarSelection: sidebarSelection, selection: $selection, scrollToSelection: $scrollToSelection, searchTextSource: $searchText)
        #if os(macOS)
        case .table:
            AppTableDetailSplitView(source: item.source, selection: $selection, searchText: $searchText, sidebarSelection: $sidebarSelection)
        #endif
        }
    }

    func tool(source: AppSource, _ item: SidebarItem) -> some CustomizableToolbarContent {
        ToolbarItem(id: item.id, placement: .automatic, showsByDefault: false) {
            Button(action: {
                selectItem(item)
            }, label: {
//                item.label(for: source, monochrome: false)
                    //.symbolVariant(.fill)
//                    .symbolRenderingMode(.multicolor)
            })
        }
    }

    func selectItem(_ item: SidebarItem) {
        dbg("selected:", item.id)
    }
}

extension SidebarSelection {
    static let homebrewItems = (
        (sel: SidebarSelection(source: .homebrew, item: .top), key: "1" as KeyEquivalent),
        (sel: SidebarSelection(source: .homebrew, item: .installed), key: "2" as KeyEquivalent),
        (sel: SidebarSelection(source: .homebrew, item: .updated), key: "3" as KeyEquivalent)
    )

    static let fairappsItems = (
        (sel: SidebarSelection(source: .fairapps, item: .top), key: KeyEquivalent("4")),
        (sel: SidebarSelection(source: .fairapps, item: .recent), key: KeyEquivalent("5")),
        (sel: SidebarSelection(source: .fairapps, item: .installed), key: KeyEquivalent("6")),
        (sel: SidebarSelection(source: .fairapps, item: .updated), key: KeyEquivalent("7"))
    )
}

@available(macOS 12.0, iOS 15.0, *)
extension FocusedValues {
    private struct FocusedSelection: FocusedValueKey {
        typealias Value = Binding<Selection?>
    }

    var selection: Binding<Selection?>? {
        get { self[FocusedSelection.self] }
        set { self[FocusedSelection.self] = newValue }
    }

    private struct FocusedSidebarSelection: FocusedValueKey {
        typealias Value = Binding<SidebarSelection?>
    }

    var sidebarSelection: Binding<SidebarSelection?>? {
        get { self[FocusedSidebarSelection.self] }
        set { self[FocusedSidebarSelection.self] = newValue }
    }

    private struct FocusedReloadCommand: FocusedValueKey {
        typealias Value = Binding<() async -> ()>
    }

    var reloadCommand: Binding<() async -> ()>? {
        get { self[FocusedReloadCommand.self] }
        set { self[FocusedReloadCommand.self] = newValue }
    }
}


#if os(macOS)
extension NSUserScriptTask {
    /// Performs the given shell command and returns the output via an `NSAppleScript` operation
    /// - Parameters:
    ///   - command: the command to execute
    ///   - async: whether to fork async using `NSUserAppleScriptTask` as opposed to synchronously with `NSAppleScript`
    ///   - admin: whether to execute the script `with administrator privileges`
    /// - Returns: the string contents of the response
    public static func fork(command: String, admin: Bool = false) async throws -> String? {
        let withAdmin = admin ? " with administrator privileges" : ""

        let cmd = "do shell script \"\(command)\"" + withAdmin

        let scriptURL = URL.tmpdir
            .appendingPathComponent("scriptcmd-" + UUID().uuidString)
            .appendingPathExtension("scpt") // needed or else error that the script: “couldn’t be opened because it isn’t in the correct format”
        try cmd.write(to: scriptURL, atomically: true, encoding: .utf8)
        dbg("running NSUserAppleScriptTask in:", scriptURL.path, "command:", cmd)
        let task = try NSUserAppleScriptTask(url: scriptURL)
        let output = try await task.execute(withAppleEvent: nil)
        dbg("successfully executed script:", command)
        return output.stringValue
    }
}
#endif

extension Text {
    /// Converts this `Text` into a label with a yellow exclamation warning.
    func warningLabel() -> some View {
        self.label(image: FairSymbol.exclamationmark_triangle_fill.symbolRenderingMode(.multicolor))
    }
}

// MARK: Parochial (package-local) Utilities

/// Work-in-Progress marker
@available(*, deprecated, message: "work in progress")
internal func wip<T>(_ value: T) -> T { value }

/// Intercept `LocalizedStringKey` constructor and forward it to ``SwiftUI.Text/init(_:bundle)``
/// Otherwise it will default to the main bundle's strings, which is always empty.
@available(*, deprecated, message: "use bundle: .module, comment: arguments literally")
@usableFromInline internal func Text(_ string: LocalizedStringKey, comment: StaticString? = nil) -> SwiftUI.Text {
    SwiftUI.Text(string, bundle: .module, comment: comment)
}
