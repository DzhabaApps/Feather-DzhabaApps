import SwiftUI

struct FeatherAccessView: View {
    @ObservedObject var access: FeatherAccessManager
    var previewState: FeatherAccessState? = nil
    var previewExpiry: Date? = nil
    private var currentState: FeatherAccessState { previewState ?? access.state }
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: currentState == .expired ? "clock.badge.exclamationmark" : "wifi.exclamationmark")
                .font(.system(size: 52)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let expiry = previewExpiry ?? access.expiresAt {
                Text("Доступ до \(expiry.formatted(date: .numeric, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button { Task { await access.refresh(force: true) } } label: {
                if access.isChecking { ProgressView() } else { Text("Повторить проверку") }
            }.buttonStyle(.borderedProminent).disabled(access.isChecking)
            Link("Продлить доступ", destination: URL(string: "https://t.me/DzhabaApps_bot?start=renew")!)
                .buttonStyle(.bordered)
            Link("Связаться с поддержкой", destination: URL(string: "https://t.me/dzhabaraduev")!)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }
    private var title: String {
        switch currentState {
        case .expired: return "Срок доступа закончился"
        case .disabled: return "Доступ к этой сборке отключён"
        default: return "Не удалось подтвердить доступ"
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
