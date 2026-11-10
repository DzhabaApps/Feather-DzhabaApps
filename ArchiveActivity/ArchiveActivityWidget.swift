import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ArchiveActivityWidget: Widget {
    private let url = URL(string: "feather://gta-download")
    private let accent = Color(red: 0.48, green: 0.40, blue: 0.91)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ArchiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("DR Store", systemImage: "arrow.down.circle.fill").foregroundStyle(accent)
                    Spacer()
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }.font(.subheadline.weight(.semibold))
                Text(context.attributes.title).font(.headline).lineLimit(1)
                ProgressView(value: context.state.fraction).tint(accent)
                Text(detail(context)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(14)
            .widgetURL(url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("DR Store", systemImage: "arrow.down.circle.fill").foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.attributes.title).lineLimit(1)
                        ProgressView(value: context.state.fraction).tint(accent)
                        Text(detail(context)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            } minimal: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
            }
            .widgetURL(url)
        }
    }

    private func detail(_ context: ActivityViewContext<ArchiveActivityAttributes>) -> String {
        switch context.state.phase {
        case .ready: return "Готово к сохранению"
        case .paused: return "Загрузка остановлена · " + context.state.bytes
        case .downloading:
            return context.isStale ? "Последний прогресс · " + context.state.bytes : context.state.bytes
        }
    }
}
