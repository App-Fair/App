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

/// A single row in the ``AppsListView``.
struct AppItemLabel : View {
    let item: AppInfo
    let source: AppSource
    @EnvironmentObject var fairManager: FairManager

    var body: some View {
        label(for: item)
    }

    var installedVersion: String? {
        fairManager.installedVersion(item)
    }

    private func label(for item: AppInfo) -> some View {
        return HStack(alignment: .center) {
            ZStack {
                fairManager.iconView(for: item, transition: true)

                if let id = item.id, let progress = fairManager.operations[id]?.progress {
                    FairProgressView(progress)
                        .progressViewStyle(PieProgressViewStyle(lineWidth: 50))
                        .foregroundStyle(Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // make sure the progress doesn't extend past the icon bounds
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(verbatim: item.app.name)
                        .font(.headline)
                        .lineLimit(1)
//                    if fairManager.enableSponsorship,
//                       let fundingLink = item.app.fundingLinks?.first {
//                        ProgressView(value: wip(0.5), total: wip(1.0))
//                            .progressViewStyle(.linear)
//                        FairSymbol.rosette.image
//                            .help(fundingLink.localizedTitle ?? "")
//                    }
                }

                TintedLabel(title: Text(item.app.subtitle ?? item.app.name), symbol: (item.displayCategories.first ?? .utilities).symbol, tint: item.app.itemTintColor(), mode: .hierarchical)
                    .font(.subheadline)
                    .lineLimit(1)
                    .symbolVariant(.fill)
                //.help(category.text)
                HStack {
                    if item.app.permissions != nil {
                        item.app.riskLevel.riskLabel()
                            .help(item.app.riskLevel.riskSummaryText())
                            .labelStyle(.iconOnly)
                            .frame(width: 20)
                    }

                    if let catalogVersion = item.app.version {
                        Label {
                            if let installedVersion = self.installedVersion,
                               catalogVersion != installedVersion {
                                Text("\(installedVersion) (\(catalogVersion))", comment: "formatting text for the app list version section displaying the installed version with the currently available version in parenthesis")
                                    .font(.subheadline)
                            } else {
                                Text(verbatim: catalogVersion)
                                    .font(.subheadline)
                            }
                        } icon: {
                            if let installedVersion = self.installedVersion {
                                if installedVersion == catalogVersion {
                                    CatalogActivity.launch.info.systemSymbol
                                        .foregroundStyle(CatalogActivity.launch.info.tintColor ?? .accentColor) // same as launchButton()
                                        .help(Text("The latest version of this app is installed", comment: "tooltip text for the checkmark in the apps list indicating that the app is currently updated to the latest version"))
                                } else {
                                    CatalogActivity.update.info.systemSymbol
                                        .foregroundStyle(CatalogActivity.update.info.tintColor ?? .accentColor) // same as updateButton()
                                        .help(Text("An update to this app is available", comment: "tooltip text for the checkmark in the apps list indicating that the app is currently installed but there is an update available"))
                                }
                            }
                        }
                        .frame(height: 12) // needed or else the icon height changes slightly (making the whole list stutter) whenever the symbol changes
                    }

                    if let versionDate = item.app.versionDate {
                        Text(versionDate, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            //.refreshingEveryMinute()
                            .font(.subheadline)
                    }

                }
                .lineLimit(1)
            }
            .allowsTightening(true)
        }
    }
}

struct AppItemLabel_Previews: PreviewProvider {
    static var previews: some View {
        //let info = AppInfo(catalogMetadata: AppCatalogItem(name: "My App", bundleIdentifier: "app.My-App", downloadURL: appfairRoot))
        //let info = AppInfo(app: AppCatalogItem.sample)

        ForEach([ColorScheme.light, .dark], id: \.self) { colorScheme in
            Text(verbatim: "XXX")
            //AppItemLabel(item: info, source: source)
        }
    }
}
