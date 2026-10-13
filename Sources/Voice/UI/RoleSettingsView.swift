import SwiftUI

struct RoleSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @State private var selectedID: String?
    @State private var draft = RoleProfile(name: "", background: "")

    private var selectedRole: RoleProfile? {
        settings.roleProfiles.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("角色会为 LLM 提供专业词汇、语境和表达边界。最多同时启用 3 个候选；首次输入会自动判定并锁定一个角色。")
                .font(.system(size: 13))
                .foregroundStyle(AppChrome.muted)

            HStack(alignment: .top, spacing: 16) {
                roleList
                    .frame(width: 220)
                editor
            }
            .frame(minHeight: 330)

            HStack(spacing: 10) {
                Button("新增角色") {
                    let new = RoleProfile(name: "新角色", background: "描述这个角色的工作语境和专业范围。")
                    draft = new
                    selectedID = nil
                }
                Button("恢复预设角色") { settings.restoreDefaultRoles() }
                Spacer()
                Text(settings.roleSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppChrome.muted)
            }
        }
        .onAppear {
            if selectedID == nil, let first = settings.roleProfiles.first {
                select(first)
            }
        }
    }

    private var roleList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可用角色")
                .font(.system(size: 13, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(settings.roleProfiles) { role in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { settings.isRoleSelected(role) },
                                set: { settings.setRoleSelected(role, selected: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .disabled(!settings.isRoleSelected(role) && !settings.canSelectMoreRoles())
                            Button {
                                select(role)
                            } label: {
                                Label(role.name, systemImage: role.symbol)
                                    .font(.system(size: 13, weight: selectedID == role.id ? .semibold : .regular))
                                    .foregroundStyle(AppChrome.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(selectedID == role.id ? AppChrome.sidebarActiveFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedRole == nil ? "新增角色" : "编辑角色")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let selectedRole {
                    Button("删除", role: .destructive) {
                        settings.deleteRole(selectedRole)
                        selectedID = nil
                        draft = RoleProfile(name: "", background: "")
                    }
                }
            }
            roleField("名称", text: $draft.name)
            roleField("SF Symbol", text: $draft.symbol)
            roleEditor("专业背景", text: $draft.background, minHeight: 58)
            roleEditor("术语与常见误辨修正", text: $draft.terminology, minHeight: 74)
            roleEditor("表达风格与承诺边界", text: $draft.styleGuide, minHeight: 74)
            HStack {
                Button("保存角色") {
                    settings.saveRole(draft)
                    selectedID = draft.id
                }
                .disabled(!draft.isUsable)
                Button("锁定此角色") {
                    settings.lockRole(draft)
                }
                .disabled(!settings.roleProfiles.contains(where: { $0.id == draft.id }))
                Button("解除锁定") { settings.lockRole(nil) }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roleField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 94, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func roleEditor(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextEditor(text: text)
                .font(.system(size: 12))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(AppChrome.canvas, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func select(_ role: RoleProfile) {
        selectedID = role.id
        draft = role
    }
}
