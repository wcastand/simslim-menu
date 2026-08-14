import AppKit
import Combine
import SwiftUI

struct Simulator: Codable, Identifiable, Hashable {
    let udid: String
    let name: String
    let state: String
    let osVersion: String
    let set: String?
    let managedDisabled: Int?
    let managedTotal: Int
    let statusError: String?

    var id: String { udid }
    var isRunning: Bool { state.lowercased() != "shutdown" }
}

enum OptimizationState {
    case optimized
    case partial
    case notOptimized
    case unknown

    var title: String {
        switch self {
        case .optimized: "Optimized"
        case .partial: "Partially optimized"
        case .notOptimized: "Not optimized"
        case .unknown: "Optimization unknown"
        }
    }

    var icon: String {
        switch self {
        case .optimized: "bolt.fill"
        case .partial: "bolt.badge.clock.fill"
        case .notOptimized: "bolt.slash"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .optimized: .green
        case .partial: .orange
        case .notOptimized: .red
        case .unknown: .secondary
        }
    }
}

enum SimSlimError: LocalizedError {
    case notInstalled
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "simslim was not found. Install it with Homebrew, then refresh."
        case .commandFailed(let message):
            return message.isEmpty ? "simslim could not complete the command." : message
        }
    }
}

enum SimSlimClient {
    private static var executableURL: URL? {
        let candidates = [
            "/opt/homebrew/bin/simslim",
            "/usr/local/bin/simslim",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/simslim"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    static func list() throws -> [Simulator] {
        let data = try run(["list", "--json"])
        return try JSONDecoder().decode([Simulator].self, from: data)
    }

    static func shutdown(_ udid: String) throws {
        _ = try run(["shutdown", udid, "--json"])
    }

    private static func run(_ arguments: [String]) throws -> Data {
        guard let executableURL else { throw SimSlimError.notInstalled }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SimSlimError.commandFailed(message)
        }
        return outputData
    }
}

@MainActor
final class SimulatorStore: ObservableObject {
    @Published private(set) var simulators: [Simulator] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyIDs: Set<String> = []
    @Published var errorMessage: String?

    private var hasLoaded = false
    private var refreshInProgress = false
    private var refreshTimer: AnyCancellable?
    private var lastKnownDisabled: [String: Int] =
        UserDefaults.standard.dictionary(forKey: "lastKnownDisabled") as? [String: Int] ?? [:]

    var runningCount: Int { simulators.filter(\.isRunning).count }

    func optimizationState(for simulator: Simulator) -> OptimizationState {
        guard let disabled = simulator.managedDisabled ?? lastKnownDisabled[simulator.id] else {
            return .unknown
        }
        if disabled == 0 { return .notOptimized }
        if disabled >= simulator.managedTotal { return .optimized }
        return .partial
    }

    func load(showActivity: Bool = true) {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        if showActivity { isLoading = true }

        Task {
            do {
                let devices = try await Task.detached { try SimSlimClient.list() }.value
                simulators = devices.sorted {
                    if $0.isRunning != $1.isRunning { return $0.isRunning }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                for device in devices {
                    if let disabled = device.managedDisabled {
                        lastKnownDisabled[device.id] = disabled
                    }
                }
                UserDefaults.standard.set(lastKnownDisabled, forKey: "lastKnownDisabled")
                errorMessage = nil
                hasLoaded = true
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshInProgress = false
            if showActivity { isLoading = false }
        }
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.load(showActivity: false)
            }
    }

    func loadIfNeeded() {
        if !hasLoaded { load() }
    }

    func shutdown(_ simulator: Simulator) {
        guard simulator.isRunning, !busyIDs.contains(simulator.id) else { return }
        busyIDs.insert(simulator.id)

        Task {
            do {
                try await Task.detached { try SimSlimClient.shutdown(simulator.udid) }.value
                errorMessage = nil
                busyIDs.remove(simulator.id)
                load()
            } catch {
                busyIDs.remove(simulator.id)
                errorMessage = error.localizedDescription
            }
        }
    }
}

final class SimulatorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct PopoverShape: Shape {
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = 10
        let radius: CGFloat = 18
        let mid = rect.midX
        let bottom = rect.maxY
        var path = Path()

        path.move(to: CGPoint(x: radius, y: top))
        path.addLine(to: CGPoint(x: mid - 14, y: top))
        path.addQuadCurve(
            to: CGPoint(x: mid - 7, y: 6),
            control: CGPoint(x: mid - 10, y: top)
        )
        path.addLine(to: CGPoint(x: mid - 2, y: 1))
        path.addQuadCurve(
            to: CGPoint(x: mid + 2, y: 1),
            control: CGPoint(x: mid, y: -0.5)
        )
        path.addLine(to: CGPoint(x: mid + 7, y: 6))
        path.addQuadCurve(
            to: CGPoint(x: mid + 14, y: top),
            control: CGPoint(x: mid + 10, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: top + radius),
            control: CGPoint(x: rect.maxX, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: bottom),
            control: CGPoint(x: rect.maxX, y: bottom)
        )
        path.addLine(to: CGPoint(x: radius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: bottom - radius),
            control: CGPoint(x: 0, y: bottom)
        )
        path.addLine(to: CGPoint(x: 0, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: radius, y: top),
            control: CGPoint(x: 0, y: top)
        )
        path.closeSubpath()
        return path
    }
}

struct PopoverContainer: View {
    @ObservedObject var store: SimulatorStore

    var body: some View {
        SimulatorListView(store: store)
            .padding(.top, 10)
            .background {
                PopoverShape().fill(Color(nsColor: .windowBackgroundColor))
            }
            .overlay {
                PopoverShape()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SimulatorStore()
    private var statusItem: NSStatusItem?
    private var panel: SimulatorPanel?
    private var outsideClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePanel()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.panel?.orderOut(nil) }
        }
        store.$simulators
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.resizePanel(toFit: devices)
            }
            .store(in: &cancellables)
        store.load()
        store.startAutoRefresh()

        // Show the panel once at launch so it remains discoverable when a
        // menu-bar organizer places a new item in its hidden section.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showPanel()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "iOS Simulators")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "iOS Simulators · Right-click to quit"
        }
        statusItem = item
    }

    private func configurePanel() {
        let panel = SimulatorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 336),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: PopoverContainer(store: store)
                .frame(minWidth: 310, maxWidth: .infinity, minHeight: 336, maxHeight: 336)
        )
        self.panel = panel
    }

    @objc private func handleStatusItemClick() {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            NSApplication.shared.terminate(nil)
            return
        }

        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : showPanel()
    }

    private func showPanel() {
        guard let panel else { return }
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func resizePanel(toFit devices: [Simulator]) {
        guard let panel, !devices.isEmpty else { return }

        let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 11)
        let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

        let widestContent = devices.reduce(CGFloat(0)) { width, device in
            let name = (device.name as NSString).size(withAttributes: [.font: nameFont]).width
            let state = ((device.isRunning ? device.state : "Shutdown") as NSString)
                .size(withAttributes: [.font: badgeFont]).width + 18
            let optimization = store.optimizationState(for: device).title
            let detail = ("iOS \(device.osVersion)  ·  \(optimization)" as NSString)
                .size(withAttributes: [.font: detailFont]).width
            return max(width, max(name + state + 8, detail))
        }

        let desiredWidth = min(max(12 + 30 + 10 + widestContent + 12 + 24 + 12, 310), 390)
        guard abs(panel.frame.width - desiredWidth) > 1 else { return }
        var frame = panel.frame
        frame.origin.x += (frame.width - desiredWidth) / 2
        frame.size.width = desiredWidth
        panel.setFrame(frame, display: true)
        if panel.isVisible { positionPanel(panel) }
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let anchorX = statusItem?.button?.window?.frame.midX ?? visibleFrame.maxX - 24
        let x = min(
            max(anchorX - panel.frame.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panel.frame.width - 8
        )
        panel.setFrameOrigin(NSPoint(x: x, y: visibleFrame.maxY - panel.frame.height + 5))
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }
}

@main
struct SimSlimMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct SimulatorListView: View {
    @ObservedObject var store: SimulatorStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage = store.errorMessage, store.simulators.isEmpty {
                ContentUnavailableView(
                    "Unable to Load Simulators",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.simulators.isEmpty && store.isLoading {
                ProgressView("Loading simulators…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.simulators.isEmpty {
                ContentUnavailableView("No Simulators", systemImage: "iphone.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.simulators) { simulator in
                            SimulatorRow(
                                simulator: simulator,
                                optimizationState: store.optimizationState(for: simulator),
                                isBusy: store.busyIDs.contains(simulator.id),
                                shutdown: { store.shutdown(simulator) }
                            )
                            if simulator.id != store.simulators.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }

        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("iOS Simulators")
                    .font(.headline)
                Text("\(store.simulators.count) devices · \(store.runningCount) running")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }
}

struct SimulatorRow: View {
    let simulator: Simulator
    let optimizationState: OptimizationState
    let isBusy: Bool
    let shutdown: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(simulator.isRunning ? Color.red.opacity(0.10) : Color.secondary.opacity(0.10))
                    .frame(width: 30, height: 30)

                if simulator.isRunning {
                    Button(action: shutdown) {
                        if isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "power")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isBusy)
                    .help("Shut down simulator")
                } else {
                    Image(systemName: "iphone")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(simulator.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    StatusBadge(
                        title: simulator.isRunning ? simulator.state : "Shutdown",
                        color: simulator.isRunning ? .green : .secondary
                    )
                }

                HStack(spacing: 6) {
                    Text("iOS \(simulator.osVersion)")
                    Text("·")
                    Label(optimizationState.title, systemImage: optimizationState.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(optimizationState.color)
                        .help(optimizationHelp)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(simulator.udid, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? .green : .secondary)
            .help(copied ? "Copied" : "Copy UUID")

        }
        .padding(.horizontal, 12)
        .frame(minHeight: 55)
    }

    private var optimizationHelp: String {
        switch optimizationState {
        case .unknown:
            "simslim can read optimization state only while this simulator is running. The app remembers the latest observed state."
        case .partial:
            "Some, but not all, managed services are disabled."
        case .optimized:
            "All managed services are disabled."
        case .notOptimized:
            "No managed services are disabled."
        }
    }
}

struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
