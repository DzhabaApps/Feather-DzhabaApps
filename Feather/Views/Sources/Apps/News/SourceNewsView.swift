import SwiftUI
import AltSourceKit

struct SourceNewsView: View {
    var news: [ASRepository.News]?
    @State private var selected: ASRepository.News?
    var body: some View {
        if let news, !news.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(news.reversed(), id: \.id) { item in
                        Button { selected = item } label: { SourceNewsCardView(new: item) }
                            .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }
            .frame(height: 150)
            .fullScreenCover(item: $selected) { SourceNewsCardInfoView(new: $0) }
        }
    }
}
