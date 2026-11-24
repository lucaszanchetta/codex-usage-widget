import SwiftUI
import WidgetKit
import AppKit
import CoreServices
import ServiceManagement

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(CompanionDelegate.self) private var companion
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { showMenuBarIcon }, set: { _ in })) {
            MenuBarContent(model: companion.model, openDetails: companion.openDetails)
        } label: {
            Label("Codex Usage", systemImage: "gauge.with.dots.needle.67percent")
        }
    }
}

@MainActor
final class CompanionDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var detailsWindow: NSWindow?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent {
            if event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
                || event.paramDescriptor(forKeyword: AEKeyword(kAEApplicationActivationExpected))?.booleanValue == false {
                return false
            }
        }
        openDetails()
        return false
    }

    func openDetails() {
        if detailsWindow == nil {
            let content = ContentView(model: model)
                .frame(minWidth: 360, minHeight: 300)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "Codex Usage"
            window.isReleasedWhenClosed = false
            window.center()
            detailsWindow = window
        }
        detailsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private let client = CodexRateLimitsClient()
    private let refreshInterval: TimeInterval = 15 * 60
    private var scheduledRefresh: Task<Void, Never>?

    init() {
        snapshot = UsageStore.load()
        let age = snapshot.map { Date().timeIntervalSince($0.fetchedAt) } ?? refreshInterval
        if age >= 0, age < refreshInterval {
            scheduleRefresh(after: refreshInterval - age)
        } else {
            refresh()
        }
    }

    deinit { scheduledRefresh?.cancel() }

    private func scheduleRefresh(after delay: TimeInterval) {
        scheduledRefresh = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay), tolerance: .seconds(30), clock: .continuous)
            } catch {
                return
            }
            self?.refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        isRefreshing = true
        errorMessage = nil
        Task {
            defer {
                isRefreshing = false
                scheduleRefresh(after: refreshInterval)
            }
            do {
                let value = try await client.fetch()
                snapshot = value
                do {
                    try UsageStore.save(value)
                    WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
                } catch {
                    errorMessage = "Usage refreshed, but the widget snapshot could not be saved. Storage: \(UsageStore.storageLocation). \(error.localizedDescription)"
                }
            }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    let openDetails: () -> Void

    var body: some View {
        if let limit = model.snapshot?.weeklyLimits.first {
            Text("Codex · \(limit.remainingPercent, specifier: "%.1f")% remaining").font(.headline)
            if let gap = limit.paceGap(at: Date()) {
                Text(UsageCalculator.formatPaceGap(gap))
                    .foregroundStyle(abs(gap) < 0.05 ? Color.primary : gap > 0 ? .green : .red)
            }
            Text(UsageCalculator.formatDuration(limit.secondsUntilReset(at: Date()))).foregroundStyle(.secondary)
            Divider()
        } else {
            Text("No usage snapshot yet").foregroundStyle(.secondary)
            Divider()
        }
        Button(model.isRefreshing ? "Refreshing…" : "Refresh") { model.refresh() }.disabled(model.isRefreshing)
        Button("Open Details…", action: openDetails)
        if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled },
            set: { enabled in
                let service = SMAppService.mainApp
                loginError = nil
                defer { loginStatus = service.status }
                do {
                    if enabled, service.status != .enabled {
                        try service.register()
                    } else if !enabled, service.status == .enabled {
                        try service.unregister()
                    }
                } catch {
                    loginError = error.localizedDescription
                }
            }
        )
    }

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Codex Usage", systemImage: "gauge.with.dots.needle.67percent").font(.title2.weight(.semibold)); Spacer()
                Button { model.refresh() } label: { Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise") }.disabled(model.isRefreshing).help("Refresh from Codex")
            }
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            Toggle("Launch at login", isOn: launchAtLogin)
            if loginStatus == .requiresApproval {
                Button("Manage Login Items in System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            if let limits = model.snapshot?.weeklyLimits, !limits.isEmpty {
                ForEach(limits) { limit in LimitCard(limit: limit, now: now) }
                if let snapshot = model.snapshot {
                    HStack(spacing: 5) {
                        if UsageCalculator.isStale(snapshot, at: now) { Image(systemName: "exclamationmark.triangle.fill"); Text("Stale snapshot") }
                        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    }.font(.caption).foregroundStyle(UsageCalculator.isStale(snapshot, at: now) ? .orange : .secondary)
                }
            } else { ContentUnavailableView("No usage yet", systemImage: "chart.bar.xaxis", description: Text("Refresh after signing in with the Codex CLI.")) }
            if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(20)
        .task {
            loginStatus = SMAppService.mainApp.status
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }
}

struct LimitCard: View {
    let limit: WeeklyLimit
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(limit.limitName).font(.headline); ProgressView(value: limit.usedPercent, total: 100).tint(limit.paceDelta(at: now) ?? 0 > 10 ? .orange : .accentColor)
            HStack { Text("\(limit.remainingPercent, specifier: "%.1f")% remaining"); Spacer(); Text(UsageCalculator.formatDuration(limit.secondsUntilReset(at: now))) }.font(.subheadline)
            if let gap = limit.paceGap(at: now) {
                Text("Pace gap: \(UsageCalculator.formatPaceGap(gap))")
                    .font(.caption)
                    .foregroundStyle(abs(gap) < 0.05 ? Color.primary : gap > 0 ? .green : .red)
            }
        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
