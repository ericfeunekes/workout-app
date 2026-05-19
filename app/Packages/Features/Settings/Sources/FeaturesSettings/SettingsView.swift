// SettingsView.swift
//
// The Settings screen. A single SwiftUI view that iterates the viewModel's
// `sections` → `rows` and renders the right DS primitive per case. The view
// holds no branching beyond the `switch` on `SettingsRow` — all logic lives
// on the viewModel.
//
// Layout mirrors `docs/design/components/meta.jsx` SettingsMain:
//   - background: DSColors.background, extends past the top safe area
//   - ScrollView in the middle
//   - each section is an ALL CAPS monospace kicker + a bordered card with
//     divider-separated rows inside
//
// Entry point: the brief lets me pick between editing `TodayView` (gear
// icon) or surfacing Settings as a sheet from a stub. The parallel
// sync-integration slice is actively rewriting `WorkoutDBApp.swift` so
// modifying TodayView risks a merge-time conflict. I go with the
// conservative route: expose `SettingsView` as the public surface and
// leave it to the shell to decide how to present it. A `presented` helper
// below wraps the view in a plain `NavigationStack` so the shell can
// `.sheet()` it in one line.

import SwiftUI
import DesignSystem

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            DSColors.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.xxl) {
                    ForEach(viewModel.sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xxl)
            }
        }
        .alert(
            viewModel.showDestructiveConfirm?.title ?? "",
            isPresented: Binding(
                get: { viewModel.showDestructiveConfirm != nil },
                set: { newValue in
                    if !newValue { viewModel.cancelDestructive() }
                }
            ),
            presenting: viewModel.showDestructiveConfirm,
            actions: { confirm in
                Button("cancel", role: .cancel) {
                    viewModel.cancelDestructive()
                }
                Button(confirm.title, role: .destructive) {
                    viewModel.confirmDestructive()
                }
            },
            message: { confirm in
                Text(confirm.message)
            }
        )
        .task {
            await viewModel.refreshAsync()
        }
    }

    // MARK: - Section + row rendering

    @ViewBuilder
    private func sectionView(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(section.title)
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)

            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            DSDivider()
                        }
                        rowView(row)
                    }
                }
            }
        }
    }

}

// Row-building helpers (`rowView`, `infoRow`, `pickerRow`, `actionRow`)
// live in `SettingsView+Rows.swift` so the main struct body stays under
// SwiftLint's `type_body_length` cap.

// MARK: - Previews

#if DEBUG
#Preview("Settings") {
    SettingsView(viewModel: SettingsViewModel(
        tokenStore: PreviewTokenStore(),
        autoregStore: PreviewAutoregStore(),
        unitsStore: PreviewUnitsStore(),
        syncMetadata: PreviewSyncMetadataStore(
            lastSyncAt: Date().addingTimeInterval(-240)
        ),
        buildInfo: BuildInfo(version: "0.0.1", build: "1", commit: "dev"),
        pairedWatchProvider: { nil }
    ))
    .preferredColorScheme(.dark)
}

private struct PreviewTokenStore: Persistence.TokenStore {
    func saveConnection(url: URL, token: String) throws {}
    func loadConnection() throws -> (url: URL, token: String)? {
        // Hardcoded syntactically valid URL — cannot fail at runtime.
        // swiftlint:disable:next force_unwrapping
        (URL(string: "https://wdb.local:8080")!, "t")
    }
    func clear() throws {}
}

private final class PreviewAutoregStore: AutoregDefaultsStore, @unchecked Sendable {
    func load() -> AutoregDefaults { AutoregDefaults() }
    func resetToDefaults() {}
}

private final class PreviewUnitsStore: UnitsPreferenceStore, @unchecked Sendable {
    private var value: UnitsPreference = .kg
    func load() -> UnitsPreference { value }
    func save(_ units: UnitsPreference) { value = units }
}

private struct PreviewSyncMetadataStore: Persistence.SyncMetadataStore {
    let lastSyncAt: Date?
    func getLastSyncAt() async -> Date? { lastSyncAt }
    func setLastSyncAt(_ date: Date) async {}
    func clearLastSyncAt() async {}
}

// Previews import Persistence implicitly via the TokenStore protocol;
// this avoids a separate file-level import for the preview block.
import Persistence
#endif
