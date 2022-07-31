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

#if os(macOS)
/// A container for a Table
@available(macOS 12.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
protocol ItemTableView : TableRowContent {
}


@available(macOS 12.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension ItemTableView {

    func dateColumn(named key: LocalizedStringKey, path: KeyPath<TableRowValue, Date?>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, Text, Text> {
        TableColumn(key, value: path, comparator: optionalDateComparator) { item in
            Text(verbatim: item[keyPath: path]?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")
            //Text(verbatim: item[keyPath: path].localizedDate(dateStyle: .short, timeStyle: .short))
        }
    }

    func numColumn<T: BinaryInteger>(named key: LocalizedStringKey, path: KeyPath<TableRowValue, T>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, Text, Text> {
        TableColumn(key, value: path, comparator: NumericComparator()) { item in
            Text(verbatim: item[keyPath: path].localizedNumber())
        }
    }

    func boolColumn(named key: LocalizedStringKey, path: KeyPath<TableRowValue, Bool>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, Toggle<EmptyView>, Text> {
        TableColumn(key, value: path, comparator: BoolComparator()) { item in
            Toggle(isOn: .constant(item[keyPath: path])) { EmptyView () }
        }
    }

    /// Non-optional string column
    func strColumn(named key: LocalizedStringKey, path: KeyPath<TableRowValue, String>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, Text, Text> {
        TableColumn(key, value: path, comparator: .localizedStandard) { item in
            Text(verbatim: item[keyPath: path])
        }
    }

    func ostrColumn(named key: LocalizedStringKey, path: KeyPath<TableRowValue, String?>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, Text, Text> {
        TableColumn(key, value: path, comparator: optionalStringComparator) { item in
            Text(verbatim: item[keyPath: path] ?? "")
        }
    }

    func oversionColumn(named key: LocalizedStringKey, path: KeyPath<TableRowValue, AppVersion?>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, VersionLabel, Text> {
        // TODO: we might want to disallow sorting on versions since it doesn't make sense to compare the versions of two different apps, and we want to discourage version inflation as a mechanism for rank boosting
        TableColumn(key, value: path, comparator: optionalComparator(AppVersion.min)) { item in
            VersionLabel(version: item[keyPath: path])
        }
    }

    func onumColumn<T: BinaryInteger>(named key: LocalizedStringKey, path: KeyPath<TableRowValue, T?>) -> TableColumn<TableRowValue, KeyPathComparator<TableRowValue>, AlignedText, Text> {
        TableColumn(key, value: path, comparator: optionalComparator(0)) { item in
            AlignedText(text: Text(verbatim: item[keyPath: path]?.localizedNumber() ?? ""), alignment: .trailing)
        }
    }
}

struct AlignedText : Equatable, View {
    let text: Text
    let alignment: TextAlignment

    var body: some View {
        text.multilineTextAlignment(alignment)
    }
}

/// The label that renders a version of an app
struct VersionLabel : Equatable, View {
    let version: AppVersion?

    var body: some View {
        Text(verbatim: version?.versionStringExtended ?? "-")
            .multilineTextAlignment(.trailing)
    }
}


extension SortComparator {
    func reorder(_ result: ComparisonResult) -> ComparisonResult {
        switch (order, result) {
        case (_, .orderedSame): return .orderedSame
        case (.forward, .orderedAscending): return .orderedAscending
        case (.reverse, .orderedAscending): return .orderedDescending
        case (.forward, .orderedDescending): return .orderedDescending
        case (.reverse, .orderedDescending): return .orderedAscending
        }
    }
}

struct BoolComparator : SortComparator {
    var order: SortOrder = SortOrder.forward

    func compare(_ lhs: Bool, _ rhs: Bool) -> ComparisonResult {
        switch (lhs, rhs) {
        case (true, true): return reorder(.orderedSame)
        case (false, false): return reorder(.orderedSame)
        case (true, false): return reorder(.orderedAscending)
        case (false, true): return reorder(.orderedAscending)
        }
    }
}

struct OptionalCompatator<T: Comparable & Hashable> : SortComparator {
    var order: SortOrder = SortOrder.forward

    let lhsDefault: T
    let rhsDefault: T

    func compare(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        lhs ?? lhsDefault < rhs ?? rhsDefault ? reorder(.orderedAscending)
        : lhs ?? lhsDefault > rhs ?? rhsDefault ? reorder(.orderedDescending)
        : .orderedSame
    }
}

let optionalDateComparator = OptionalCompatator(lhsDefault: Date.distantPast, rhsDefault: Date.distantFuture)

let optionalStringComparator = OptionalCompatator(lhsDefault: "", rhsDefault: "")

func optionalComparator<T: Hashable & Comparable>(_ value: T) -> OptionalCompatator<T> {
    OptionalCompatator(lhsDefault: value, rhsDefault: value)
}


struct URLComparator : SortComparator {
    var order: SortOrder = SortOrder.forward

    func compare(_ lhs: URL?, _ rhs: URL?) -> ComparisonResult {
        reorder((lhs?.absoluteString ?? "").compare(rhs?.absoluteString ?? ""))
    }
}

struct NumericComparator<N: Numeric & Comparable> : SortComparator {
    var order: SortOrder = SortOrder.forward

    func compare(_ lhs: N, _ rhs: N) -> ComparisonResult {
        lhs < rhs ? reorder(.orderedAscending) : lhs > rhs ? reorder(.orderedDescending) : .orderedSame
    }
}
#endif

