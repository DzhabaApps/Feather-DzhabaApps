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
            Form {
                if isCreating {
                    Section("Название копии") {
                        TextField("Например, Рабочий WhatsApp", text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(create)
                        Text("\(name.count)/60").font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Создать и установить", action: create)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 || loadFailed)
                    } footer: {
                        Text("Копия установится отдельно. Для обновления выбирайте её название в этом же меню.")
                    }
                } else {
                    Section {
                        Button { installer.selectInstallation(request) } label: {
                            Label("Обычная установка", systemImage: "arrow.down.app")
                        }
                    } footer: {
                        Text("Установка с исходным идентификатором приложения. Если оно уже установлено, iOS попробует его обновить.")
                    }
                    if !copies.isEmpty {
                        Section {
                            ForEach(copies) { copy in
                                Button { installer.selectInstallation(request, copy: copy) } label: {
                                    Label("Обновить «\(copy.name)»", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .contextMenu {
                                    Button("Забыть копию", role: .destructive) { copyToForget = copy }
                                }
                                .swipeActions {
                                    Button("Забыть", role: .destructive) { copyToForget = copy }
                                }
                            }
                        } header: { Text("Ваши копии") } footer: {
                            Text("Выберите копию для установки скачанной версии. Если копия удалена с iPhone, она установится снова. Этот список сохраняется после очистки файлов Fizer.")
                        }
                    }
                    Section {
                        Button {
                            isCreating = true
                            nameFocused = true
                        } label: {
                            Label("Создать новую копию", systemImage: "plus.square.on.square")
                        }
                    } footer: {
                        Text("Копии занимают дополнительное место на iPhone. В отдельных приложениях вход, уведомления и другие функции могут работать иначе.")
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
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
                Text("Копия исчезнет из списка Fizer. Приложение и его данные на iPhone останутся. Её номер больше не будет использоваться для новых копий.")
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
