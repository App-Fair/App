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
import WebKit

@available(macOS 12.0, iOS 15.0, *)
struct CatalogItemView: View {
    let info: AppInfo

    @EnvironmentObject var fairManager: FairManager
    @Environment(\.openURL) var openURLAction
    @Environment(\.colorScheme) var colorScheme

    @State private var caskURLFileSize: Int64? = nil
    @State private var caskURLModifiedDate: Date? = nil

    @State private var previewScreenshot: URL? = nil

    private var currentOperation: CatalogOperation? {
        get {
            fairManager.operations[info.id]
        }

        nonmutating set {
            fairManager.operations[info.id] = newValue
        }
    }

    private var currentActivity: CatalogActivity? {
        get {
            currentOperation?.activity
        }

        nonmutating set {
            currentOperation = newValue.flatMap({ CatalogOperation(activity: $0) })
        }
    }

    @StateObject var progress = ObservableProgress()
    @State var confirmations: [CatalogActivity: Bool] = [:]

    @Namespace private var namespace

#if os(macOS) // horizontalSizeClass unavailable on macOS
    func horizontalCompact() -> Bool { false }
#else
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    func horizontalCompact() -> Bool { horizontalSizeClass == .compact }
#endif

    var unavailableIcon: some View {
        // FairSymbol.exclamationmark_triangle_fill.image.symbolRenderingMode(.multicolor)
        FairSymbol.puzzlepiece_fill.image.symbolRenderingMode(.hierarchical)
    }


    var body: some View {
        ZStack {
            catalogStack()
            screenshotPreviewOverlay()
        }
        .onAppear {
            // transfer the progress so we can watch the operation
            progress.progress = currentOperation?.progress ?? progress.progress
        }
    }

    func catalogStack() -> some View {
        VStack {
            VStack(spacing: 0) {
                catalogHeader()
                    .padding(.vertical)
                    .background(Material.ultraThinMaterial)
                Divider()
            }
            catalogActionButtons()
                .frame(height: buttonHeight + 12)
            Divider()
            catalogSummaryCards()
                .frame(height: 40)
            Divider()
            catalogOverview()
                .padding()
        }
    }

    func starsCard() -> some View {
        summarySegment {
            card(
                Text("Stars", bundle: .module, comment: "app catalog entry header box title"),
                numberView(number: .decimal, \.starCount),
                histogramView(\.starCount)
            )
        }
    }

    func downloadsCard() -> some View {
        summarySegment {
            card(
                Text("Downloads", bundle: .module, comment: "app catalog entry header box title"),
                numberView(number: .decimal, \.downloadCount)
                    .help(info.isCask ? Text("The number of downloads of this cask in the past 90 days", bundle: .module, comment: "app catalog entry header box title tooltip text") : Text("The total number of downloads for this release", bundle: .module, comment: "app catalog entry header box title tooltip text")),
                histogramView(\.downloadCount)
            )
        }
    }

    func sizeCard() -> some View {
        summarySegment {
            card(
                Text("Size", bundle: .module, comment: "app catalog entry header box title"),
                downloadSizeView(),
                histogramView(\.fileSize)
            )
        }
    }

    func downloadSizeView() -> some View {
        Group {
            if info.isCask {
                if let caskURLFileSize = caskURLFileSize, caskURLFileSize > 0 { // sometimes -1 when it isn't found
                    numberView(size: .file, value: Int(caskURLFileSize))
                } else {
                    // show the card view with an empty file size
                    Text("Unknown", bundle: .module, comment: "app catalog entry content box placeholder text for a download size that isn't known")
                        .redacted(reason: .placeholder)
                        .task {
                            await fetchDownloadURLStats()
                        }
                }
            } else {
                numberView(size: .file, \.fileSize)
            }
        }
        .transition(.opacity)
    }

    func coreSizeCard() -> some View {
        summarySegment {
            card(
                Text("Core Size", bundle: .module, comment: "app catalog entry header box title for the core size of the app"),
                numberView(size: .file, \.coreSize),
                histogramView(\.coreSize)
            )
        }
    }

    func watchersCard() -> some View {
        summarySegment {
            card(
                Text("Watchers", bundle: .module, comment: "app catalog entry header box title for the number of watchers for the app"),
                numberView(number: .decimal, \.watcherCount),
                histogramView(\.watcherCount)
            )
        }
    }

    func issuesCard() -> some View {
        summarySegment {
            card(
                Text("Issues", bundle: .module, comment: "app catalog entry header box title for the number of issues for the app"),
                numberView(number: .decimal, \.issueCount),
                histogramView(\.issueCount)
            )
        }
    }

    func releaseDateCard() -> some View {
        summarySegment {
            card(
                Text("Updated", bundle: .module, comment: "app catalog entry header box title for the date the app was last updated"),
                releaseDateView(),
                histogramView(\.issueCount)
            )
        }
    }

    func releaseDateView() -> some View {
        Group {
            if let date = metadata.versionDate ?? self.caskURLModifiedDate {
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .wide))
                    .transition(.opacity)
            } else {
                Text("Unknown", bundle: .module, comment: "app catalog entry header box content for an unknown update date")
                    .redacted(reason: .placeholder)
            }
        }
        .transition(.opacity)
    }

    private func fetchDownloadURLStats() async {
        if fairManager.homeBrewInv.manageCaskDownloads == true {
            do {
                dbg("checking URL HEAD:", metadata.downloadURL.absoluteString)

                let head = try await URLSession.shared.fetchHEAD(url: metadata.downloadURL, cachePolicy: .returnCacheDataElseLoad)
                
                // in theory, we could also try to pre-flight out expected SHA-256 checksum by checking for a header like "Digest: sha-256=A48E9qOokqqrvats8nOJRJN3OWDUoyWxBf7kbu9DBPE=", but in practice no server ever seems to send it
                withAnimation {
                    self.caskURLFileSize = head?.expectedContentLength
                    self.caskURLModifiedDate = head?.lastModifiedDate
                }
                dbg("URL HEAD:", metadata.downloadURL.absoluteString, self.caskURLFileSize?.localizedByteCount(), self.caskURLFileSize, (head as? HTTPURLResponse)?.allHeaderFields as? [String: String])

            } catch {
                // errors are not unexpected when the user leaves this view:
                // NSURLErrorDomain Code=-999 "cancelled"
                dbg("error checking URL size:", metadata.downloadURL.absoluteString, "error:", error)
            }
        }
    }

    func catalogSummaryCards() -> some View {
        HStack(alignment: .center) {
            starsCard()
                .opacity(info.isCask ? 0.0 : 1.0)
            Divider()
            releaseDateCard()
            Divider()
            downloadsCard()
            Divider()
            sizeCard()
            Divider()
            issuesCard()
                .opacity(info.isCask ? 0.0 : 1.0)
        }
    }

    /// The accessory on the trailing section of a `groupBox`
    @ViewBuilder func progressAccessory(_ fetching: Int) -> some View {
        ProgressView()
            .opacity(fetching > 0 ? 1.0 : 0.0).controlSize(.mini)
            .padding(.trailing, 8)
            .animation(Animation.easeInOut, value: fetching)
    }


    func linkTextField(_ title: Text, icon: FairSymbol, url: URL?, linkText: String? = nil) -> some View {
        // the text winds up being un-aligned vertically when rendered like this
        //        TextField(text: .constant(linkText ?? url?.absoluteString ?? "")) {
        //            title
        //                .label(symbol: icon)
        //                .labelStyle(.titleAndIconFlipped)
        //                .link(to: url)
        //                //.font(Font.body)
        //        }
        //        .textFieldStyle(.plain)

        HStack {
            title
                .label(image: icon)
                .lineLimit(1)
                .labelStyle(.titleAndIconFlipped)
                .link(to: url)
                .frame(width: 110, alignment: .trailing)

            Text(linkText ?? url?.absoluteString ?? "")
                .lineLimit(1)
                .textSelection(.enabled)
                .font(Font.body.monospacedDigit())
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        //.alignmentGuide(.leading, computeValue: { d in (d.width - 60) })

        //        HStack {
        //
        //            TextField(text: .constant("")) {
        //                title
        //                    .label(symbol: icon)
        //                    .labelStyle(.titleAndIconFlipped)
        //                    .link(to: url)
        //                    .font(Font.body)
        //            }
        //            Text(linkText ?? url.absoluteString)
        //                .font(Font.body.monospaced())
        //                .truncationMode(.middle)
        //                .textSelection(.enabled)
        //        }

        //        TextField(text: .constant(linkText ?? url.absoluteString)) {
        //            title
        //                .label(symbol: icon)
        //                .labelStyle(.titleAndIconFlipped)
        //                .link(to: url)
        //                .font(Font.body)
        //        }


    }

    func detailsListView() -> some View {
        ScrollView {
            Form {
                if let cask = info.cask {
                    if let page = cask.homepage, let homepage = URL(string: page) {
                        linkTextField(Text("Homepage", bundle: .module, comment: "app catalog entry info link title"), icon: .house, url: homepage)
                            .help(Text("Opens link to the home page for this app at: \(homepage.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }

                    if let downloadURL = cask.url, let downloadURL = URL(string: downloadURL) {
                        linkTextField(Text("Download", bundle: .module, comment: "app catalog entry info link title"), icon: .arrow_down_circle, url: downloadURL)
                            .help(Text("Opens link to the direct download for this app at: \(downloadURL.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }

                    if let appcast = cask.appcast, let appcast = URL(string: appcast) {
                        linkTextField(Text("Appcast", bundle: .module, comment: "app catalog entry info link title"), icon: .dot_radiowaves_up_forward, url: appcast)
                            .help(Text("Opens link to the appcast for this app at: \(appcast.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }

                    if let tapToken = cask.tapToken, let tapURL = cask.tapURL {
                        linkTextField(Text("Cask Token", bundle: .module, comment: "app catalog entry info link title"), icon: .esim, url: tapURL, linkText: tapToken)
                            .help(Text("The page for the Homebrew Cask token", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }

                    if let sha256 = cask.checksum ?? "None" {
                        linkTextField(Text("Checksum", bundle: .module, comment: "app catalog entry info link title"), icon: cask.checksum == nil ? .exclamationmark_triangle_fill : .rosette, url: cask.checksum == nil ? nil : URL(string: "https://github.com/Homebrew/formulae.brew.sh/search?q=" + sha256), linkText: sha256)
                            .help(cask.checksum == nil ? Text("The SHA-256 checksum for the app is missing, which means that the integrity cannot be varified when it is downloaded.", bundle: .module, comment: "app catalog entry info link tooltip") : Text("The SHA-256 checksum for the app download", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }

//                    linkTextField(Text("Auto-Updates", bundle: .module, comment: "app catalog entry info auto-update tooltip"), icon: .sparkle, url: nil, linkText: cask.auto_updates == nil ? "Unknown" : cask.auto_updates == true ? "Yes" : "No")
//                        .help(Text("Whether this app handles updating itself", bundle: .module, comment: "tooltip text describing when an app auto-updates"))

                } else {
                    if let landingPage = info.catalogMetadata.landingPage {
                        linkTextField(Text("Home", bundle: .module, comment: "app catalog entry info link title"), icon: .house, url: landingPage)
                            .help(Text("Opens link to the landing page for this app at: \(landingPage.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }
                    if let discussionsURL = info.catalogMetadata.discussionsURL {
                        linkTextField(Text("Discussions", bundle: .module, comment: "app catalog entry info link title"), icon: .text_bubble, url: discussionsURL)
                            .help(Text("Opens link to the discussions page for this app at: \(discussionsURL.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }
                    if let issuesURL = info.catalogMetadata.issuesURL {
                        linkTextField(Text("Issues", bundle: .module, comment: "app catalog entry info link title"), icon: .checklist, url: issuesURL)
                            .help(Text("Opens link to the issues page for this app at: \(issuesURL.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }
                    if let sourceURL = info.catalogMetadata.sourceURL {
                        linkTextField(Text("Source", bundle: .module, comment: "app catalog entry info link title"), icon: .chevron_left_forwardslash_chevron_right, url: sourceURL)
                            .help(Text("Opens link to source code repository for this app at: \(sourceURL.absoluteString)", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }
                    if let fairsealURL = info.catalogMetadata.fairsealURL {
                        linkTextField(Text("Fairseal", bundle: .module, comment: "app catalog entry info link title"), icon: .rosette, url: fairsealURL, linkText: String(info.catalogMetadata.sha256 ?? ""))
                            .help(Text("Lookup fairseal at: \(info.catalogMetadata.fairsealURL?.absoluteString ?? "")", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }
                    if let developerURL = info.catalogMetadata.developerURL {
                        linkTextField(Text("Developer", bundle: .module, comment: "app catalog entry info link title"), icon: .person, url: developerURL, linkText: metadata.developerName)
                            .help(Text("Searches for this developer at: \(info.catalogMetadata.developerURL?.absoluteString ?? "")", bundle: .module, comment: "app catalog entry info link tooltip"))
                    }
                }
            }
            .symbolRenderingMode(SymbolRenderingMode.hierarchical)
            //.font(Font.body.monospaced())
            //.textFieldStyle(.plain)
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
    }

    @State var overviewTab = OverviewTab.description

    enum OverviewTab : CaseIterable, Hashable {
        case description
        case version
        case caveats

        var title: Text {
            switch self {
            case .description: return Text("Description", bundle: .module, comment: "app catalog cask entry overview tab title")
            case .version: return Text("Version", bundle: .module, comment: "app catalog cask entry overview tab title")
            case .caveats: return Text("Caveats", bundle: .module, comment: "app catalog cask entry preview overview title")
            }
        }
    }

    @State var metadataTab = MetadataTab.details

    enum MetadataTab : CaseIterable, Hashable {
        case details
        case permissions
        case formula
        case security

        var title: Text {
            switch self {
            case .details: return Text("Details", bundle: .module, comment: "app catalog cask entry metadata tab title for app details")
            case .permissions: return Text("Permissions", bundle: .module, comment: "app catalog cask entry metadata tab title for app permissions")
            case .formula: return Text("Formula", bundle: .module, comment: "app catalog cask entry metadata tab title for app formula")
            case .security: return Text("Security", bundle: .module, comment: "app catalog cask entry metadata tab title for app secutiry")
            }
        }
    }


    func catalogOverview() -> some View {
        VStack {
            HStack {
                overviewTabView()
                metadataTabView()
            }
            .frame(maxHeight: 200)

            previewTabView()
        }
    }

    @State var previewTab = PreviewTab.screenshots

    enum PreviewTab : CaseIterable, Hashable {
        case screenshots
        case discussions
        case homepage

        var title: Text {
            switch self {
            case .screenshots: return Text("Screen Shots", bundle: .module, comment: "app catalog cask entry preview tab title")
            case .discussions: return Text("Discussions", bundle: .module, comment: "app catalog cask entry preview tab title")
            case .homepage: return Text("Home Page", bundle: .module, comment: "app catalog cask entry preview tab title")
            }
        }
    }


    /// The preview tabs, including screenshots and the homepage
    func previewTabView() -> some View {
        TabView(selection: $previewTab) {
            ForEach(PreviewTab.allCases, id: \.self) { tab in
                Group {
                    switch tab {
                    case .screenshots:
                        screenshotsSection()
                    case .discussions:
                        discussionsSection()
                    case .homepage:
                        homepageSection()
                    }
                }
                .tag(tab)
                .tabItem {
                    tab.title
                }
            }
        }
        .onAppear { // change to homepage when there are no screenshots
            if metadata.screenshotURLs?.isEmpty == false {
                previewTab = .screenshots
            } else if fairManager.homeBrewInv.enableCaskHomepagePreview == true {
                previewTab = .homepage
            }
        }
    }

    @ViewBuilder func discussionsSection() -> some View {
        webViewSection(page: info.isCask ? nil : info.catalogMetadata.discussionsURL)
    }

    @ViewBuilder func homepageSection() -> some View {
        webViewSection(page: info.homepage ?? info.catalogMetadata.landingPage)
    }

    /// Use an embedded mini-browser to show the given URL
    @ViewBuilder private func webViewSection(page: URL?) -> some View {
        if let page = page {
            CatalogItemBrowserView(page: page, openLinksInNewBrowser: fairManager.openLinksInNewBrowser)
        }
    }

    func screenshotsSection() -> some View {
        ScrollView(.horizontal) {
            screenshotsStackView()
        }
        .overlay(Group {
            if metadata.screenshotURLs?.isEmpty != false {
                VStack {
                    Spacer()
                    Label {
                        Text("No screenshots available", bundle: .module, comment: "placeholder string for empty screenshot preview section") // ([contribute…](https://www.appfair.app/#customize_app))")
                            .lineLimit(1)
                            .font(Font.callout)
                            .help(Text("This app has not published any screenshots", bundle: .module, comment: "tooltip for empty screenshot preview section"))
                    } icon: {
                        unavailableIcon
                    }
                    .padding()
                    Spacer()


                    Text("(if you own or maintain this app, you can [contribute](https://www.appfair.app/#customize_app) screenshots and other metadata)", bundle: .module, comment: "footer markdown text of screenshots page indicating how to update catalog metadata")
                        .font(Font.caption)
                        .lineLimit(1)
                        .help(Text("Click here for information on customizing screenshots and other metadata for this app.", bundle: .module, comment: "tooltip text for footer of screenshots page indicating how to update catalog metadata"))

                }
                .foregroundColor(.secondary)
            }
        })
    }

    func overviewTabView() -> some View {
        TabView(selection: $overviewTab) {
            ForEach(OverviewTab.allCases, id: \.self) { tab in
                Group {
                    switch tab {
                    case .description:
                        ReadmeBox(info: info)
                    case .version:
                        ReleaseNotesBox(info: info)
                    case .caveats:
                        if let cask = info.cask, let caveats = cask.caveats {
                            textBox(.success(AttributedString(caveats)))
                        }
                    }
                }
                .tag(tab)
                .tabItem {
                    Label {
                        if tab == .version, let version = metadata.version, version.count < 16 {
                            Text(verbatim: version)
                        } else {
                            tab.title
                        }
                    } icon: {
                        //fetchingReadme > 0 ? FairSymbol.hourglass : FairSymbol.atom
                    }
                }
            }
        }
    }

    func metadataTabView() -> some View {
        TabView(selection: $metadataTab) {
            ForEach(MetadataTab.allCases, id: \.self) { tab in
                Group {
                    switch tab {
                    case .details:
                        detailsListView()
                    case .permissions:
                        if info.cask == nil {
                            permissionsSection()
                        }
                    case .security:
                        if info.cask != nil {
                            //SecurityBox(info: info) // TODO: make this human-readable for presentation instead of showing the raw JSON
                        }
                    case .formula:
                        if let cask = info.cask {
                            CaskFormulaBox(cask: cask, json: false)
                        }
                    }
                }
                .tag(tab)
                .tabItem {
                    tab.title
//                    Label {
//                    } icon: {
//                        // fetchingFormula > 0 ? FairSymbol.hourglass : FairSymbol.atom
//                    }
                }
            }
        }
    }

    // MARK: README


    // MARK: Description / Summary

    func permissionsSection() -> some View {
        let riskLabel = info.isCask ? Text("Risk: Unknown", bundle: .module, comment: "label for unknown rick") : Text("Risk: ", bundle: .module, comment: "prefix string for risk label") + metadata.riskLevel.textLabel().fontWeight(.regular)

        let riskIcon = (info.isCask ? nil : metadata)?.riskLevel.riskLabel()
            .help(metadata.riskLevel.riskSummaryText())
            .labelStyle(IconOnlyLabelStyle())
            .padding(.trailing)

        return groupBox(title: riskLabel, trailing: riskIcon) {
            permissionsList()
                .overlay(Group {
                    if info.isCask {
                        Text("Risk assessment unavailable for Homebrew Casks", bundle: .module, comment: "placeholder string")
                            .label(image: unavailableIcon)
                            .padding()
                            .lineLimit(1)
                            .font(Font.callout)
                            .foregroundColor(.secondary)
                            .help(Text("Risk assessment is only available for App Fair Fairground apps", bundle: .module, comment: "tooltip text"))
                    }
                })
        }
    }

    func permissionListItem(permission: AppLegacyPermission) -> some View {
        let entitlement = permission.type

        var title = entitlement.localizedInfo.title
        if !permission.usageDescription.isEmpty {
            title = Text("\(title) – \(Text(permission.usageDescription))", bundle: .module, comment: "formatting string separating the permission title from the permission description").foregroundColor(.secondary).italic()
        }

        return title.label(image: entitlement.localizedInfo.symbol.image)
            .listItemTint(ListItemTint.monochrome)
            .symbolRenderingMode(SymbolRenderingMode.monochrome)
            .lineLimit(1)
            .truncationMode(.tail)
        //.textSelection(.enabled)
            .help(Text("\(entitlement.localizedInfo.info): \( Text(permission.usageDescription))", bundle: .module, comment: "formatting string separating entitlement info from usage description in tooltip text"))
    }

    /// The entitlements that will appear in the list.
    /// These filter out entitlements that are pre-requisites (e.g., sandboxing) as well as harmless entitlements (e.g., JIT).
    var listedPermissions: [AppLegacyPermission] {
        metadata.orderedPermissions(filterCategories: [.harmless, .prerequisite])
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

    func previewImage(_ url: URL) -> some View {
        URLImage(url: url, resizable: .fit)
    }

    func screenshotsStackView() -> some View {
        LazyHStack {
            ForEach(metadata.screenshotURLs ?? [], id: \.self) { url in
                previewImage(url)
                    .matchedGeometryEffect(id: url, in: namespace, isSource: self.previewScreenshot != url)
                    .contentShape(Rectangle())
                    .button {
                        dbg("open screenshot:", url.relativePath)
                        withAnimation(Animation.spring(response: 0.45, dampingFraction: 0.9)) {
                            self.previewScreenshot = url
                        }
                    }
                    .buttonStyle(.zoomable)
            }
        }
    }

    func screenshotPreviewOverlay() -> some View {
        ZStack {
            if self.previewScreenshot != nil {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }

            ForEach(metadata.screenshotURLs ?? [], id: \.self) { url in
                let presenting = self.previewScreenshot == url

                ZStack {
                    URLImage(url: url, resizable: ContentMode.fit, showProgress: false)
                        .matchedGeometryEffect(id: url, in: namespace, isSource: presenting)
                        .shadow(color: Color.black.opacity(presenting ? 0.2 : 0), radius: 20, y: 10)
                        .padding(20)

                    // The top button bar
                    VStack {
                        HStack {
                            Spacer()
                            FairSymbol.xmark_circle
                                .image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .hoverSymbol(activeVariant: .none, inactiveVariant: .fill)
                                .button {
                                    withAnimation {
                                        self.previewScreenshot = nil
                                    }
                                }
                                .keyboardShortcut(.escape) // sadly doesn't seem to work
                                .disabled(!presenting)
                                .buttonStyle(.plain)
                                .frame(width: 25, height: 25)
                                .padding()
                        }
                        Spacer()
                    }

                }
                .prefersDefaultFocus(in: namespace)
                .onTapGesture {
                    // tapping anywhere in the view will close the preview
                    withAnimation {
                        self.previewScreenshot = nil
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibility(sortPriority: presenting ? 1 : 0)
                .accessibility(hidden: !presenting)
                .opacity(presenting ? 1 : 0)
            }
        }
    }

    func catalogAuthorRow() -> some View {
        Group {
            let devName = info.catalogMetadata.developerName ?? ""
            if devName.isEmpty {
                Text("Unknown", bundle: .module, comment: "fallback text for unknown developer name")
            } else {
                Text(devName)
            }
        }
    }

    func numberView(number numberStyle: NumberFormatter.Style? = nil, size sizeStyle: ByteCountFormatStyle.Style? = nil, _ path: KeyPath<AppCatalogItem, Int?>) -> some View {
        numberView(number: numberStyle, size: sizeStyle, value: info.catalogMetadata[keyPath: path])
    }

    func numberView(number numberStyle: NumberFormatter.Style? = nil, size sizeStyle: ByteCountFormatStyle.Style? = nil, value: Int?) -> some View {
        if let value = value {
            if let sizeStyle = sizeStyle {
                return Text(Int64(value), format: .byteCount(style: sizeStyle))
            } else {
                return Text(value, format: .number)
            }
        } else {
            return Text(FairSymbol.questionmark.image)
        }
    }

    /// Show a histogram of where the given value lies in the context of other apps in the grouping (TODO)
    func histogramView(_ path: KeyPath<AppCatalogItem, Int?>) -> EmptyView? {
        nil
        //FairSymbol.chart_bar_xaxis.image.resizable()
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
            fairManager.iconView(for: info, transition: true)
                .frame(width: 60, height: 60)
                .transition(AnyTransition.asymmetric(insertion: AnyTransition.opacity, removal: AnyTransition.scale(scale: 0.75).combined(with: AnyTransition.opacity))) // shrink and fade out the placeholder while fading in the actual icon
                .padding(.leading)

            VStack(alignment: .center) {
                Text(metadata.name)
                    .font(Font.largeTitle)
                    .truncationMode(.middle)
                Text(metadata.subtitle ?? metadata.localizedDescription ?? "")
                    .font(Font.title2)
                    .truncationMode(.tail)
//                catalogAuthorRow()
//                    .font(Font.title3)
//                    .truncationMode(.head)
            }
            //.textSelection(.enabled) // this makes the text turn very dark when it is selected
            .lineLimit(1)
            .allowsTightening(true)
            .hcenter()

            categorySymbol()
                .frame(width: 60, height: 60)
                .padding(.trailing)
        }
    }

    func catalogActionButtons() -> some View {
        let isCatalogApp = info.catalogMetadata.bundleIdentifier.rawValue == Bundle.main.bundleID

        return GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    if isCatalogApp {
                        Spacer() // no button to install ourselves
                            .hcenter()
                    } else {
                        installButton()
                            .hcenter()
                    }
                    updateButton()
                        .hcenter()
                    if isCatalogApp {
                        Spacer() // no button to launch ourselves
                            .hcenter()
                    } else {
                        launchButton()
                            .hcenter()
                    }
                    revealButton()
                        .hcenter()
                    if isCatalogApp {
                        Spacer() // no button to delete ourselves
                            .hcenter()
                    } else {
                        trashButton()
                            .hcenter()
                    }
                }
                .symbolRenderingMode(.hierarchical)
                .buttonBorderShape(.roundedRectangle)
                .frame(minWidth: proxy.size.width) // cause the buttons to scroll off the view if it is too narrow to hold them all
            }
        }
    }

    func installButton() -> some View {
        button(activity: .install, role: nil, needsConfirm: fairManager.enableInstallWarning)
            .keyboardShortcut(currentActivity == .install ? .cancelAction : .defaultAction)
            .disabled(appInstalled)
            .confirmationDialog(Text("Install \(info.catalogMetadata.name)", bundle: .module, comment: "install button confirmation dialog title"), isPresented: confirmationBinding(.install), titleVisibility: .visible, actions: {
                Text("Download & Install \(info.catalogMetadata.name)", bundle: .module, comment: "install button confirmation dialog confirm button text").button {
                    runTask(activity: .install, confirm: true)
                }
                if let cask = info.cask {
                    if let page = cask.homepage, let homepage = URL(string: page) {
                        Text("Visit Homepage: \(homepage.host ?? "")", bundle: .module, comment: "install button confirmation dialog visit homepage button text").button {
                            openURLAction(homepage)
                        }
                    }
                } else {
                    if let discussionsURL = info.catalogMetadata.discussionsURL {
                        Text("Visit Community Forum", bundle: .module, comment: "install button confirmation dialog visit discussions button text").button {
                            openURLAction(discussionsURL)
                        }
                    }
                }
                // TODO: only show if there are any open issues
                // Text("Visit App Issues Page").button {
                //    openURLAction(info.catalogMetadata.issuesURL)
                // }
                //.help(Text("Opens your web browsers and visits the developer site")) // sadly, tooltips on confirmationDialog buttons don't seem to work
            }, message: installMessage)
            .tint(.green)
    }

    func updateButton() -> some View {
        button(activity: .update)
            .keyboardShortcut(currentActivity == .update ? .cancelAction : .defaultAction)
            .disabled((!appInstalled || !appUpdated))
            .accentColor(.orange)
    }

    func launchButton() -> some View {
        button(activity: .launch)
            .keyboardShortcut(KeyboardShortcut(KeyEquivalent.return, modifiers: .command))
            .disabled(!appInstalled)
            .accentColor(.green)
    }

    func revealButton() -> some View {
        button(activity: .reveal)
            .keyboardShortcut(KeyboardShortcut(KeyEquivalent("i"), modifiers: .command)) // CMD-I
            .disabled(!appInstalled)
            .accentColor(.teal)
    }

    func trashButton() -> some View {
        button(activity: .trash, role: ButtonRole.destructive, needsConfirm: fairManager.enableDeleteWarning)
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!appInstalled)
        //.accentColor(.red) // coflicts with the red background of the button
            .confirmationDialog(Text("Really delete this app?", bundle: .module, comment: "delete button confirmation dialog title"), isPresented: confirmationBinding(.trash), titleVisibility: .visible, actions: {
                Text("Delete", bundle: .module, comment: "delete button confirmation dialog delete button text").button {
                    runTask(activity: .trash, confirm: true)
                }
            }, message: {
                Text("This will remove the application “\(info.catalogMetadata.name)” from your applications folder and place it in the Trash.", bundle: .module, comment: "delete button confirmation dialog body text")
            })
    }

    func installMessage() -> some View {
        let developerName = info.catalogMetadata.developerName ?? ""

        if info.isCask {
            return Text("""
                This will use the Homebrew package manager to download and install the application “\(info.catalogMetadata.name)” from the developer “\(developerName)” at:

                [\(info.catalogMetadata.downloadURL.absoluteString)](\(info.catalogMetadata.downloadURL.absoluteString))

                This app has not undergone any formal review, so you will be installing and running it at your own risk.

                Before installing, you should first review the home page for the app to learn more about it.
                """, bundle: .module, comment: "installation warning for homebrew apps")
        } else {
            let metaURL = info.catalogMetadata.sourceURL?.absoluteString ?? ""
            return Text("""
                This will download and install the application “\(info.catalogMetadata.name)” from the developer “\(developerName)” at:

                \(metaURL)

                This app has not undergone any formal review, so you will be installing and running it at your own risk.

                Before installing, you should first review the Discussions, Issues, and Documentation pages to learn more about the app.
                """, bundle: .module, comment: "installation warning for fairground apps")
        }
    }

    private var metadata: AppCatalogItem {
        info.catalogMetadata
    }

    /// Whether the app is successfully installed
    var appInstalled: Bool {
        fairManager.installedVersion(for: info) != nil
    }

    /// Whether the given app is up-to-date or not
    var appUpdated: Bool {
        fairManager.appUpdated(for: info)
    }

    func confirmationBinding(_ activity: CatalogActivity) -> Binding<Bool> {
        Binding {
            confirmations[activity] ?? false
        } set: { newValue in
            confirmations[activity] = newValue
        }
    }

    func cancelTask(activity: CatalogActivity) {
        if currentOperation?.activity == activity {
            currentOperation?.progress.cancel()
            currentOperation = nil
        }
    }

    func runTask(activity: CatalogActivity, confirm confirmed: Bool) {
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

    /// The height of the accessory for the buttons
    let accessoryHeight = 18.0

    let buttonHeight = 22.0 // a friendly-feeling height

    func button(activity: CatalogActivity, role: ButtonRole? = .none, needsConfirm: Bool = false) -> some View {
        Button(role: role, action: {
            if currentActivity == activity {
                // clicking the button while the operation is being performed will cancel it
                cancelTask(activity: activity)
            } else {
                runTask(activity: activity, confirm: !needsConfirm)
            }
        }, label: {
            HStack(spacing: 0) {
                Group {
                    if currentActivity == activity {
                        ProgressView()
                            .progressViewStyle(.circular) // spinner
                            .controlSize(.mini) // needs to be small to fit in the button
                            .opacity(currentActivity == activity ? 1 : 0)
                    } else {
                        activity.info.systemSymbol
                    }
                }
                .frame(width: 20)
                Group {
                    //GeometryReader { proxy in
                    activity.info.title
                        .font(Font.headline.smallCaps())
                    //.truncationMode(.middle)
                    //.allowsTightening(true)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: true, vertical: true) // needed to prevent text truncation
                    //.opacity(proxy.size.width < 50 ? 0.0 : 1.0) // hide label when the button is too small
                }
                .hcenter()
                Group {
                    if currentActivity == activity {
                        FairSymbol.x_circle
                            .hoverSymbol(activeVariant: .fill, inactiveVariant: .none, animation: .easeInOut) //.symbolRenderingMode(.hierarchical)
                    } else if let activityWarning = warning(for: activity) {
                        EnabledView { enabled in
                            FairSymbol.exclamationmark_triangle_fill
                                .symbolRenderingMode(enabled ? .multicolor : .hierarchical)
                                .help(activityWarning)
                        }
                    } else {
                        FairSymbol.circle
                    }
                }
                .frame(width: 20)
            }
            .frame(height: buttonHeight)
        })
            .buttonStyle(ActionButtonStyle(progress: .constant(currentActivity == activity ? progress.progress.fractionCompleted : 1.0), primary: true, highlighted: false))
            .focusable(true)
            .accentColor(activity.info.tintColor)
            .disabled(currentActivity != nil && currentActivity != activity)
            .animation(.easeIn(duration: 0.25), value: currentActivity) // make the enabled state of the button animate
            .help(currentActivity == activity ? (Text("Cancel \(activity.info.title)", bundle: .module, comment: "cancel catalog activity tooltip text")) : activity.info.toolTip)
    }

    func performAction(activity: CatalogActivity) async {
        switch activity {
        case .install: await installButtonTapped()
        case .update: await updateButtonTapped()
        case .trash: await deleteButtonTapped()
        case .reveal: await revealButtonTapped()
        case .launch: await launchButtonTapped()
        }
    }

    /// Returns a warning if there is likely to be an issue with the given operation
    func warning(for activity: CatalogActivity) -> Text? {
        switch activity {
        case .install, .update:
            if info.catalogMetadata.sha256 == nil {
                return Text("Installation artifact cannot be verified because it has no associated SHA-256 checksum.", bundle: .module, comment: "warning text when installing an item without a checksum")
            }
            return nil

        case .trash:
            return nil
        case .reveal:
            return nil
        case .launch:
            return nil
        }
    }

    func categorySymbol() -> some View {
        //let category = (item.appCategories.first?.groupings.first ?? .create)

        //let img = Image(systemName: category.symbolName.description)
        let img = info.displayCategories.first?.symbol.image ?? (info.isCask ? AppSource.homebrew.symbol.image : AppSource.fairapps.symbol.image)
        let baseColor = metadata.itemTintColor()
        return ZStack {
            Circle()
                //.fill(baseColor)
                //.foregroundStyle(.linearGradient(colors: [baseColor, baseColor], startPoint: .top, endPoint: .bottom))
                .foregroundStyle(
                    .linearGradient(colors: [baseColor.opacity(0.8), baseColor], startPoint: .top, endPoint: .bottom)
                )
                .background(Circle().foregroundColor(Color.white)) // need a background of white so the opacity looks right

            img
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(Color.white)
                //.fairTint(simple: true, color: baseColor, scheme: colorScheme)
                .symbolVariant(.fill)
                .symbolRenderingMode(.palette)
                .padding()
                //.brightness(0.4)
            //.foregroundColor(.secondary)
        }
    }

    func card<V1: View, V2: View, V3: View>(_ s1: V1, _ s2: V2, _ s3: V3?) -> some View {
        VStack(alignment: .center) {
            s1
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .bold, design: .default))
            s2
                .font(.system(size: 20, weight: .heavy, design: .rounded))
            if let s3 = s3 {
                s3
                    .padding(.horizontal)
            }
        }
        .foregroundColor(.secondary)
    }

    func startProgress() -> Progress {
        progress.progress = Progress(totalUnitCount: URLSession.progressUnitCount)
        currentOperation?.progress = progress.progress
        return progress.progress
    }

    func launchButtonTapped() async {
        dbg("launchButtonTapped")
        await fairManager.launch(info)
    }

    func installButtonTapped() async {
        dbg("installButtonTapped")
        await fairManager.install(info, progress: startProgress(), update: false)
    }

    func updateButtonTapped() async {
        dbg("updateButtonTapped")
        await fairManager.install(info, progress: startProgress(), update: true)
    }

    func revealButtonTapped() async {
        dbg("revealButtonTapped")
        if info.isCask == true {
            await fairManager.trying {
                try await fairManager.homeBrewInv.reveal(item: info)
            }
        } else {
            await fairManager.trying {
                try await fairManager.fairAppInv.reveal(item: info.catalogMetadata)
            }
        }
    }

    func deleteButtonTapped() async {
        dbg("deleteButtonTapped")
        if info.isCask {
            return await fairManager.trying {
                try await fairManager.homeBrewInv.delete(item: info)
            }
        } else {
            return await fairManager.trying {
                try await fairManager.fairAppInv.delete(item: info.catalogMetadata)
            }
        }
    }
}

//private let readmeRegex = Result {
//    try NSRegularExpression(pattern: #".*## Description\n(?<description>[^#]+)\n#.*"#, options: .dotMatchesLineSeparators)
//}

/// Regular expression to replace headers with bold text (since markdown doesn't yet support headers)
private let headerRegex = Result {
    try NSRegularExpression(pattern: #"^#+ (?<text>.*)$"#, options: [.anchorsMatchLines])
}

fileprivate extension View {
    func textBox(_ text: Result<AttributedString, Error>?) -> some View {
        let astr: AttributedString
        switch text {
        case .none: astr = AttributedString()
        case .success(let str): astr = str
        case .failure(let error): astr = AttributedString(error.localizedDescription, attributes: .init([NSAttributedString.Key.obliqueness: 8]))
        }

        return ZStack {
            ScrollView {
                Text(astr)
                    //.textSelection(.enabled) // there's a weird bug here that causes multi-line text to stop wrapping lined when the text box is selected
                    //.fixedSize() // doesn't help
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            if text == nil {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    func fetchMarkdownResource(url: URL, info: AppInfo) async throws -> AttributedString {
        let data = try await URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
            .fetch(validateFragmentHash: true)
        var atx = String(data: data, encoding: .utf8) ?? ""

//        // extract the portion of text between the "# Description" and following "#" sections
//        if let match = try readmeRegex.get().firstMatch(in: atx, options: [], range: atx.span)?.range(withName: "description") {
//            atx = (atx as NSString).substring(with: match)
//        } else {
//            if !info.isCask { // casks don't have this requirement; permit full READMEs
//                atx = ""
//            }
//        }

        // replace headers (which are unsupported in AttributedString) with simply bold styling
        for match in try headerRegex.get().matches(in: atx, options: [], range: atx.span).reversed() {
            let textRange = match.range(withName: "text")
            let text = (atx as NSString).substring(with: textRange)

            dbg("replacing header range:", match.range, " with bold text:", text)
            atx = (atx as NSString).replacingCharacters(in: match.range, with: ["**", text, "**"].joined())
        }

        // the README.md relative location is 2 paths down from the repository base, so for relative links to Issues and Discussions to work the same as they do in the web version, we need to append the path that the README would be rendered in the browser

        // note this this differs with casks
        let baseURL = info.catalogMetadata.baseURL?.appendingPathComponent("blob/main/")
        return try AttributedString(markdown: atx.trimmed(), options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible, languageCode: nil), baseURL: baseURL)
    }


}

struct ReadmeBox : View {
    let info: AppInfo

    @State var readmeText: Result<AttributedString, Error>? = nil
    @State var fetchingReadme = 0

    var body: some View {
        descriptionSection()
    }

    func descriptionSection() -> some View {
        textBox(self.readmeText)
            .font(Font.body)
            .task {
                if fetchingReadme == 0 {
                    fetchingReadme += 1
                    await fetchReadme()
                    fetchingReadme -= 1
                }
            }
    }


    private func fetchReadme() async {
        let readmeURL = info.catalogMetadata.readmeURL
        do {
            dbg("fetching README for:", info.catalogMetadata.id, readmeURL?.absoluteString)
            if let readmeURL = readmeURL {
                let txt = try await fetchMarkdownResource(url: readmeURL, info: info)
                //withAnimation { // the effect here is weird: it expands from zero width
                    self.readmeText = .success(txt)
                //}
            } else {
                // throw AppError(loc("No description found."))
                self.readmeText = .success(AttributedString(info.catalogMetadata.localizedDescription ?? NSLocalizedString("No description found", bundle: .module, comment: "error message when no app description could be found")))
            }
        } catch {
            dbg("error handling README:", error)
            //if let readmeURL = readmeURL {
                self.readmeText = .failure(error)
            //}
        }
    }


}

struct SecurityBox : View {
    let info: AppInfo

    @State private var securitySummary: Result<AttributedString, Error>? = nil
    @State private var fetchingSecurity = 0

    var body: some View {
        artifactSecuritySection()
    }

    func artifactSecuritySection() -> some View {
        textBox(self.securitySummary)
            .font(Font.body.monospaced())
            .task {
                if fetchingSecurity == 0 && securitySummary == nil {
                    fetchingSecurity += 1
                    self.securitySummary = await fetchArtifactSecurity(checkFileHash: true)
                    fetchingSecurity -= 1
                }
            }

    }

    func fetchArtifactSecurity(checkFileHash: Bool = true, reparseJSON: Bool = false) async -> Result<AttributedString, Error>? {

        let url: URL?
        if checkFileHash == false {
            let sourceURL = self.info.cask?.url ?? self.info.catalogMetadata.downloadURL.absoluteString
            let urlChecksum = sourceURL.utf8Data.sha256().hex()

            url = URL(string: urlChecksum, relativeTo: URL(string: "https://www.appfair.net/fairscan/urls/"))?.appendingPathExtension("json")

        } else { // use the artifact URL hash
            guard let checksum = self.info.cask?.checksum ?? self.info.catalogMetadata.sha256 else {
                dbg("no checksum for artifact")
                return nil
            }

            if checksum == "no_check" {
                dbg("checksum for artifact is no_check")
                return nil
            }

            url = URL(string: checksum, relativeTo: URL(string: "https://www.appfair.net/fairscan/files/"))?.appendingPathExtension("json") // e.g.: https://www.appfair.net/fairscan/urls/ffea53299849ef43ee26927cbf3ff0342fa6e9a1421059c368fe91a992c9a3a1.json
        }

        guard let url = url else {
            dbg("no URL for info", info.catalogMetadata.name)
            return nil
        }

        do {
            dbg("checking security URL:", url.absoluteString)
            let scanResult = try await URLSession.shared.fetch(request: URLRequest(url: url))
            if !reparseJSON {
                return .success(AttributedString(scanResult.data.utf8String ?? ""))
            } else {
                do {
                    let ob = try JSum(json: scanResult.data)
                    let pretty = try ob.json(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    return .success(AttributedString(pretty.utf8String ?? ""))
                } catch {
                    return .success(AttributedString(scanResult.data.utf8String ?? ""))
                }
            }
        } catch {
            // errors are not unexpected when the user leaves this view:
            // NSURLErrorDomain Code=-999 "cancelled"
            dbg("error checking cask security:", url.absoluteString, "error:", error)
            return .failure(error)
        }
    }
}

struct ReleaseNotesBox : View {
    let info: AppInfo

    @State var releaseNotesText: Result<AttributedString, Error>? = nil
    @State var fetchingReleaseNotes = 0

    var body: some View {
        versionSection()
    }


    @ViewBuilder func versionSection() -> some View {
//        let desc = info.isCask ? info.cask?.caveats : self.info.catalogMetadata.versionDescription
        textBox(self.releaseNotesText)
            .font(.body)
            .task {
                if fetchingReleaseNotes == 0 {
                    fetchingReleaseNotes += 1
                    await fetchReleaseNotes()
                    fetchingReleaseNotes -= 1
                }
            }
    }

    func fetchReleaseNotes() async {
        let releaseNotesURL = info.catalogMetadata.releaseNotesURL
        do {
            dbg("fetching release notes for:", info.catalogMetadata.id, releaseNotesURL?.absoluteString)
            if let releaseNotesURL = releaseNotesURL {
                let notes = try await fetchMarkdownResource(url: releaseNotesURL, info: info)
                //withAnimation { // the effect here is weird: it expands from zero width
                    self.releaseNotesText = .success(notes)
                //}
            } else if let cask = info.cask {
                guard let (strategy, appcastURL) = try await HomebrewInventory.default.fetchLivecheck(for: cask.token) else {
                    self.releaseNotesText = .success(AttributedString("Missing release notes"))
                    return
                }

                if !strategy.hasPrefix(":sparkle") {
                    self.releaseNotesText = .success(AttributedString("Incompatible release notes"))
                    return
                }

                let (contents, _) = try await URLSession.shared.fetch(request: URLRequest(url: appcastURL))
                let webFeed = try AppcastFeed(xmlData: contents)

                guard let channel = webFeed.channels.first else {
                    self.releaseNotesText = .success(AttributedString("No release channel"))
                    return
                }
                self.releaseNotesText = .success(AttributedString(channel.title ?? "No title"))
            } else {
                self.releaseNotesText = .success(AttributedString("No release notes"))
            }
        } catch {
            dbg("error handling release notes:", error)
            //if let readmeURL = readmeURL {
                self.releaseNotesText = .failure(error)
            //}
        }
    }

//    func releaseVersionAccessoryView() -> Text? {
//        if let versionDate = info.catalogMetadata.versionDate ?? self.caskURLModifiedDate {
//            return Text(versionDate, format: .dateTime)
//        } else {
//            return nil
//        }
//    }
}

struct CaskFormulaBox : View {
    let cask: CaskItem
    let json: Bool

    @EnvironmentObject var fairManager: FairManager

    @State private var caskSummary: Result<AttributedString, Error>? = nil
    @State private var fetchingFormula = 0

    var body: some View {
        caskFormulaSection(cask: cask)
    }

    func caskFormulaSection(cask: CaskItem) -> some View {
        textBox(self.caskSummary)
            .font(Font.body.monospaced())
            .task {
                if fetchingFormula == 0 {
                    fetchingFormula += 1
                    await fetchCaskSummary(json: json)
                    fetchingFormula -= 1
                }
            }
    }

    private func fetchCaskSummary(json jsonSource: Bool) async {
        if self.caskSummary == nil, let url = jsonSource ? fairManager.homeBrewInv.caskMetadata(name: cask.token) : fairManager.homeBrewInv.caskSource(name: cask.token) {
            // self.caskSummary = NSLocalizedString("Loading…", bundle: .module, comment: "") // makes unnecessary flashes
            do {
                dbg("checking cask summary:", url.absoluteString)
                let metadata = try await URLSession.shared.fetch(request: URLRequest(url: url))
                if jsonSource {
                    do {
                        let ob = try JSum(json: metadata.data)
                        let pretty = try ob.json(outputFormatting: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
                        self.caskSummary = .success(AttributedString(pretty.utf8String ?? ""))
                    } catch {
                        self.caskSummary = .success(AttributedString(metadata.data.utf8String ?? ""))
                    }
                } else {
                    self.caskSummary = .success(AttributedString(metadata.data.utf8String ?? ""))
                }
            } catch {
                // errors are not unexpected when the user leaves this view:
                // NSURLErrorDomain Code=-999 "cancelled"
                dbg("error checking cask metadata:", url.absoluteString, "error:", error)
                self.caskSummary = .failure(error)
            }
        }
    }
}

extension CatalogActivity {
    var info: (title: Text, systemSymbol: FairSymbol, tintColor: Color?, toolTip: Text) {
        switch self {
        case .install:
            return (Text("Install", bundle: .module, comment: "catalog entry button title for install action"), .square_and_arrow_down_fill, Color.blue, Text("Download and install the app.", bundle: .module, comment: "catalog entry button tooltip for install action"))
        case .update:
            return (Text("Update", bundle: .module, comment: "catalog entry button title for update action"), .square_and_arrow_down_on_square, Color.orange, Text("Update to the latest version of the app.", bundle: .module, comment: "catalog entry button tooltip for update action")) // TODO: when pre-release, change to "Update to the latest pre-release version of the app"
        case .trash:
            return (Text("Delete", bundle: .module, comment: "catalog entry button title for delete action"), .trash, Color.red, Text("Delete the app from your computer.", bundle: .module, comment: "catalog entry button tooltip for delete action"))
        case .reveal:
            return (Text("Reveal", bundle: .module, comment: "catalog entry button title for reveal action"), .doc_viewfinder_fill, Color.indigo, Text("Displays the app install location in the Finder.", bundle: .module, comment: "catalog entry button tooltip for reveal action"))
        case .launch:
            return (Text("Launch", bundle: .module, comment: "catalog entry button title for launch action"), .checkmark_seal, Color.green, Text("Launches the app.", bundle: .module, comment: "catalog entry button tooltip for launch action"))
        }
    }
}

extension AppCatalogItem {
    @ViewBuilder func iconImage() -> some View {
        if let iconURL = self.iconURL {
            AsyncImage(url: iconURL, scale: 1.0, transaction: Transaction(animation: .easeIn)) { phase in
                switch phase {
                case .success(let image):
                    //let _ = iconCache.setObject(ImageInfo(image: image), forKey: iconURL as NSURL)
                    //let _ = dbg("success image for:", self.name, image)
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure(let error):
                    let _ = dbg("error image for:", self.name, error)
                    if !error.isURLCancelledError { // happens when items are scrolled off the screen
                        let _ = dbg("error fetching icon from:", iconURL.absoluteString, "error:", error.isURLCancelledError ? "Cancelled" : error.localizedDescription)
                    }
                    fallbackIcon()
                        .grayscale(0.9)
                        .help(error.localizedDescription)
                case .empty:
//                    let _ = dbg("empty image for:", self.name)
//                    if let image = iconCache.object(forKey: iconURL as NSURL) {
//                        image.image
//                            .resizable(resizingMode: .stretch)
//                            .aspectRatio(contentMode: .fit)
//                    } else {
                    fallbackIcon()
                        .grayscale(0.5)
//                    }
                @unknown default:
                    fallbackIcon()
                        .grayscale(0.8)
                }
            }
        } else {
            fallbackIcon()
                .grayscale(1.0)
        }
    }

    @ViewBuilder func fallbackIcon() -> some View {
        let baseColor = itemTintColor()
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(baseColor)
            .opacity(0.5)
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

#if os(macOS)
/// Repliction of iOS's `PageTabViewStyle` for macOS
typealias PaginatedTabViewStyle = DefaultTabViewStyle

//struct PaginatedTabViewStyle : TabViewStyle {
//    static func _makeView<SelectionValue>(value: _GraphValue<_TabViewValue<PaginatedTabViewStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue : Hashable {
//        //_ViewOutputs(value)
//        // inputs.outputs
//    }
//
//    static func _makeViewList<SelectionValue>(value: _GraphValue<_TabViewValue<PaginatedTabViewStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue : Hashable {
//        // inputs
//    }
//}

extension TabViewStyle where Self == PaginatedTabViewStyle {

    /// The page `TabView` style.
    static var paginated: PaginatedTabViewStyle { PaginatedTabViewStyle() }
}
#endif

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
            configuration.icon.frame(width: 16) // otherwise, icons are not aligned
        }
    }
}

struct ZoomableButtonStyle: ButtonStyle {
    var zoomLevel = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? zoomLevel : 1)
    }
}

extension ButtonStyle where Self == ZoomableButtonStyle {
    static var zoomable: ZoomableButtonStyle {
        ZoomableButtonStyle()
    }

    static func zoomable(level: Double = 0.95) -> ZoomableButtonStyle {
        ZoomableButtonStyle(zoomLevel: level)
    }
}

struct CatalogItemBrowserView : View {
    let page: URL
    let openLinksInNewBrowser: Bool // TODO: fairManager.openLinksInNewBrowser
    @Environment(\.openURL) var openURLAction

    @StateObject private var webViewState = WebViewState(initialRequest: nil, configuration: {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.processPool = WKProcessPool()
        config.websiteDataStore = .nonPersistent() // incogito mode
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }())

    var body: some View {
        WebView(state: webViewState)
            .webViewNavigationActionPolicy(decide: { action, state in
                dbg("navigation:", action, "type:", action.navigationType)
                // clicking on links will open in a new browser
                if openLinksInNewBrowser,
                    action.navigationType == .linkActivated,
                    let url = action.request.url {
                    openURLAction(url)
                    return (.cancel, nil)
                } else {
                    return (.allow, nil)
                }
            })
            .task {
                if webViewState.url != page {
                    webViewState.load(page)
                }
            }
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct CatalogItemView_Previews: PreviewProvider {
    static var previews: some View {
        CatalogItemView(info: AppInfo(catalogMetadata: AppCatalogItem.sample))
            .environmentObject(FairAppInventory.default)
            .frame(width: 700)
            .frame(height: 800)
        //.environment(\.locale, Locale(identifier: "fr"))
    }
}
