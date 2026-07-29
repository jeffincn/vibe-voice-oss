import SwiftUI

/// The debugging surface for a device that is not attached to a Mac.
///
/// A keyboard extension cannot show any of this: it has no settings screen, a
/// few hundred points of height, and a memory budget that does not stretch to a
/// log viewer. So the containing app owns the switches and the reader, and both
/// processes write to the same App Group directory.
struct DiagnosticsView: View {
    private static let visibleEventLimit = 250

    @State private var channelLabel = DiagnosticSettings.channelLabel ?? ""
    @State private var isVerbose = DiagnosticSettings.isVerbose
    @State private var verifiesInsertion = DiagnosticSettings.verifiesInsertion
    @State private var events: [DiagnosticEvent] = []
    @State private var didCopy = false

    var body: some View {
        List {
            channelSection
            switchesSection
            environmentSection
            eventsSection
        }
        .navigationTitle(MobileL10n.t(.diagnosticsTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(MobileL10n.t(.diagnosticsRefresh)) { reload() }
                    .accessibilityIdentifier("diagnostics.refresh")
            }
        }
        .onAppear(perform: reload)
    }

    private var channelSection: some View {
        Section {
            TextField(MobileL10n.t(.diagnosticsChannelPlaceholder), text: $channelLabel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("diagnostics.channel")
                .onChange(of: channelLabel) { _, new in
                    DiagnosticSettings.channelLabel = new
                }
        } header: {
            Text(MobileL10n.t(.diagnosticsChannelTitle))
        } footer: {
            Text(MobileL10n.t(.diagnosticsChannelHelp))
        }
    }

    private var switchesSection: some View {
        Section {
            Toggle(MobileL10n.t(.diagnosticsVerbose), isOn: $isVerbose)
                .accessibilityIdentifier("diagnostics.verbose")
                .onChange(of: isVerbose) { _, new in DiagnosticSettings.isVerbose = new }
            Toggle(MobileL10n.t(.diagnosticsVerifyInsertion), isOn: $verifiesInsertion)
                .accessibilityIdentifier("diagnostics.verifyInsertion")
                .onChange(of: verifiesInsertion) { _, new in
                    DiagnosticSettings.verifiesInsertion = new
                }
        } header: {
            Text(MobileL10n.t(.diagnosticsSwitchesTitle))
        } footer: {
            Text(MobileL10n.t(.diagnosticsSwitchesHelp))
        }
    }

    private var environmentSection: some View {
        Section {
            LabeledContent(
                MobileL10n.t(.diagnosticsStorage),
                value: DiagnosticStore.shared.storageDescription
            )
            LabeledContent(
                MobileL10n.t(.diagnosticsAppGroup),
                value: MobileL10n.t(isAppGroupReachable ? .diagnosticsReachable : .diagnosticsMissing)
            )
            LabeledContent(
                MobileL10n.t(.diagnosticsKeyboardSeen),
                value: keyboardLastSeen
            )
        } header: {
            Text(MobileL10n.t(.diagnosticsEnvironmentTitle))
        } footer: {
            Text(MobileL10n.t(.diagnosticsEnvironmentHelp))
        }
    }

    private var eventsSection: some View {
        Section {
            if events.isEmpty {
                Text(MobileL10n.t(.diagnosticsEmpty))
                    .foregroundStyle(.secondary)
            } else {
                // Newest first: the reason anyone opens this screen is whatever
                // just went wrong.
                ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, event in
                    eventRow(event)
                }
            }
        } header: {
            HStack {
                Text(MobileL10n.t(.diagnosticsEventsTitle))
                Spacer()
                Button(MobileL10n.t(didCopy ? .diagnosticsCopied : .diagnosticsCopy)) {
                    UIPasteboard.general.string = DiagnosticStore.shared.export()
                    didCopy = true
                }
                .accessibilityIdentifier("diagnostics.copy")
                Button(MobileL10n.t(.diagnosticsClear), role: .destructive) {
                    DiagnosticStore.shared.clear()
                    reload()
                }
                .accessibilityIdentifier("diagnostics.clear")
            }
            .textCase(nil)
        }
    }

    private func eventRow(_ event: DiagnosticEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(event.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(event.level == .error ? Color.red : Color.primary)
                Text("\(event.process.rawValue)/\(event.area.rawValue)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let channel = event.channel {
                    Text(channel)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            Text(event.fieldSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var isAppGroupReachable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DiagnosticSettings.appGroupID
        ) != nil
    }

    /// Whether the keyboard extension has ever written to the shared log. If it
    /// has not, no amount of reading this screen will explain a keyboard bug —
    /// the extension is either not enabled or not reaching the App Group.
    private var keyboardLastSeen: String {
        guard let latest = events.last(where: { $0.process == .keyboard }) else {
            return MobileL10n.t(.diagnosticsNever)
        }
        return latest.timestamp.formatted(date: .omitted, time: .standard)
    }

    private func reload() {
        events = DiagnosticStore.shared.recentEvents(limit: Self.visibleEventLimit)
        didCopy = false
    }
}
