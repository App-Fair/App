import FairApp

/// The entry point to creating a scene and settings.
public extension AppContainer {
//    /// The root scene for new windows
//    @SceneBuilder static func rootScene(store: AppManager) -> Self.SceneBody
//
//    associatedtype SettingsBody : View
//    /// The settings associated with this app
//    @ViewBuilder static func settingsView(store: AppManager) -> Self.SettingsBody

    #if os(iOS)
    @SceneBuilder static func rootScene(store: FairManager) -> some SwiftUI.Scene {
        WindowGroup { // or DocumentGroup
            FacetHostingView(store: store).environmentObject(store)
        }
        .commands {
            SidebarCommands()
            FacetCommands(store: store)
        }
    }

    static func settingsView(store: FairManager) -> some SwiftUI.View {
        Store.AppFacets.settings
            .facetView(for: store)
            .environmentObject(store)
    }
    #endif

    #if os(macOS)
    @SceneBuilder static func rootScene(store fairManager: FairManager) -> some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .initialViewSize(CGSize(width: 1200, height: 700)) // The default size of the window; this will only be set the first time the app is launched, and then restore whatever the user resizes to
                .environmentObject(fairManager)
                .preferredColorScheme(fairManager.themeStyle.colorScheme)
        }
        .commands {
            AppFairCommands(fairManager: fairManager)
        }
        .commands {
            SidebarCommands()
            SearchBarCommands()
            ToolbarCommands()
        }
        .commands {
            CommandGroup(after: .pasteboard) {
                Group {
                    CopyAppURLCommand()
                }
                .environmentObject(fairManager)
            }
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.newItem) {
                // only permit a single window; this hides the "New" menu option
            }
        }
    }

    /// The app-wide settings view
    @ViewBuilder static func settingsView(store fairManager: FairManager) -> some SwiftUI.View {
        AppSettingsView()
            .preferredColorScheme(fairManager.themeStyle.colorScheme)
            .environmentObject(fairManager)
        // TODO: use facet settings
        //Store.AppFacets.settings
            //.facetView(for: store)
            //.environmentObject(store)
    }
    #endif
}

