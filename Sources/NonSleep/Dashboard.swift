import SwiftUI

private let leaf = Color(red: 0.23, green: 0.49, blue: 0.37)

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var background: Color {
        scheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.11) : Color(red: 0.96, green: 0.96, blue: 0.93)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            hero
            VStack(spacing: 10) {
                FeatureRow(icon: "sun.max", title: "잠자기 방지", tag: model.awake ? "사용 중" : nil,
                    detail: "Mac과 화면을 깨어 있게 유지합니다.",
                    note: model.lid && !model.awake ? "덮개 모드에 의해 시스템 잠자기는 계속 방지됩니다." : nil,
                    isOn: Binding(get: { model.awake }, set: { model.setAwake($0) }),
                    busy: false, disabled: model.busy != nil, activeColor: Color(nsColor: StatusAppearance.awake.color))

                FeatureRow(icon: "laptopcomputer", title: "덮어도 깨어 있기",
                    tag: model.lidKnown ? (model.lid ? "사용 중" : "관리자 권한") : "확인 중",
                    detail: "MacBook 덮개를 닫아도 작업을 계속합니다.",
                    note: "시스템 잠자기도 함께 차단됩니다. 기기·macOS에 따라 동작이 다를 수 있습니다.",
                    isOn: Binding(get: { model.lid }, set: { value in Task { await model.setLid(value) } }),
                    busy: model.busy == "lid", disabled: model.busy != nil || !model.lidKnown,
                    activeColor: Color(nsColor: StatusAppearance.lid.color))

                FeatureRow(icon: "moon", title: "방해 금지",
                    tag: !model.focusConfigured ? "설정 필요" : (model.focusRequest == nil ? "상태 미확인" : "단축어 실행됨"),
                    detail: "알림을 잠시 멈추고, 하던 일에 집중하세요.",
                    note: model.focusConfigured ? "최근 단축어 실행 기준입니다. 시스템에서 바꾼 상태는 반영되지 않습니다." : "처음 한 번, 켜기·끄기 단축어를 연결해 주세요.",
                    isOn: Binding(get: { model.focusRequest == true }, set: { value in Task { await model.setFocus(value) } }),
                    busy: model.busy == "focus", disabled: model.busy != nil,
                    activeColor: Color(nsColor: StatusAppearance.focus.color))
                .contextMenu {
                    Button("방해 금지 켜기 실행") { Task { await model.setFocus(true) } }
                    Button("방해 금지 끄기 실행") { Task { await model.setFocus(false) } }
                    Divider()
                    Button("단축어 설정…") { model.openSettings(.focus) }
                }
            }

            if model.recovery != nil {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(leaf)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("덮개 설정 복원 가능").font(.system(size: 12, weight: .semibold))
                        Text("앱 종료 시 이전 전원 설정으로 복원합니다. 강제 종료 후에는 여기서 복원할 수 있습니다.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("복원") { Task { await model.restoreLid() } }
                        .font(.system(size: 11, weight: .medium)).disabled(model.busy != nil || !model.lidKnown)
                }
                .padding(12).background(leaf.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            footer
        }
        .padding(26)
        .frame(width: 466)
        .background(background)
        .tint(leaf)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .alert("작업을 완료하지 못했어요", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: model.statusAppearance.symbolName)
                    .foregroundStyle(Color(nsColor: model.statusAppearance.color))
                Text("NonSleep").font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Spacer()
            Text("YOUR MAC, AWAKE.")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.3).foregroundStyle(.secondary)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("깨어 있는 Mac.\n끊김 없는 몰입.")
                    .font(.system(size: 27, weight: .semibold)).tracking(-1)
                    .lineSpacing(3)
                HStack(spacing: 6) {
                    Circle().fill(model.activeCount > 0 ? leaf : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(model.activeCount > 0 ? "\(model.activeCount)개 기능 사용 중" : "필요한 기능을 켜보세요")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(leaf.opacity(0.06)).frame(width: 100, height: 100)
                Circle().stroke(leaf.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 88, height: 88)
                Image(systemName: model.activeCount > 0 ? "sun.max" : "sun.haze")
                    .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(leaf)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 9)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 10)).padding(.top, 1)
                Text("종료하면 잠자기 방지는 해제됩니다. 방해 금지는 유지되며, 허용한 알림은 집중 모드 설정을 따릅니다.")
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            HStack {
                Button { model.openSettings() } label: {
                    Label("설정", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").accessibilityLabel("전원 상태 새로고침")
                }
                .buttonStyle(.plain).disabled(model.busy != nil)
                Button("종료") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).padding(.leading, 12).disabled(model.busy != nil)
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let tag: String?
    let detail: String
    let note: String?
    @Binding var isOn: Bool
    let busy: Bool
    let disabled: Bool
    let activeColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isOn ? activeColor : .secondary)
                .frame(width: 36, height: 36)
                .background(activeColor.opacity(isOn ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let tag {
                        Text(tag).font(.system(size: 8, weight: .medium))
                            .foregroundStyle(isOn ? activeColor : .secondary)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(activeColor.opacity(0.07), in: Capsule())
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView().controlSize(.small).frame(width: 34, height: 22)
                    .accessibilityLabel("\(title) 변경 중")
            } else {
                Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(disabled).accessibilityLabel(title)
            }
        }
        .padding(15)
        .tint(activeColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.04)))
    }
}
