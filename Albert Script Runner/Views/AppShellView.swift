import SwiftUI

private enum WorkspaceSidebarItem: String, CaseIterable, Identifiable {
    case locations
    case tokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .locations:
            return "Locations"
        case .tokens:
            return "Manage Saved Environments"
        }
    }

    var systemImage: String {
        switch self {
        case .locations:
            return "map"
        case .tokens:
            return "key"
        }
    }
}

struct AppShellView: View {
    @AppStorage("mainSidebarOpen") private var mainSidebarOpen: Bool = false
    @AppStorage("mainSidebarSelection") private var mainSidebarSelectionRaw: String = WorkspaceSidebarItem.locations.rawValue

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { mainSidebarOpen ? .doubleColumn : .detailOnly },
            set: { newValue in
                mainSidebarOpen = newValue != .detailOnly
            }
        )
    }

    private var sidebarSelection: Binding<WorkspaceSidebarItem?> {
        Binding(
            get: {
                WorkspaceSidebarItem(rawValue: mainSidebarSelectionRaw) ?? .locations
            },
            set: { newValue in
                mainSidebarSelectionRaw = (newValue ?? .locations).rawValue
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            List(selection: sidebarSelection) {
                ForEach(WorkspaceSidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Navigator")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ContentView()
        }
        .onAppear {
            if WorkspaceSidebarItem(rawValue: mainSidebarSelectionRaw) == nil {
                mainSidebarSelectionRaw = WorkspaceSidebarItem.locations.rawValue
            }
        }
    }
}
