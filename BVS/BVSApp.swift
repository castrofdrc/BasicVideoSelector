import SwiftUI
import AppKit
import AVFoundation
import Carbon

@main
struct BVSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct Match: Identifiable {
    let url: URL
    var category: String? = nil
    var id: URL { url }
}

private final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()
    private let defaultsKey = "BVS.permanentCategories"

    @Published private(set) var permanentCategories: [String]
    @Published private(set) var temporaryCategories: [String] = []
    @Published var selectedCategory: String?

    var categories: [String] {
        (permanentCategories + temporaryCategories)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private init() {
        permanentCategories = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        selectedCategory = nil
    }

    func isPermanent(_ category: String) -> Bool {
        permanentCategories.contains(category)
    }

    func add(_ category: String, permanent: Bool) {
        guard !categories.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) else { return }
        if permanent {
            permanentCategories.append(category)
            savePermanentCategories()
        } else {
            temporaryCategories.append(category)
        }
    }

    func remove(_ category: String) {
        permanentCategories.removeAll { $0 == category }
        temporaryCategories.removeAll { $0 == category }
        if selectedCategory == category { selectedCategory = nil }
        savePermanentCategories()
    }

    private func savePermanentCategories() {
        UserDefaults.standard.set(permanentCategories, forKey: defaultsKey)
    }
}

private struct CategoryManagerView: View {
    @ObservedObject var store: CategoryStore
    let onRemove: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var categoryName = ""
    @State private var isPermanent = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crea categorías antes de revisar los videos. Las temporales solo están disponibles durante esta sesión; las permanentes se conservan para las próximas. Al cerrar BVS se olvidan las temporales, pero los archivos ya procesados permanecen en su carpeta.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Nombre, por ejemplo Zorros", text: $categoryName)
                    .textFieldStyle(.roundedBorder)
                Toggle("Permanente", isOn: $isPermanent)
                    .toggleStyle(.checkbox)
                Button("Crear", action: createCategory)
                    .buttonStyle(.borderedProminent)
            }

            if let validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.red)
            }

            if store.categories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus").font(.title2).foregroundStyle(.tertiary)
                    Text("Todavía no hay categorías").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                List(store.categories, id: \.self) { category in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        Text(category)
                        Text(store.isPermanent(category) ? "Permanente" : "Temporal")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.remove(category)
                            onRemove(category)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Quitar categoría (no elimina archivos ya procesados)")
                    }
                }
                .frame(minHeight: 130, maxHeight: 230)
            }

            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func createCategory() {
        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            validationMessage = "Escribe un nombre para la categoría."
            return
        }
        guard name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains(where: \.isNewline) else {
            validationMessage = "El nombre no puede incluir separadores de carpeta."
            return
        }
        guard !store.categories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            validationMessage = "Ya existe una categoría con ese nombre."
            return
        }
        store.add(name, permanent: isPermanent)
        categoryName = ""
        validationMessage = nil
    }
}

private enum DestinationMode: String, CaseIterable, Identifiable {
    case workFolder
    case otherFolder

    var id: String { rawValue }
}

private enum VideoConverter {
    private enum ConversionError: LocalizedError {
        case incompatible
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .incompatible:
                return "macOS no puede convertir este formato a MP4."
            case .exportFailed(let detail):
                return "Falló la conversión: \(detail)"
            }
        }
    }

    static func containsVideoTrack(at url: URL) async throws -> Bool {
        try await AVURLAsset(url: url).loadTracks(withMediaType: .video).isEmpty == false
    }

    static func convertToMP4(source: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let compatible = await withCheckedContinuation { continuation in
            AVAssetExportSession.determineCompatibility(
                ofExportPreset: AVAssetExportPresetHighestQuality,
                with: asset,
                outputFileType: .mp4
            ) { compatible in
                continuation.resume(returning: compatible)
            }
        }
        guard compatible,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.incompatible
        }

        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                if session.status == .completed {
                    continuation.resume()
                } else {
                    let detail = session.error?.localizedDescription ?? "Error desconocido."
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: ConversionError.exportFailed(detail))
                }
            }
        }
    }
}

private final class VLCNowPlayingMonitor: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var status = "Conectando con VLC…"

    private let queue = DispatchQueue(label: "com.bvs.vlc-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "org.videolan.vlc").isEmpty else {
            update(url: nil, status: "Abre VLC y reproduce un video.")
            return
        }
        let source = "tell application id \"org.videolan.vlc\" to get path of current item"
        guard let appleScript = NSAppleScript(source: source) else {
            update(url: nil, status: "No se pudo preparar la conexión con VLC.")
            return
        }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            if errorNumber == -1743 {
                update(url: nil, status: "Permite que BVS controle VLC en Privacidad y seguridad → Automatización.")
            } else if errorNumber == -1728 {
                update(url: nil, status: "No hay un video seleccionado en VLC.")
            } else {
                update(url: nil, status: "No se pudo leer el video actual de VLC.")
            }
            return
        }

        guard let value = result.stringValue, !value.isEmpty else {
            update(url: nil, status: "No hay un video seleccionado en VLC.")
            return
        }
        let url: URL
        if let parsed = URL(string: value), parsed.isFileURL {
            url = parsed.standardizedFileURL
        } else if value.hasPrefix("/") || value.hasPrefix("~") {
            url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
        } else {
            update(url: nil, status: "El elemento actual de VLC no es un archivo local.")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            update(url: nil, status: "No se encontró el archivo que VLC está reproduciendo.")
            return
        }
        update(url: url, status: "Video actual de VLC")
    }

    private func update(url: URL?, status: String) {
        DispatchQueue.main.async {
            self.currentURL = url
            self.status = status
        }
    }
}

private func bvsHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var pressedHotKey = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedHotKey
    )
    guard status == noErr, pressedHotKey.id == 1 else { return OSStatus(eventNotHandledErr) }
    Unmanaged<VLCShortcutController>.fromOpaque(userData).takeUnretainedValue().shortcutPressed()
    return noErr
}

private final class VLCShortcutController: ObservableObject {
    static let shared = VLCShortcutController()

    @Published private(set) var registrationError: String?
    @Published private(set) var isRegisteredForVLC = false
    @Published private(set) var lastAddedURL: URL?
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var activationObserver: NSObjectProtocol?
    private var frontmostTimer: Timer?
    private var onSelect: ((URL) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var isQuerying = false

    func markAdded(_ url: URL) {
        lastAddedURL = url.standardizedFileURL
    }

    func forgetAdded(_ url: URL) {
        if lastAddedURL?.standardizedFileURL == url.standardizedFileURL {
            lastAddedURL = nil
        }
    }

    func start(onSelect: @escaping (URL) -> Void, onFailure: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self.onFailure = onFailure
        guard activationObserver == nil else {
            updateRegistration(isVLCActive: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "org.videolan.vlc")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            bvsHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else {
            registrationError = "No se pudo iniciar el atajo de teclado (\(installStatus))."
            return
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateRegistration(isVLCActive: application?.bundleIdentifier == "org.videolan.vlc")
        }
        frontmostTimer?.invalidate()
        frontmostTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            let isVLCActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "org.videolan.vlc"
            self?.updateRegistration(isVLCActive: isVLCActive)
        }
        updateRegistration(isVLCActive: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "org.videolan.vlc")
    }

    private func updateRegistration(isVLCActive: Bool) {
        if isVLCActive, hotKey == nil, eventHandler != nil, registrationError == nil {
            let hotKeyID = EventHotKeyID(signature: OSType(0x42565331), id: 1)
            let modifiers = UInt32(controlKey | optionKey | cmdKey)
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_S),
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            if status == noErr {
                registrationError = nil
                isRegisteredForVLC = true
            } else {
                hotKey = nil
                isRegisteredForVLC = false
                registrationError = "No se pudo registrar ⌃⌥⌘S (\(status))."
            }
        } else if !isVLCActive, let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
            isRegisteredForVLC = false
        } else if !isVLCActive, eventHandler != nil {
            registrationError = nil
        }
    }

    func shortcutPressed() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.isQuerying else { return }
            self.isQuerying = true
            DispatchQueue.global(qos: .userInitiated).async {
                let (url, errorMessage) = Self.currentVLCFile()
                DispatchQueue.main.async {
                    self.isQuerying = false
                    if let url {
                        self.onSelect?(url)
                    } else if let errorMessage {
                        self.onFailure?(errorMessage)
                    }
                }
            }
        }
    }

    private static func currentVLCFile() -> (URL?, String?) {
        let source = "tell application id \"org.videolan.vlc\" to get path of current item"
        guard let appleScript = NSAppleScript(source: source) else { return (nil, "No se pudo consultar el video actual de VLC.") }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            return (nil, number == -1728 ? "No hay un video activo en VLC." : "No se pudo consultar el video actual de VLC.")
        }
        guard let value = result.stringValue, !value.isEmpty else { return (nil, "No hay un video activo en VLC.") }
        let url: URL
        if let parsed = URL(string: value), parsed.isFileURL {
            url = parsed.standardizedFileURL
        } else if value.hasPrefix("/") || value.hasPrefix("~") {
            url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
        } else {
            return (nil, "El elemento actual de VLC no es un archivo local.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, "No se encontró el archivo actual de VLC.") }
        return (url, nil)
    }
}

private struct VLCCompanionView: View {
    @StateObject private var monitor = VLCNowPlayingMonitor()
    @ObservedObject private var shortcutController = VLCShortcutController.shared
    @ObservedObject private var categoryStore = CategoryStore.shared
    let onAdd: (URL) -> Void

    private var currentVideoWasAdded: Bool {
        guard let currentURL = monitor.currentURL,
              let lastAddedURL = shortcutController.lastAddedURL else { return false }
        return currentURL.standardizedFileURL == lastAddedURL.standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.tint).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BVS · VLC").font(.headline)
                    Text(monitor.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Divider()
            if let url = monitor.currentURL {
                HStack(spacing: 8) {
                    Label("Categoría", systemImage: "folder")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Categoría", selection: $categoryStore.selectedCategory) {
                        Text("Sin categoría").tag(Optional<String>.none)
                        ForEach(categoryStore.categories, id: \.self) { category in
                            Text(category).tag(Optional(category))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(url.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
                Button {
                    onAdd(url)
                } label: {
                    Label(currentVideoWasAdded ? "Añadido a la selección" : "Guardar este video", systemImage: currentVideoWasAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(currentVideoWasAdded ? Color.green : Color.accentColor)
                }
                .buttonStyle(.bordered)
            } else {
                Label("Reproduce un archivo local en VLC para añadirlo aquí.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(shortcutController.registrationError ?? (shortcutController.isRegisteredForVLC ? "Atajo ⌃⌥⌘S listo. La categoría elegida se aplica a los próximos videos." : "Atajo ⌃⌥⌘S activo solo mientras VLC está al frente."))
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 340, height: 270)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

struct ContentView: View {
    @StateObject private var shortcutController = VLCShortcutController.shared
    @StateObject private var categoryStore = CategoryStore.shared
    @State private var folderURL: URL?
    @State private var input = ""
    @State private var matches: [Match] = []
    @State private var message: String?
    @State private var alertText: String?
    @State private var copiedCount = 0
    @State private var skippedCount = 0
    @State private var isCopying = false
    @State private var copyProgress = 0
    @State private var convertVideos = false
    @State private var companionWindow: NSPanel?
    @State private var showCategoryManager = false
    @State private var destinationMode: DestinationMode = .workFolder
    @State private var customDestinationURL: URL?

    private var outputParentURL: URL? {
        destinationMode == .workFolder ? folderURL : customDestinationURL
    }

    private var tokens: [String] {
        input.split { $0.isWhitespace || $0 == "," }
            .map(String.init)
    }

    private var canSearch: Bool { folderURL != nil && !tokens.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    folderSection
                    categorySection
                    numberSection
                    resultsSection
                    destinationSection
                }
                .padding(28)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(nil)
        .alert("BVS", isPresented: Binding(
            get: { alertText != nil }, set: { if !$0 { alertText = nil } }
        )) {
            Button("OK", role: .cancel) { alertText = nil }
        } message: {
            Text(alertText ?? "")
        }
        .onAppear {
            shortcutController.start(onSelect: addVLCVideo) { error in
                message = error
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerView(store: categoryStore, onRemove: categoryRemoved)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("BVS").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Basic Video Selector").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("SELECCIÓN POR TERMINACIÓN")
                .font(.caption2.weight(.semibold)).tracking(1.1)
                .foregroundStyle(.tertiary)
            Text(shortcutController.registrationError != nil ? "Atajo no disponible" : (shortcutController.isRegisteredForVLC ? "Atajo listo" : "⌃⌥⌘S"))
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .help(shortcutController.registrationError ?? "Atajo activo solo mientras VLC está en primer plano.")
            Button(action: openVLCCompanion) {
                Label("Ventana VLC", systemImage: "pip")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
        .background(.bar)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("1", "Carpeta de trabajo", detail: "La búsqueda se limita a esta carpeta. Los videos añadidos desde VLC también se guardan aquí.")
            HStack(spacing: 12) {
                Image(systemName: folderURL == nil ? "folder" : "folder.fill")
                    .font(.title2).foregroundStyle(.tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(folderURL?.lastPathComponent ?? "Ninguna carpeta seleccionada")
                        .fontWeight(.medium).lineLimit(1)
                    Text(folderURL?.path ?? "Elige la carpeta que contiene tus archivos")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Elegir carpeta…", action: chooseFolder)
                    .buttonStyle(.bordered)
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Categoría para próximos videos", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Picker("Categoría", selection: $categoryStore.selectedCategory) {
                    Text("Sin categoría").tag(Optional<String>.none)
                    ForEach(categoryStore.categories, id: \.self) { category in
                        Text(category).tag(Optional(category))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Button("Gestionar categorías…") { showCategoryManager = true }
                    .buttonStyle(.bordered)
            }
            Text("La categoría se guarda con cada video que añadas y permanece seleccionada hasta que la cambies.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("↗", "Destino", detail: "BVS creará la carpeta Seleccionados en la ubicación elegida.")
            HStack(spacing: 12) {
                Picker("Ubicación de Seleccionados", selection: $destinationMode) {
                    Text("Dentro de la carpeta de trabajo").tag(DestinationMode.workFolder)
                    Text("En otra ubicación…").tag(DestinationMode.otherFolder)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: destinationMode) { mode in
                    if mode == .otherFolder, customDestinationURL == nil {
                        chooseDestinationFolder()
                    }
                }
                Spacer()
                if destinationMode == .otherFolder {
                    Text(customDestinationURL?.path ?? "Elige una carpeta")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button("Elegir…", action: chooseDestinationFolder)
                        .buttonStyle(.bordered)
                }
            }
            .padding(13)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    private var numberSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("2", "Cifras finales", detail: "Pega números separados por espacios, comas o saltos de línea. Se aceptan longitudes variables.")
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(9)
                .frame(height: 112)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Ej.: 171, 14, 3")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary).padding(.leading, 14).padding(.top, 17)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            HStack {
                Label("Cada número debe coincidir con el final exacto del nombre, sin extensión.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: search) {
                    Label("Buscar coincidencias", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("3", "Vista previa", detail: "Revisa los archivos antes de copiarlos.")
                Spacer()
                if folderURL != nil {
                    Text("\(matches.count) \(matches.count == 1 ? "archivo" : "archivos")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Group {
                if matches.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 27)).foregroundStyle(.tertiary)
                        Text(folderURL == nil ? "Selecciona una carpeta o añade un video desde VLC" : "Los resultados y videos añadidos desde VLC aparecerán aquí")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 115)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(matches) { match in
                                HStack(spacing: 11) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: match.url.path))
                                        .resizable().frame(width: 26, height: 26)
                                    Text(match.url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Text(match.category ?? "SIN CATEGORÍA")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(match.category == nil ? Color.secondary : Color.accentColor)
                                        .lineLimit(1)
                                    Text(match.url.pathExtension.isEmpty ? "ARCHIVO" : match.url.pathExtension.uppercased())
                                        .font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                                    Button {
                                        shortcutController.forgetAdded(match.url)
                                        matches.removeAll { $0.url.standardizedFileURL == match.url.standardizedFileURL }
                                        message = "Archivo quitado de la selección."
                                    } label: {
                                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Quitar de la selección")
                                }
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                if match.id != matches.last?.id { Divider().padding(.leading, 50) }
                            }
                        }
                    }
                    .frame(maxHeight: 210)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            if let message {
                HStack {
                    Label(message, systemImage: isCopying ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(isCopying ? Color.secondary : Color.green)
                    Spacer()
                    if !isCopying, let outputParentURL {
                        Button("Mostrar en Finder") {
                            NSWorkspace.shared.open(outputParentURL.appendingPathComponent("Seleccionados", isDirectory: true))
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            Toggle("Convertir videos compatibles a MP4", isOn: $convertVideos)
                .toggleStyle(.checkbox)
                .disabled(isCopying)
            HStack {
                Text("Los originales permanecen intactos.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: copyMatches) {
                    if isCopying {
                        Label("Procesando \(copyProgress) de \(matches.count)…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label(convertVideos ? "Procesar a “Seleccionados”" : "Copiar a “Seleccionados”", systemImage: convertVideos ? "film" : "doc.on.doc.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(matches.isEmpty || isCopying || outputParentURL == nil)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background(.bar)
    }

    private func sectionTitle(_ number: String, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.weight(.bold)).foregroundStyle(.tint)
                .frame(width: 22, height: 22).background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona la carpeta de origen"
        panel.message = "BVS buscará archivos solo en esta carpeta."
        panel.prompt = "Seleccionar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            matches = []
            message = nil
        }
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = "Elige dónde crear Seleccionados"
        panel.message = "BVS creará la carpeta Seleccionados dentro de la ubicación elegida."
        panel.prompt = "Elegir ubicación"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customDestinationURL = url
        } else if customDestinationURL == nil {
            destinationMode = .workFolder
        }
    }

    private func categoryRemoved(_ category: String) {
        matches = matches.map { match in
            guard match.category == category else { return match }
            var updated = match
            updated.category = nil
            return updated
        }
    }

    private func openVLCCompanion() {
        if let companionWindow {
            companionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 270),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "BVS · VLC"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: VLCCompanionView(onAdd: addVLCVideo))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let margin: CGFloat = 28
            let xRange = (visible.minX + margin)...(visible.maxX - panel.frame.width - margin)
            let yRange = (visible.minY + margin)...(visible.maxY - panel.frame.height - margin)
            let desiredX = visible.minX + (visible.width - panel.frame.width) * 0.66
            let desiredY = visible.midY - panel.frame.height / 2
            let x = min(max(desiredX, xRange.lowerBound), xRange.upperBound)
            let y = min(max(desiredY, yRange.lowerBound), yRange.upperBound)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        companionWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addVLCVideo(_ url: URL) {
        guard !matches.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else {
            shortcutController.markAdded(url)
            message = "Este video ya está en la selección."
            return
        }
        if folderURL == nil {
            folderURL = url.deletingLastPathComponent()
        }
        matches.append(Match(url: url, category: categoryStore.selectedCategory))
        matches.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        shortcutController.markAdded(url)
        message = "Añadido desde VLC. Total en la selección: \(matches.count)."
    }

    private func search() {
        guard let folderURL else { return }
        let invalid = tokens.filter { !$0.allSatisfy(\.isNumber) }
        guard invalid.isEmpty else {
            alertText = "Usa solo cifras. Estas entradas no son válidas: \(invalid.joined(separator: ", "))"
            return
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [])
            matches = urls.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
                      values.isDirectory != true, values.isRegularFile != false else { return nil }
                let stem = url.deletingPathExtension().lastPathComponent
                return tokens.contains(where: { stem.hasSuffix($0) }) ? Match(url: url, category: categoryStore.selectedCategory) : nil
            }.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            message = nil
        } catch {
            alertText = "No se pudo leer la carpeta: \(error.localizedDescription)"
        }
    }

    private func copyMatches() {
        guard let outputParentURL else {
            alertText = "Elige la ubicación de la carpeta Seleccionados antes de procesar."
            return
        }
        let destinationRoot = outputParentURL.appendingPathComponent("Seleccionados", isDirectory: true)
        let selectedMatches = matches
        let shouldConvertVideos = convertVideos
        isCopying = true
        copyProgress = 0
        message = "Preparando archivos…"

        // File copies can take a long time for large videos, so keep them off the UI thread.
        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
                var copied = 0
                var converted = 0
                var skipped = 0
                var failures: [String] = []
                for (index, match) in selectedMatches.enumerated() {
                    let source = match.url
                    let progress = index + 1
                    DispatchQueue.main.async {
                        copyProgress = progress
                        message = "Procesando \(progress) de \(selectedMatches.count): \(source.lastPathComponent)"
                    }
                    do {
                        let destination = match.category.map {
                            destinationRoot.appendingPathComponent($0, isDirectory: true)
                        } ?? destinationRoot
                        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                        if shouldConvertVideos, try await VideoConverter.containsVideoTrack(at: source) {
                            let target = destination.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension("mp4")
                            guard !FileManager.default.fileExists(atPath: target.path) else {
                                skipped += 1
                                continue
                            }
                            try await VideoConverter.convertToMP4(source: source, destination: target)
                            converted += 1
                        } else {
                            let target = destination.appendingPathComponent(source.lastPathComponent)
                            guard !FileManager.default.fileExists(atPath: target.path) else {
                                skipped += 1
                                continue
                            }
                            try FileManager.default.copyItem(at: source, to: target)
                            copied += 1
                        }
                    } catch {
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                DispatchQueue.main.async {
                    copiedCount = copied
                    skippedCount = skipped
                    isCopying = false
                    message = "Convertidos: \(converted) · Copiados sin convertir: \(copied) · Omitidos: \(skipped)"
                    if !failures.isEmpty {
                        alertText = "Algunos archivos no pudieron procesarse. Los demás se completaron.\n\n" + failures.joined(separator: "\n")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isCopying = false
                    message = nil
                    alertText = "No se pudo crear la carpeta Seleccionados en la ubicación elegida: \(error.localizedDescription)"
                }
            }
        }
    }
}
