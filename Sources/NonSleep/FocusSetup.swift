import SwiftUI

struct FocusSetup: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "moon.circle.fill").font(.system(size: 32)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("방해 금지 연결").font(.system(size: 20, weight: .semibold))
                    Text("Apple 단축어로 macOS 집중 모드를 전환합니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                step("1", "단축어 앱에서 두 개를 만드세요.",
                     "‘집중 모드 설정’ 동작을 추가하고, 둘 다 ‘방해 금지’를 선택합니다.")
                step("2", "하나는 켜기, 다른 하나는 끄기로 설정하세요.",
                     "켜기 단축어는 ‘끔으로 설정할 때까지’ 유지하도록 설정합니다. 이름은 자유롭게 정해도 됩니다.")
                Button("단축어 앱 열기", action: model.openShortcuts).padding(.leading, 28)
            }

            Divider()
            HStack {
                Text("단축어 연결").font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.loadingShortcuts { ProgressView().controlSize(.small) }
                Button("목록 새로고침") { Task { await model.loadShortcuts() } }
                    .font(.system(size: 11)).disabled(model.loadingShortcuts)
            }
            VStack(spacing: 12) {
                shortcutPicker("켤 때 실행", selection: $model.shortcutOn)
                shortcutPicker("끌 때 실행", selection: $model.shortcutOff)
            }
            if model.shortcuts.isEmpty && !model.loadingShortcuts {
                Text("단축어를 만든 뒤 목록을 새로고침하세요.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !model.shortcutOn.isEmpty && model.shortcutOn == model.shortcutOff {
                Text("켜기와 끄기는 서로 다른 단축어를 선택해 주세요.").font(.system(size: 11)).foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("모든 알림을 조용히 하려면", systemImage: "bell.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text("시스템 설정 → 집중 모드 → 방해 금지에서 허용된 사람·앱을 비우고, 반복 통화·시간 지정 알림 등 예외를 꺼주세요. 긴급 알림 등 일부 시스템 알림은 macOS 정책을 따릅니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Button("집중 모드 설정 열기", action: model.openFocusSettings).font(.system(size: 11))
            }
            .padding(14).background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            Text("NonSleep은 선택한 단축어의 실행 성공 여부만 확인합니다. 단축어 동작과 시스템의 실제 집중 모드 상태를 직접 읽거나 검증하지 않습니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("끄기 실행") { Task { await model.setFocus(false) } }
                    .disabled(!model.focusConfigured || model.busy != nil)
                Spacer()
                Button("완료") {
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
            Text("단축어 선택…").tag("")
            if !selection.wrappedValue.isEmpty && !model.shortcuts.contains(selection.wrappedValue) {
                Text("\(selection.wrappedValue) (목록에서 찾지 못함)").tag(selection.wrappedValue)
            }
            ForEach(model.shortcuts, id: \.self) { Text($0).tag($0) }
        }
        .font(.system(size: 12))
    }
}
