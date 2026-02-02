//
//  MigrationTemplatesView.swift
//  Albert Script Runner
//

import SwiftUI
import SwiftData

struct MigrationTemplatesView: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext: ModelContext

    @StateObject private var vm = MigrationTrackerViewModel()

    // MVP: toggles that map directly to the Python extract script options
    @State private var includeParameterGroups: Bool = false
    @State private var includeDataTemplates: Bool = false

    // Templates are grouped (expandable) with per-type toggles.
    @State private var includeTemplates: Bool = false
    @State private var templatesExpanded: Bool = false

    @State private var includeBatchTaskTemplates: Bool = false
    @State private var includePropertyTaskTemplates: Bool = false
    @State private var includeNotebookTemplates: Bool = false
    @State private var includeGeneralTaskTemplates: Bool = false
    @State private var includeSheetTemplates: Bool = false

    @State private var templates: [CustomTemplateEntity] = []
    @State private var isLoading: Bool = false
    @State private var isHoveringTemplatesButton: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            filters

            Divider()

            content
        }
        .padding(12)
        .background(.thinMaterial)
        .cornerRadius(10)
        .task { await reloadTemplates() }
        .onChange(of: includeTemplates) { _, newValue in
            // If templates are disabled, disable all subtypes.
            if !newValue {
                includeBatchTaskTemplates = false
                includePropertyTaskTemplates = false
                includeNotebookTemplates = false
                includeGeneralTaskTemplates = false
                includeSheetTemplates = false
            }
        }
        .onChange(of: includeBatchTaskTemplates) { _, _ in includeTemplates = anyTemplateTypeSelected }
        .onChange(of: includePropertyTaskTemplates) { _, _ in includeTemplates = anyTemplateTypeSelected }
        .onChange(of: includeNotebookTemplates) { _, _ in includeTemplates = anyTemplateTypeSelected }
        .onChange(of: includeGeneralTaskTemplates) { _, _ in includeTemplates = anyTemplateTypeSelected }
        .onChange(of: includeSheetTemplates) { _, _ in includeTemplates = anyTemplateTypeSelected }
        // Removed onChange handlers for vm.selectedTemplateKind, vm.prefixFilter, vm.tagFilterCSV
        // .onAppear removed: no configure method in vm
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Migration Templates")
                    .font(.headline)

                Text("Choose what to download from Albert. Wiring to the Python engine comes next.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Download Templates") {
                    downloadTemplateTracker()
                }

                Button("Reload") {
                    Task { await reloadTemplates() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select what to download")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            HStack {
                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    // Right-justified core toggles
                    HStack {
                        Spacer()
                        filterToggle("Parameter Groups (PGs)", isOn: $includeParameterGroups)
                    }

                    HStack {
                        Spacer()
                        filterToggle("Data Templates (DTs)", isOn: $includeDataTemplates)
                    }

                    // Custom Templates pill: compact, right-aligned, content-hugging
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                templatesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Text("Custom Templates")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                if selectedTemplatesCount > 0 {
                                    Text("\(selectedTemplatesCount)")
                                        .font(.caption2)
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                        .background(Capsule().fill(.quaternary))
                                }

                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(templatesExpanded ? 90 : 0))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 10)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        if templatesExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                // Subtype toggles (content-hugging; no inner spacers)
                                filterToggle("Batch Task Templates", isOn: $includeBatchTaskTemplates)

                                filterToggle("Property Task Templates", isOn: $includePropertyTaskTemplates)

                                filterToggle("Notebook Templates", isOn: $includeNotebookTemplates)

                                filterToggle("General Task Templates", isOn: $includeGeneralTaskTemplates)

                                filterToggle("Sheet Templates", isOn: $includeSheetTemplates)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                    .fixedSize(horizontal: true, vertical: false)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isHoveringTemplatesButton = hovering
                        }

                        // Collapse when the pointer leaves the entire pill/panel AND nothing is selected.
                        if !hovering && templatesExpanded && !anyTemplateTypeSelected {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                templatesExpanded = false
                            }
                        }
                    }
                    .scaleEffect(isHoveringTemplatesButton && !templatesExpanded ? 1.03 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: templatesExpanded)
                    .animation(.easeInOut(duration: 0.18), value: isHoveringTemplatesButton)
                }
            }

            if let msg = vm.lastErrorMessage, !msg.isEmpty {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    private var content: some View {
        Group {
            if templates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No templates found")
                        .font(.subheadline)
                    Text("Try changing filters, or insert sample data to validate the SwiftData pipeline.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                .padding(.vertical, 8)
            } else {
                List {
                    Section("Custom Templates (\(templates.count))") {
                        ForEach(templates, id: \.uniqueKey) { t in
                            templateRow(t)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func templateRow(_ t: CustomTemplateEntity) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(t.albertId)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(t.templateKind)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !t.tagsCSV.isEmpty {
                        Text(t.tagsCSV)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Toggle("Migrate", isOn: Binding(
                    get: { t.shouldMigrate },
                    set: { vm.setShouldMigrate($0, for: t, modelContext: modelContext) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

                Toggle("Complete", isOn: Binding(
                    get: { t.migrationComplete },
                    set: { vm.setMigrationCompleted($0, for: t, modelContext: modelContext) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text("PGs: \(t.parameterGroupCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("DTs: \(t.dataTemplateCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var anyTemplateTypeSelected: Bool {
        includeBatchTaskTemplates ||
        includePropertyTaskTemplates ||
        includeNotebookTemplates ||
        includeGeneralTaskTemplates ||
        includeSheetTemplates
    }

    private var selectedTemplatesCount: Int {
        [includeBatchTaskTemplates,
         includePropertyTaskTemplates,
         includeNotebookTemplates,
         includeGeneralTaskTemplates,
         includeSheetTemplates].filter { $0 }.count
    }

    private var pillCornerRadius: CGFloat { templatesExpanded ? 16 : 999 }

    // MARK: - Actions

    private func filterToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
    }

    private func reloadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            vm.lastErrorMessage = nil
            templates = try vm.fetchCustomTemplates(modelContext: modelContext)
        } catch {
            vm.lastErrorMessage = "Failed to fetch templates: \(error.localizedDescription)"
            templates = []
        }
    }

    private func downloadTemplateTracker() {
        vm.lastErrorMessage = nil

        // Use a small unique suffix so repeated clicks won't collide with uniqueKey constraints.
        let suffix = String(Int(Date().timeIntervalSince1970))
        let env = "sandbox"

        let pg = ParameterGroupEntity(
            albertId: "PRG\(suffix)",
            name: "Sample Parameter Group \(suffix)",
            environment: env,
            tags: ["SAMPLE"],
            shouldMigrate: true,
            migrationCompletedAt: nil,
            notes: ""
        )

        let dt = DataTemplateEntity(
            albertId: "DAT\(suffix)",
            name: "Sample Data Template \(suffix)",
            environment: env,
            tags: ["SAMPLE"],
            shouldMigrate: true,
            migrationCompletedAt: nil,
            notes: ""
        )

        let ct = CustomTemplateEntity(
            albertId: "CTP\(suffix)",
            name: "Sample Template \(suffix)",
            environment: env,
            templateKind: "Property Task",
            tags: ["SAMPLE"],
            shouldMigrate: true,
            migrationCompletedAt: nil,
            notes: ""
        )

        // Insert nodes
        modelContext.insert(pg)
        modelContext.insert(dt)
        modelContext.insert(ct)

        // Create edges
        let linkPG = TemplateParameterGroupLinkEntity(template: ct, parameterGroup: pg)
        let linkDT = TemplateDataTemplateLinkEntity(template: ct, dataTemplate: dt)
        modelContext.insert(linkPG)
        modelContext.insert(linkDT)

        do {
            try modelContext.save()
            Task { await reloadTemplates() }
        } catch {
            vm.lastErrorMessage = "Failed to insert sample data: \(error.localizedDescription)"
        }
    }
}

#Preview {
    // Use an in-memory container for previews and avoid throwing APIs in the macro body
    let schema = Schema([
        ParameterGroupEntity.self,
        DataTemplateEntity.self,
        CustomTemplateEntity.self,
        TemplateParameterGroupLinkEntity.self,
        TemplateDataTemplateLinkEntity.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try? ModelContainer(for: schema, configurations: [configuration])

    if let container {
        return MigrationTemplatesView()
            .modelContainer(container)
    } else {
        return MigrationTemplatesView()
    }
}
