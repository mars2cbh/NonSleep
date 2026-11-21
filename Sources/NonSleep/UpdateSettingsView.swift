import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdates
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NonSleep 업데이트").font(.system(size: 21, weight: .semibold))
                    Text("현재 버전 \(updates.installedVersion)")
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
                    Link("GitHub에서 변경 사항 보기", destination: candidate.releaseURL).font(.system(size: 12))
                }
                HStack {
                    Button("업데이트 확인") { Task { await updates.checkNow() } }
                        .disabled(updates.isBusy)
                    if updates.candidate != nil {
                        Button("다운로드 및 설치…", action: updates.downloadAndInstall)
                            .buttonStyle(.borderedProminent).disabled(!updates.canInstall)
                    }
                }
                if let lastChecked = updates.lastChecked {
                    Text("마지막 확인: \(lastChecked.formatted(date: .numeric, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Toggle("자동으로 업데이트 확인", isOn: $updates.automaticallyChecks).toggleStyle(.switch)
                    .font(.system(size: 13, weight: .semibold))
                Text("앱 실행 시와 실행 중 6시간 간격으로 GitHub의 최신 정식 Release를 확인합니다. 설치는 직접 선택할 수 있습니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            .padding(18).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            Text("이 Mac에 맞는 설치 파일을 다운로드하고 전자서명을 확인합니다. 설치가 완료되면 앱이 자동으로 다시 시작됩니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Link("모든 Release 보기", destination: URL(string: "https://github.com/mars2cbh/NonSleep/releases")!)
                .font(.system(size: 12))
            Spacer(minLength: 0)
            HStack {
                Text("CalVer · YYYY.MM.DD[.N]").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("완료", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
    }
}
