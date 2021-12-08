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
import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
struct CatalogItemView: View {
    let info: AppInfo

    @EnvironmentObject var appManager: AppManager
    @Environment(\.openURL) var openURLAction
    @Environment(\.colorScheme) var colorScheme

    @State var currentActivity: Activity? = nil
    @StateObject var progress = ObservableProgress()
    @State var confirmations: [Activity: Bool] = [:]

    #if os(macOS) // horizontalSizeClass unavailable on macOS
    func horizontalCompact() -> Bool { false }
    #else
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    func horizontalCompact() -> Bool { horizontalSizeClass == .compact }
    #endif


    var body: some View {
        // let _ = debuggingViewChanges() // e.g.: “CatalogItemView: @self, @identity, _appManager, _openURLAction, _colorScheme, _currentActivity, _progress, _confirmations changed.”
        catalogGrid()
        //catalogStack()
    }

    func headerView() -> some View {
        pinnedHeaderView()
            .padding(.top)
            //.background(item.tintColor())
            .background(Material.ultraThinMaterial)
    }

    func catalogStack() -> some View {
        VStack {
            headerView()
            catalogSummaryCards()
            Divider()
            catalogOverview()
        }
    }

    func catalogGrid() -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(pinnedViews: [.sectionHeaders]) {
                Section {
                    catalogSummaryCards()
                    Divider()
                    catalogOverview()
                } header: {
                    headerView()
                }
            }
        }
    }

    func pinnedHeaderView() -> some View {
        VStack {
            catalogHeader()
            Divider()
            catalogActionButtons()
            Divider()
        }
    }

    func starsCard() -> some View {
        summarySegment {
            card(
                Text("Stars"),
                numberView(number: .decimal, \.starCount),
                histogramView(\.starCount)
            )
        }
    }

    func downloadsCard() -> some View {
        summarySegment {
            card(
                Text("Downloads"),
                numberView(number: .decimal, \.downloadCount),
                histogramView(\.downloadCount)
            )
        }
    }

    func sizeCard() -> some View {
        summarySegment {
            card(
                Text("Size"),
                numberView(size: .file, \.fileSize),
                histogramView(\.fileSize)
            )
        }
    }

    func coreSizeCard() -> some View {
        summarySegment {
            card(
                Text("Core Size"),
                numberView(size: .file, \.coreSize),
                histogramView(\.coreSize)
            )
        }
    }

    func watchersCard() -> some View {
        summarySegment {
            card(
                Text("Watchers"),
                numberView(number: .decimal, \.watcherCount),
                histogramView(\.watcherCount)
            )
        }
    }

    func issuesCard() -> some View {
        summarySegment {
            card(
                Text("Issues"),
                numberView(number: .decimal, \.issueCount),
                histogramView(\.issueCount)
            )
        }
    }

    func releaseDateCard() -> some View {
        summarySegment {
            card(
                Text("Updated"),
                Text(info.release.versionDate ?? Date(), format: .relative(presentation: .numeric, unitsStyle: .abbreviated)),
                histogramView(\.issueCount)
            )
        }
    }

    func catalogSummaryCards() -> some View {
        HStack(alignment: .center) {
            starsCard()
            Divider()
            releaseDateCard()
            Divider()
            downloadsCard()
            Divider()
            sizeCard()
            Divider()
            issuesCard()
            //watchersCard()
        }
        .frame(height: 54)
    }

    func linkTextField(_ title: Text, icon: String, url: URL, linkText: String? = nil) -> some View {
        TextField(text: .constant(linkText ?? url.absoluteString)) {
            title
                .label(symbol: icon)
                .labelStyle(.titleAndIconFlipped)
                .link(to: url)
                .font(Font.body)
        }
    }

    func detailsView() -> some View {
        ScrollView {
            Form {
                linkTextField(Text("Discussions"), icon: "text.bubble", url: info.release.discussionsURL)
                    .help(Text("Opens link to the discussions page for this app at: \(info.release.discussionsURL.absoluteString)"))
                linkTextField(Text("Issues"), icon: "checklist", url: info.release.issuesURL)
                    .help(Text("Opens link to the issues page for this app at: \(info.release.issuesURL.absoluteString)"))
                linkTextField(Text("Source"), icon: "chevron.left.forwardslash.chevron.right", url: info.release.sourceURL)
                    .help(Text("Opens link to source code repository for this app at: \(info.release.sourceURL.absoluteString)"))
                linkTextField(Text("Fairseal"), icon: "rosette", url: info.release.fairsealURL, linkText: String(info.release.sha256 ?? ""))
                    .help(Text("Lookup fairseal at: \(info.release.fairsealURL)"))
                linkTextField(Text("Developer"), icon: "person", url: info.release.developerURL, linkText: item.developerName)
                    .help(Text("Searches for this developer at: \(info.release.developerURL)"))
            }
            .symbolRenderingMode(SymbolRenderingMode.multicolor)
            .font(Font.body.monospaced())
            .textFieldStyle(.plain)
            .truncationMode(.middle)
        }
    }

    func groupBox<V: View, L: View>(title: Text, trailing: L, @ViewBuilder content: () -> V) -> some View {
        GroupBox(content: {
            content()
        }, label: {
            HStack {
                title
                    .font(.headline)
                Spacer()
                trailing
                    .font(.subheadline)
            }
                .lineLimit(1)
        })
            .groupBoxStyle(.automatic)
            .padding()
    }

    func catalogOverview() -> some View {
        LazyVStack {
            Section {
                catalogColumns()
            } footer: {
                groupBox(title: Text("Preview"), trailing: EmptyView()) {
                    ScrollView(.horizontal) {
                        previewView()
                    }
                    .frame(height: 300)
                }
            }
        }
    }

    func catalogColumns() -> some View {
        HStack {
            VStack {
                groupBox(title: Text("Description"), trailing: EmptyView()) {
                    ScrollView {
                        descriptionSummary()
                            .font(.body)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 150)

                groupBox(title: Text("Version: ") + Text(verbatim: info.releasedVersion?.versionStringExtended ?? ""), trailing: Text(info.release.versionDate ?? .distantPast, format: .dateTime)) {
                    ScrollView {
                        versionSummary()
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 150)
            }

            VStack(alignment: .leading) {
                groupBox(title: Text("Details"), trailing: EmptyView()) {
                    detailsView()
                }
                .frame(height: 150)

                groupBox(title: Text("Permissions: ") + item.riskLevel.textLabel().fontWeight(.regular), trailing: item.riskLevel.riskLabel()
                            .help(item.riskLevel.riskSummaryText())
                            .labelStyle(IconOnlyLabelStyle())
                            .padding(.trailing)) {
                    permissionsList()
                }
                .frame(height: 150)
            }
        }
    }

    func versionSummary() -> some View {
        Text(atx: self.info.release.versionDescription ?? "")
            .font(.body)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func descriptionSummary() -> some View {
        if let readme = self.appManager.readme(for: self.info.release) {
            Text(readme)
        } else {
            Text("Loading README…")
        }
    }

    func permissionListItem(permission: AppPermission) -> some View {
        let entitlement = permission.type

        var title = entitlement.localizedInfo.title
        if !permission.usageDescription.isEmpty {
            title = title + Text(" – ") + Text(permission.usageDescription).foregroundColor(.secondary).italic()
        }

        return title.label(symbol: entitlement.localizedInfo.symbol)
            .listItemTint(ListItemTint.monochrome)
            .symbolRenderingMode(SymbolRenderingMode.monochrome)
            .lineLimit(1)
            .truncationMode(.tail)
            //.textSelection(.enabled)
            .help(entitlement.localizedInfo.info + Text(": ") + Text(permission.usageDescription))
    }

    /// The entitlements that will appear in the list.
    /// These filter out entitlements that are pre-requisites (e.g., sandboxing) as well as harmless entitlements (e.g., JIT).
    var listedPermissions: [AppPermission] {
        item.orderedPermissions(filterCategories: [.harmless, .prerequisite])
    }

    func permissionsList() -> some View {
        List {
            ForEach(listedPermissions, id: \.type, content: permissionListItem)
        }
        .conditionally {
#if os(macOS)
            $0.listStyle(.bordered(alternatesRowBackgrounds: true))
#endif
        }
    }

    func previewView() -> some View {
        LazyHStack {
            ForEach(item.screenshotURLs ?? [], id: \.self) { url in
                URLImage(sync: false, url: url, resizable: .fit, showProgress: false)
            }
        }
    }
    
    func catalogAuthorRow() -> some View {
        Group {
            if info.release.developerName.isEmpty {
                Text("Unknown")
            } else {
                Text(info.release.developerName)
            }
        }
    }

    func numberView(number numberStyle: NumberFormatter.Style? = nil, size sizeStyle: ByteCountFormatStyle.Style? = nil, _ path: KeyPath<AppCatalogItem, Int?>) -> some View {
        let value = info.release[keyPath: path]
        if let value = value {
            if let sizeStyle = sizeStyle {
                return Text(Int64(value), format: .byteCount(style: sizeStyle))
            } else {
                return Text(value, format: .number)
            }
        } else {
            return SwiftUI.Text(FairSymbol.questionmark_square.image)
        }
    }

    /// Show a histogram of where the given value lies in the context of other apps in the grouping
    func histogramView(_ path: KeyPath<AppCatalogItem, Int?>) -> some View {
        FairSymbol.chart_bar_xaxis.image
            .resizable()
    }

    func summarySegment<V: View>(@ViewBuilder content: () -> V) -> some View {
        content()
            .lineLimit(1)
            .truncationMode(.middle)
        //.textSelection(.enabled)
            .hcenter()
    }

    func catalogHeader() -> some View {
        HStack(alignment: .center) {
            iconView()
                .frame(width: 80, height: 80)
                .padding(.leading, 40)

            VStack(alignment: .center) {
                Text(item.name)
                    .font(Font.largeTitle)
                    .truncationMode(.middle)
                Text(item.subtitle ?? item.localizedDescription)
                .font(Font.title2)
                    .truncationMode(.tail)
                catalogAuthorRow()
                    .font(Font.title3)
                    .truncationMode(.head)
            }
            .textSelection(.enabled)
            .lineLimit(1)
            .allowsTightening(true)
            .hcenter()

            categorySymbol()
                .frame(width: 80, height: 80)
                .padding(.trailing, 40)
        }
    }

    func catalogActionButtons() -> some View {
        let isCatalogApp = info.release.bundleIdentifier == "app.App-Fair"

        return HStack {
            installButton()
                .disabled(isCatalogApp)
                .hcenter()
            updateButton()
                .hcenter()
            launchButton()
                .disabled(isCatalogApp)
                .hcenter()
            revealButton()
                .hcenter()
            trashButton()
                .disabled(isCatalogApp)
                .hcenter()
        }
        .symbolRenderingMode(.monochrome)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.regular)
    }

    func installButton() -> some View {
        button(activity: .install, role: nil, needsConfirm: true)
            .disabled(appInstalled)
            .confirmationDialog(Text("Install \(info.release.name)"), isPresented: confirmationBinding(.install), titleVisibility: .visible, actions: {
                Text("Download & Install \(info.release.name)").button {
                    runTask(activity: .install, confirm: true)
                }
                Text("Visit Community Forum").button {
                    openURLAction(info.release.discussionsURL)
                }
                // TODO: only show if there are any open issues
                // Text("Visit App Issues Page").button {
                //    openURLAction(info.release.issuesURL)
                // }
                .help(Text("Opens your web browsers and visits the developer site at \(info.release.baseURL.absoluteString)")) // sadly, tooltips on confirmationDialog buttons don't seem to work
            }, message: installMessage)
            .tint(.green)
    }

    func updateButton() -> some View {
        button(activity: .update)
            //.disabled(wip(false))
            .disabled((!appInstalled || !info.appUpdated))
            .accentColor(.orange)
    }

    func launchButton() -> some View {
        button(activity: .launch)
            .disabled(!appInstalled)
            .accentColor(.green)
    }

    func revealButton() -> some View {
        button(activity: .reveal)
            .disabled(!appInstalled)
            .accentColor(.teal)
    }

    func trashButton() -> some View {
        button(activity: .trash, role: ButtonRole.destructive, needsConfirm: true)
        //.keyboardShortcut(.delete)
            .disabled(!appInstalled)
            //.accentColor(.red) // coflicts with the red background of the button
            .confirmationDialog(Text("Really delete this app?"), isPresented: confirmationBinding(.trash), titleVisibility: .visible, actions: {
                Text("Delete").button {
                    runTask(activity: .trash, confirm: true)
                }
            }, message: {
                Text("This will remove the application “\(info.release.name)” from your applications folder and place it in the Trash.")
            })
    }

    func installMessage() -> some View {
        Text(atx: """
            This will download and install the application “\(info.release.name)” from the developer “\(info.release.developerName)” at:

            \(info.release.sourceURL.absoluteString)

            This app has not undergone any formal review, so you will be installing and running it at your own risk.

            Before installing, you should first review the Discussions, Issues, and Documentation pages to learn more about the app.
            """)
    }

    var item: AppCatalogItem {
        info.release
    }

    var doingStuff: Bool {
        currentActivity != nil
    }

    enum Activity : CaseIterable, Equatable {
        case install
        case update
        case trash
        case reveal
        case launch

        var info: (title: Text, systemSymbol: String, tintColor: Color?, toolTip: Text) {
            switch self {
            case .install:
                return (Text("Install"), "square.and.arrow.down.fill", Color.blue, Text("Download and install the app."))
            case .update:
                return (Text("Update"), "square.and.arrow.down.on.square", Color.orange, Text("Update to the latest version of the app.")) // TODO: when pre-release, change to "Update to the latest pre-release version of the app"
            case .trash:
                return (Text("Delete"), "trash", Color.red, Text("Delete the app from your computer."))
            case .reveal:
                return (Text("Reveal"), "doc.text.fill.viewfinder", Color.indigo, Text("Displays the app install location in the Finder."))
            case .launch:
                return (Text("Launch"), "checkmark.seal.fill", Color.green, Text("Launches the app."))
            }
        }
    }

    /// The plist for the given installed app
    var appPropertyList: Result<Plist, Error>? {
        let installPath = AppManager.appInstallPath(for: item)
        let result = appManager.installedApps[installPath]
        //dbg("install for item:", item, "install path:", AppManager.appInstallPath(for: item).path, "plist:", result != nil, "installedApps:", appManager.installedApps.keys.map(\.path))

        if result == nil {
            //dbg("install path not found:", installPath, "in keys:", appManager.installedApps.keys)
        }
        return result
    }

    /// Returns the URLs that are registered with the system `NSWorkspace` for handling the app's bundle
    @available(*, deprecated, message: "unsuitable for use with bindings because NSWorkspace.shared.urlsForApplications sometimes has a delay")
    var appInstallURLs: [URL] {
        guard let plist = appPropertyList?.successValue else {
            return []
        }
        guard let bundleID = plist.bundleID else {
            return []
        }

#if os(macOS)
        let apps = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        return apps
#else
        return [] // TODO: iOS install check
#endif
    }

    /// Whether the app is successfully installed
    var appInstalled: Bool {
        appPropertyList?.successValue?.bundleID == info.id
        //!appInstallURLs.isEmpty // this is more accurate, but NSWorkspace.shared.urlsForApplications has a delay in returning the correct information sometimes
    }

    func confirmationBinding(_ activity: Activity) -> Binding<Bool> {
        Binding {
            confirmations[activity] ?? false
        } set: { newValue in
            confirmations[activity] = newValue
        }
    }

    func runTask(activity: Activity, confirm confirmed: Bool) {
        if !confirmed {
            confirmations[activity] = true
        } else {
            confirmations[activity] = false // we have confirmed
            currentActivity = activity
            Task(priority: .userInitiated) {
                await performAction(activity: activity)
                currentActivity = nil
            }
        }
    }

    func button(activity: Activity, role: ButtonRole? = .none, needsConfirm: Bool = false) -> some View {
        Button(role: role, action: {
            runTask(activity: activity, confirm: !needsConfirm)
        }, label: {
            Label(title: {
                HStack(spacing: 5) {
                    activity.info.title
                        .font(Font.headline.smallCaps())
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    Group {
                        if currentActivity == activity {
                            ProgressView()
                                .progressViewStyle(.circular) // spinner
                                .controlSize(.small) // needs to be small to fit in the button
                                .opacity(currentActivity == activity ? 1 : 0)
                        } else {
                            FairSymbol.circle
                        }
                    }
                    .frame(width: 20, height: 15)
                }
            }, icon: {
                Image(systemName: activity.info.systemSymbol)
            })
        })
            .buttonStyle(ActionButtonStyle(progress: .constant(currentActivity == activity ? progress.progress.fractionCompleted : 1.0), primary: true, highlighted: false))
            .accentColor(activity.info.tintColor)
            .disabled(doingStuff)
            .help(activity.info.toolTip)
    }

    func performAction(activity: Activity) async {
        switch activity {
        case .install: await installButtonTapped()
        case .update: await updateButtonTapped()
        case .trash: await deleteButtonTapped()
        case .reveal: await revealButtonTapped()
        case .launch: await launchButtonTapped()
        }
    }

    func iconView() -> some View {
        item.iconImage()
    }

    func categorySymbol() -> some View {
        let category = (item.appCategories.first?.groupings.first ?? .create)

        return Image(systemName: category.symbolName.description)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fairTint(simple: false, color: item.itemTintColor(), scheme: colorScheme)
            .symbolVariant(.fill)
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(.secondary)
    }

    func card<V1: View, V2: View, V3: View>(_ s1: V1, _ s2: V2, _ s3: V3) -> some View {
        VStack(alignment: .center) {
            s1
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .bold, design: .default))
            s2
                .font(.system(size: 20, weight: .heavy, design: .rounded))
            s3
                .padding(.horizontal)
        }
        .foregroundColor(.secondary)
    }

    func installButtonTapped() async {
        dbg("installButtonTapped")
        do {
            progress.progress = Progress(totalUnitCount: AppManager.progressUnitCount)
            try await appManager.install(item: item, progress: progress.progress, update: false)
        } catch {
            appManager.reportError(error)
        }
    }

    func launchButtonTapped() async {
        dbg("launchButtonTapped")
        await appManager.launch(item: item)
    }

    func updateButtonTapped() async {
        dbg("updateButtonTapped")
        do {
            progress.progress = Progress(totalUnitCount: AppManager.progressUnitCount)
            try await appManager.install(item: item, progress: progress.progress, update: true)
        } catch {
            appManager.reportError(error)
        }
    }

    func revealButtonTapped() async {
        dbg("revealButtonTapped")
        await appManager.reveal(item: item)
    }

    func deleteButtonTapped() async {
        dbg("deleteButtonTapped")
        await appManager.trash(item: item)
    }
}


extension AppCatalogItem {
    @ViewBuilder func iconImage() -> some View {
        if let iconURL = self.iconURL {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable(resizingMode: .stretch)
                        .aspectRatio(contentMode: .fit)
                case .failure(let error):
                    fallbackIcon()
                        .brightness(0.4)
                        .help(error.localizedDescription)
                case .empty:
                    fallbackIcon()
                        .grayscale(1.0)
                @unknown default:
                    fallbackIcon()
                        .grayscale(0.8)
                }
            }
            .transition(.slide)
        } else {
            fallbackIcon()
                .grayscale(1.0)
        }
    }

    @ViewBuilder func iconImageOLD() -> some View {
        if let iconURL = self.iconURL {
            URLImage(url: iconURL, resizable: .fit)
        } else {
            fallbackIcon()
        }
    }

    @ViewBuilder func fallbackIcon() -> some View {
        // fall-back to the generated image for the app, but with no title or sub-title
        FairIconView("", subtitle: "", iconColor: itemTintColor())
    }

    /// The specified tint color, falling back on the default tint for the app name
    func itemTintColor() -> Color {
         self.tintColor() ?? FairIconView.iconColor(name: self.appNameHyphenated)
    }


    func tintColor() -> Color? {
        func hexColor(hex: Int, opacity: Double = 1.0) -> Color {
            let red = Double((hex & 0xff0000) >> 16) / 255.0
            let green = Double((hex & 0xff00) >> 8) / 255.0
            let blue = Double((hex & 0xff) >> 0) / 255.0
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
        }

        guard var tint = self.tintColor else {
            return nil
        }

        if tint.hasPrefix("#") {
            tint.removeFirst()
        }

        if let intValue = Int(tint, radix: 16) {
            return hexColor(hex: intValue)
        }

        return nil
    }
}

extension LabelStyle where Self == TitleAndIconFlippedLabelStyle {
    /// The same as `titleAndIcon` with the icon at the end
    public static var titleAndIconFlipped: TitleAndIconFlippedLabelStyle {
        TitleAndIconFlippedLabelStyle()
    }
}

public struct TitleAndIconFlippedLabelStyle : LabelStyle {
    public func makeBody(configuration: TitleAndIconLabelStyle.Configuration) -> some View {
        HStack(alignment: .firstTextBaseline) {
            configuration.title
            configuration.icon
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct CatalogItemView_Previews: PreviewProvider {
    static var previews: some View {
        CatalogItemView(info: AppInfo(release: AppCatalogItem.sample))
            .environmentObject(AppManager.default)
            .frame(width: 700)
            .frame(height: 800)
        //.environment(\.locale, Locale(identifier: "fr"))
    }
}
