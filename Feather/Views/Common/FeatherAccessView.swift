import SwiftUI

struct FeatherAccessView: View {
    @ObservedObject var access: FeatherAccessManager
    var previewState: FeatherAccessState? = nil
    var previewExpiry: Date? = nil
    private var currentState: FeatherAccessState { previewState ?? access.state }
    private var waiting: Bool { previewState == nil && (access.isChecking || !access.hasChecked) }
    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: 20) {
            Image(systemName: currentState == .expired ? "clock.badge.exclamationmark" : "lock.shield")
                .font(.system(size: 52)).foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            if waiting {
                ProgressView()
                Text("Проверяем подписку…").font(.title2.bold())
            } else {
                Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if !waiting, let expiry = previewExpiry ?? access.expiresAt {
                Text(currentState == .expired ? "Срок истёк \(SubscriptionPresentation.expiry(expiry))" : "Подписка до \(SubscriptionPresentation.expiry(expiry))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !waiting {
                if currentState == .expired {
                    Link("Продлить подписку", destination: SubscriptionPresentation.renewalURL)
                        .buttonStyle(.borderedProminent)
                } else if currentState == .disabled {
                    Link("Открыть мою подписку", destination: SubscriptionPresentation.accountURL)
                        .buttonStyle(.borderedProminent)
                }
                Button(currentState == .expired ? "Проверить продление" : "Повторить проверку") {
                    Task { await access.refresh(force: true) }
                }
                .buttonStyle(.bordered)
                Link("Написать в поддержку", destination: SubscriptionPresentation.supportURL)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch currentState {
        case .expired: return "Подписка истекла"
        case .disabled: return "Установка отключена"
        default: return "Не удалось проверить подписку"
        }
    }
    private var message: String {
        switch currentState {
        case .expired: return "Продлите подписку, чтобы устанавливать и обновлять приложения. Ваша библиотека сохранена."
        case .disabled: return "Откройте «Моя подписка» на сайте и проверьте ссылку на установку для этого iPhone."
        default: return "Для проверки подключитесь к интернету. Если связь не восстановилась, повторите попытку позже."
        }
    }
}
