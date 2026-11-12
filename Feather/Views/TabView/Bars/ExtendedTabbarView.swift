import SwiftUI

@available(iOS 18, *)
struct ExtendedTabbarView: View {
    @AppStorage("DRStore.selectedTab") private var selectedTab: TabEnum = .sources
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(TabEnum.defaultTabs, id: \.rawValue) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) { TabEnum.view(for: tab) }
            }
        }
    }
}
