import SwiftUI

@available(iOS 18, *)
struct ExtendedTabbarView: View {
    var body: some View {
        TabView {
            ForEach(TabEnum.defaultTabs, id: \.rawValue) { tab in
                Tab(tab.title, systemImage: tab.icon) { TabEnum.view(for: tab) }
            }
        }
    }
}
