// SettingsView+Rows.swift
//
// Row-building helpers for `SettingsView`, split out of `SettingsView.swift`
// so the main struct body stays under SwiftLint's `type_body_length` cap.
// Each helper takes the concrete data a `SettingsRow` carries and returns
// the SwiftUI tree for that row.

import SwiftUI
import DesignSystem

extension SettingsView {

    @ViewBuilder
    func rowView(_ row: SettingsRow) -> some View {
        switch row {
        case .info(let id, let label, let value):
            infoRow(id: id, label: label, value: value)
        case .picker(let id, let label, let options, let selected, let onPick):
            pickerRow(id: id, label: label, options: options, selected: selected, onPick: onPick)
        case .toggle(let id, let label, let isOn, let onToggle):
            toggleRow(id: id, label: label, isOn: isOn, onToggle: onToggle)
        case .action(let id, let label, let destructive, let onTap):
            actionRow(id: id, label: label, destructive: destructive, onTap: onTap)
        }
    }

    func infoRow(id: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(label)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(DSTypography.mono)
                .monospacedDigit()
                .foregroundStyle(DSColors.foregroundMuted)
                .accessibilityIdentifier(id)
        }
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.xl)
        .accessibilityElement(children: .contain)
    }

    func pickerRow(
        id: String,
        label: String,
        options: [String],
        selected: String,
        onPick: @escaping @MainActor @Sendable (String) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.md) {
            Text(label)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(
                "",
                selection: Binding(
                    get: { selected },
                    set: { newValue in onPick(newValue) }
                )
            ) {
                ForEach(options, id: \.self) { option in
                    Text(option)
                        .font(DSTypography.mono)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier(id)
        }
        .padding(.vertical, DSSpacing.md)
        .padding(.horizontal, DSSpacing.xl)
        .accessibilityIdentifier("settings.row.\(id)")
    }

    func actionRow(
        id: String,
        label: String,
        destructive: Bool,
        onTap: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        Button(action: { onTap() }, label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                Text(label)
                    .font(DSTypography.body)
                    .foregroundStyle(destructive ? DSColors.accent : DSColors.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, DSSpacing.lg)
            .padding(.horizontal, DSSpacing.xl)
            .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    func toggleRow(
        id: String,
        label: String,
        isOn: Bool,
        onToggle: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> some View {
        SettingsToggleRow(
            id: id,
            label: label,
            isOn: isOn,
            onToggle: onToggle
        )
    }
}

private struct SettingsToggleRow: View {
    let id: String
    let label: String
    let isOn: Bool
    let onToggle: @MainActor @Sendable (Bool) -> Void

    init(
        id: String,
        label: String,
        isOn: Bool,
        onToggle: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.id = id
        self.label = label
        self.isOn = isOn
        self.onToggle = onToggle
    }

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { newValue in
                    onToggle(newValue)
                }
            ),
            label: {
                Text(label)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foreground)
            }
        )
        .toggleStyle(.switch)
        .padding(.vertical, DSSpacing.md)
        .padding(.horizontal, DSSpacing.xl)
        .accessibilityIdentifier(id)
    }
}
