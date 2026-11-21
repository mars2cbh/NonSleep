import NonSleepCore
import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdates
    let onClose: () -> Void

    @ObservedObject private var language = LanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("NonSleep Updates")).font(.system(size: 21, weight: .semibold))
                    Text(L10n.tr("Current version %@", updates.installedVersion))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 10) {
                    if updates.phase == .checking { ProgressView().controlSize(.small) }
                    else { Image(systemName: updates.candidate == nil ? "info.circle" : "arrow.down.circle.fill").foregroundStyle(.blue) }
                    Text(updates.statusText).font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let candidate = updates.candidate {
                    Text("\(updates.installedVersion) → \(candidate.version.description)")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Link(L10n.tr("View Changes on GitHub"), destination: candidate.releaseURL).font(.system(size: 12))
                }
                HStack {
                    Button(L10n.tr("Check for Updates")) { Task { await updates.checkNow() } }
                        .disabled(updates.isBusy)
                    if updates.candidate != nil {
                        Button(L10n.tr("Download and Install…"), action: updates.downloadAndInstall)
                            .buttonStyle(.borderedProminent).disabled(!updates.canInstall)
                    }
                }
                if let lastChecked = updates.lastChecked {
                    Text(L10n.tr("Last checked: %@", lastChecked.formatted(Date.FormatStyle(date: .numeric, time: .shortened).locale(language.locale))))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.tr("Automatically check for updates"), isOn: $updates.automaticallyChecks).toggleStyle(.switch)
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.tr("Check GitHub’s latest stable release at launch and every 6 hours while running. You choose when to install."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            .padding(18).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            Text(L10n.tr("Download the update for this Mac and verify its signature. The app restarts after installation."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Link(L10n.tr("View All Releases"), destination: URL(string: "https://github.com/mars2cbh/NonSleep/releases")!)
                .font(.system(size: 12))
            Spacer(minLength: 0)
            HStack {
                Text("CalVer · YYYY.MM.DD[.N]").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button(L10n.tr("Done"), action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
    }
}
