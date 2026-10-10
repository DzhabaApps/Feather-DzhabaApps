import SwiftUI

struct FeatherAccessView: View {
    @ObservedObject var access: FeatherAccessManager
    var previewState: FeatherAccessState? = nil
    var previewExpiry: Date? = nil
    private var currentState: FeatherAccessState { previewState ?? access.state }
    private var waiting: Bool { previewState == nil && (access.isChecking || !access.hasChecked) }
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: currentState == .expired ? "clock.badge.exclamationmark" : "leaf.fill")
                .font(.system(size: 52)).foregroundStyle(.secondary)
            if waiting {
                ProgressView()
                Text("Проверяем доступ…").font(.title2.bold())
            } else {
                Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if !waiting, let expiry = previewExpiry ?? access.expiresAt {
                Text("Доступ до \(SubscriptionPresentation.expiry(expiry))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !waiting {
            if currentState == .expired {
                Link("Продлить доступ", destination: URL(string: "https://t.me/DzhabaApps_bot?start=renew")!)
                    .buttonStyle(.borderedProminent)
            }
            Button { Task { await access.refresh(force: true) } } label: {
                if access.isChecking { ProgressView() } else { Text(currentState == .expired ? "Проверить продление" : "Повторить проверку") }
            }.buttonStyle(.bordered).disabled(access.isChecking)
            if currentState != .expired {
                Link("Продлить доступ", destination: URL(string: "https://t.me/DzhabaApps_bot?start=renew")!)
                    .buttonStyle(.bordered)
            }
            Link("Связаться с поддержкой", destination: URL(string: "https://t.me/dzhabaraduev")!)
            }
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }
    private var title: String {
        switch currentState {
        case .expired: return "Доступ закончился"
        case .disabled: return "Нужно восстановить приложение"
        default: return "Не удалось проверить доступ"
        }
    }
    private var message: String {
        switch currentState {
        case .expired: return "Продлите доступ, чтобы снова подписывать и устанавливать приложения. Ваша библиотека сохранена."
        case .disabled: return "Откройте актуальную ссылку в боте или обратитесь в поддержку."
        default: return "Для проверки подключитесь к интернету. Если связь не восстановилась, повторите попытку позже."
        }
    }
}
