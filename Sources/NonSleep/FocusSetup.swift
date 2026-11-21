import NonSleepCore
import SwiftUI

struct FocusSetup: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var language = LanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "moon.circle.fill").font(.system(size: 32)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Set Up Do Not Disturb")).font(.system(size: 20, weight: .semibold))
                    Text(L10n.tr("Use Apple Shortcuts to control macOS Focus."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                step("1", L10n.tr("Create two shortcuts in the Shortcuts app."),
                     L10n.tr("Add the “Set Focus” action to each and choose “Do Not Disturb.”"))
                step("2", L10n.tr("Set one to On and the other to Off."),
                     L10n.tr("Set the On shortcut to stay on “Until Turned Off.” Choose any names you like."))
                Button(L10n.tr("Open Shortcuts"), action: model.openShortcuts).padding(.leading, 28)
            }

            Divider()
            HStack {
                Text(L10n.tr("Connect Shortcuts")).font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.loadingShortcuts { ProgressView().controlSize(.small) }
                Button(L10n.tr("Refresh List")) { Task { await model.loadShortcuts() } }
                    .font(.system(size: 11)).disabled(model.loadingShortcuts)
            }
            VStack(spacing: 12) {
                shortcutPicker(L10n.tr("Run when turning on"), selection: $model.shortcutOn)
                shortcutPicker(L10n.tr("Run when turning off"), selection: $model.shortcutOff)
            }
            if model.shortcuts.isEmpty && !model.loadingShortcuts {
                Text(L10n.tr("Create your shortcuts, then refresh the list.")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !model.shortcutOn.isEmpty && model.shortcutOn == model.shortcutOff {
                Text(L10n.tr("Choose different shortcuts for On and Off.")).font(.system(size: 11)).foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.tr("To silence notifications"), systemImage: "bell.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.tr("In System Settings → Focus → Do Not Disturb, remove allowed people and apps, and turn off exceptions such as repeated calls and time-sensitive notifications. Some alerts follow macOS policies."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Button(L10n.tr("Open Focus Settings"), action: model.openFocusSettings).font(.system(size: 11))
            }
            .padding(14).background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            Text(L10n.tr("NonSleep only checks whether the selected shortcut ran successfully. It cannot verify the shortcut’s actions or the actual macOS Focus state."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.tr("Run Off Shortcut")) { Task { await model.setFocus(false) } }
                    .disabled(!model.focusConfigured || model.busy != nil)
                Spacer()
                Button(L10n.tr("Done")) {
                    if let onDone { onDone() } else { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 490)
        .task { await model.loadShortcuts() }
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 10, weight: .semibold))
                .frame(width: 19, height: 19).background(.primary.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcutPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text(L10n.tr("Choose a Shortcut…")).tag("")
            if !selection.wrappedValue.isEmpty && !model.shortcuts.contains(selection.wrappedValue) {
                Text(L10n.tr("%@ (not found in list)", selection.wrappedValue)).tag(selection.wrappedValue)
            }
            ForEach(model.shortcuts, id: \.self) { Text($0).tag($0) }
        }
        .font(.system(size: 12))
    }
}
