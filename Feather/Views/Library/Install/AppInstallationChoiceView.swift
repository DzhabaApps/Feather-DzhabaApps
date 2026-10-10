import SwiftUI

struct AppInstallationChoiceView: View {
    let request: AppInstallRequest
    @ObservedObject var installer: RepositoryInstallCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var copies: [AppCopy] = []
    @State private var name = ""
    @State private var isCreating = false
    @State private var loadFailed = false
    @State private var message: String?
    @State private var copyToForget: AppCopy?
    @FocusState private var nameFocused: Bool

    init(request: AppInstallRequest, installer: RepositoryInstallCoordinator, creating: Bool = false) {
        self.request = request
        self.installer = installer
        _isCreating = State(initialValue: creating)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        FRAppIconView(app: request.app, size: 80)
                        Text(request.originalName).font(.title2.bold()).multilineTextAlignment(.center)
                        Text("Версия \(request.app.version ?? "Неизвестна")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 16)
                    if isCreating {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Название копии").font(.headline)
                            TextField("Например, Рабочий WhatsApp", text: $name)
                                .textFieldStyle(.roundedBorder).focused($nameFocused)
                                .submitLabel(.done).onSubmit(create)
                            Text("Отдельное приложение со своим названием. Позже вы сможете обновить его здесь.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(action: create) {
                            Text("Создать и установить").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60)
                    } else {
                        Button { installer.selectInstallation(request) } label: {
                            Label("Установить приложение", systemImage: "arrow.down.app.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        Button {
                            isCreating = true
                            nameFocused = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "plus.square.on.square").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Создать копию").font(.headline)
                                    Text("Отдельное приложение со своим названием")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote)
                            }.padding(16).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                        if !copies.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ваши копии").font(.headline)
                                VStack(spacing: 0) {
                                    ForEach(copies) { copy in
                                        HStack(spacing: 12) {
                                            Image(systemName: "square.on.square").foregroundStyle(Color.accentColor)
                                            Text(copy.name).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                                            Button("Обновить") { installer.selectInstallation(request, copy: copy) }
                                                .font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
                                        }.padding(14)
                                        .contextMenu {
                                            Button("Забыть копию", role: .destructive) { copyToForget = copy }
                                        }
                                        if copy.id != copies.last?.id { Divider().padding(.leading, 14) }
                                    }
                                }.background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                Text("Обновление установит скачанную версию в выбранную копию.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Text("В копиях некоторые функции приложения могут быть недоступны.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                }.padding(24)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .disabled(loadFailed)
            .navigationTitle(isCreating ? "Новая копия" : "Установка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isCreating ? "Назад" : "Отмена") {
                        if isCreating { isCreating = false; message = nil } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack {
                        Text(isCreating ? "Новая копия" : "Установка").font(.headline)
                        Text(request.originalName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Забыть «\(copyToForget?.name ?? "")»?", isPresented: Binding(
                get: { copyToForget != nil }, set: { if !$0 { copyToForget = nil } }
            ), titleVisibility: .visible) {
                if let copy = copyToForget {
                    Button("Забыть копию", role: .destructive) {
                        do { try installer.copies.forget(copy); load() }
                        catch { message = "Не удалось сохранить список копий. Попробуйте снова." }
                        copyToForget = nil
                    }
                }
            } message: {
                Text("Копия исчезнет из списка DR Store. Приложение и его данные на iPhone останутся. Её номер больше не будет использоваться для новых копий.")
            }
        }
    }

    private func load() {
        do {
            copies = try installer.copies.copies(for: request.originalIdentifier)
            let number = try installer.copies.nextNumber(for: request.originalIdentifier)
            name = String(request.originalName.prefix(40)) + " — копия \(number)"
            loadFailed = false
        } catch {
            loadFailed = true
            message = "Не удалось прочитать список копий. Обратитесь в поддержку."
        }
    }

    private func create() {
        guard !loadFailed else { return }
        do {
            let copy = try installer.createCopy(request, name: name)
            installer.selectInstallation(request, copy: copy)
        } catch {
            message = (error as? AppCopyStore.CopyError)?.errorDescription ?? "Не удалось сохранить копию. Попробуйте снова."
        }
    }
}
