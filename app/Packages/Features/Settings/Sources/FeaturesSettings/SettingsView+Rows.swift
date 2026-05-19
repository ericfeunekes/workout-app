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
        case .info(_, let label, let value):
            infoRow(label: label, value: value)
        case .picker(_, let label, let options, let selected, let onPick):
            pickerRow(label: label, options: options, selected: selected, onPick: onPick)
        case .toggle(_, let label, let isOn, let onToggle):
            toggleRow(label: label, isOn: isOn, onToggle: onToggle)
        case .action(_, let label, let destructive, let onTap):
            actionRow(label: label, destructive: destructive, onTap: onTap)
        }
    }

    func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(label)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(DSTypography.mono)
                .monospacedDigit()
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.xl)
    }

    func pickerRow(
        label: String,
        options: [String],
        selected: String,
        onPick: @escaping @Sendable (String) -> Void
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
        }
        .padding(.vertical, DSSpacing.md)
        .padding(.horizontal, DSSpacing.xl)
    }

    func actionRow(
        label: String,
        destructive: Bool,
        onTap: @escaping @Sendable () -> Void
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
    }

    func toggleRow(
        label: String,
        isOn: Bool,
        onToggle: @escaping @Sendable (Bool) -> Void
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { newValue in onToggle(newValue) }
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
    }
}
