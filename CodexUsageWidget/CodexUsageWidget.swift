import SwiftUI
import WidgetKit

struct CodexUsageEntry: TimelineEntry { let date: Date; let snapshot: UsageSnapshot? }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CodexUsageEntry { CodexUsageEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) { completion(CodexUsageEntry(date: Date(), snapshot: UsageStore.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        let now = Date()
        let snapshot = UsageStore.load()
        let current = CodexUsageEntry(date: now, snapshot: snapshot)
        guard let snapshot else {
            completion(Timeline(entries: [current], policy: .never))
            return
        }

        let staleAt = snapshot.fetchedAt.addingTimeInterval(UsageCalculator.staleAfter + 1)
        guard let reset = snapshot.weeklyLimits.first?.resetsAt, reset > now else {
            let entries = staleAt > now
                ? [current, CodexUsageEntry(date: staleAt, snapshot: snapshot)]
                : [current]
            completion(Timeline(entries: entries, policy: .never))
            return
        }

        // The companion replaces this timeline after each successful fetch.
        // If it stops, show stale data and update the clock from cached values.
        let hour: TimeInterval = 60 * 60
        let fallback = min(reset, now.addingTimeInterval(6 * hour))
        var dates = [now]
        var next = now.addingTimeInterval(hour)
        if staleAt > now, staleAt < fallback {
            dates.append(staleAt)
            next = staleAt.addingTimeInterval(hour)
        }
        while next < fallback {
            dates.append(next)
            next = next.addingTimeInterval(hour)
        }
        let entries = dates.map { CodexUsageEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(fallback)))
    }
}

struct CodexUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexUsageEntry
    var body: some View {
        UsageDashboard(entry: entry, isWide: family == .systemMedium)
            .containerBackground(.background, for: .widget)
    }
}

struct UsageDashboard: View {
    let entry: CodexUsageEntry
    let isWide: Bool

    var body: some View {
        if let snapshot = entry.snapshot, let limit = snapshot.weeklyLimits.first {
            let stale = UsageCalculator.isStale(snapshot, at: entry.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Codex").font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Text("\(limit.remainingPercent, specifier: "%.1f")% left")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)

                Spacer(minLength: 0)
                if isWide {
                    HStack(spacing: 16) {
                        usageFigures(limit)
                            .frame(maxWidth: .infinity)
                        Divider().frame(height: 34)
                        paceSplit(limit)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    paceSplit(limit)
                    Spacer(minLength: 0)
                    usageFigures(limit)
                }
                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text(resetLabel(limit))
                    if isWide, let reset = limit.resetsAt {
                        Text("· \(reset, format: .dateTime.weekday(.abbreviated).hour().minute())")
                    }
                    Spacer(minLength: 0)
                    if stale {
                        Text("Stale").foregroundStyle(.orange)
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise.circle").font(.title2)
                Text("Open Codex Usage to refresh")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func usageFigures(_ limit: WeeklyLimit) -> some View {
        HStack(spacing: 8) {
            figure("Used", percent: limit.usedPercent)
                .frame(maxWidth: .infinity, alignment: .leading)
            figure("Target", percent: limit.expectedPercent(at: entry.date))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func figure(_ label: String, percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Group {
                if let percent {
                    Text("\(percent, specifier: "%.1f")%")
                } else {
                    Text("—").accessibilityLabel("Unavailable")
                }
            }
            .font(.system(size: isWide ? 25 : 19, weight: .semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func paceSplit(_ limit: WeeklyLimit) -> some View {
        if let gap = limit.paceGap(at: entry.date) {
            let visibleGap = abs(gap) < 0.05 ? 0 : gap
            let color: Color = visibleGap == 0 ? .primary : visibleGap < 0 ? .green : .red
            VStack(alignment: .leading, spacing: 2) {
                Text(UsageCalculator.formatPaceGap(gap))
                    .font(.system(size: isWide ? 22 : 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                    .accessibilityLabel("Pace split: \(UsageCalculator.formatPaceGap(gap))")
                PaceGapDiagram(gap: visibleGap, color: color)
                    .accessibilityHidden(true)
            }
        } else {
            Text("Pace unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resetLabel(_ limit: WeeklyLimit) -> String {
        guard let reset = limit.resetsAt else { return "Reset unavailable" }
        guard reset > entry.date else { return "Awaiting reset data" }
        return "Resets " + UsageCalculator.formatDuration(limit.secondsUntilReset(at: entry.date))
    }
}

private struct PaceGapDiagram: View {
    let gap: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            let width = min(half, max(2, half * abs(gap) / 100))
            ZStack {
                Capsule().fill(.quaternary).frame(height: 5)
                if gap != 0 {
                    Capsule().fill(color)
                        .frame(width: width, height: 5)
                        .offset(x: gap < 0 ? -width / 2 : width / 2)
                }
                Rectangle().fill(.primary).frame(width: 1.5, height: 11)
            }
        }
        .frame(height: 11)
    }
}

struct CodexUsageWidget: Widget {
    let kind = "CodexUsageWidget"
    var body: some WidgetConfiguration { StaticConfiguration(kind: kind, provider: Provider()) { entry in CodexUsageWidgetView(entry: entry) }.configurationDisplayName("Codex Usage").description("Weekly usage remaining, reset countdown, and pace gap.").supportedFamilies([.systemSmall, .systemMedium]) }
}

@main
struct CodexUsageWidgetBundle: WidgetBundle { var body: some Widget { CodexUsageWidget() } }

private extension UsageSnapshot {
    static var preview: UsageSnapshot { let reset = Date().addingTimeInterval(3 * 86_400); return UsageSnapshot(weeklyLimits: [WeeklyLimit(id: "preview", limitName: "Weekly", usedPercent: 32, remainingPercent: 68, resetsAt: reset, secondsUntilReset: 3 * 86_400, expectedPercent: 55, paceDelta: -23)]) }
}
