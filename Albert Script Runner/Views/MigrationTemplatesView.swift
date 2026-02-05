//
//  MigrationTemplatesView.swift
//  Albert Script Runner
//

import SwiftUI
import SwiftData

struct MigrationTemplatesView: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext: ModelContext

    @StateObject private var vm = MigrationTrackerViewModel()

    @Binding var inputs: MigrationTemplateInputs
    @Binding var selectedMigrationFileURL: URL?
    @Binding var didPromptForMigrationFile: Bool

    // Templates are grouped (expandable) with per-type toggles.
    @State private var templatesExpanded: Bool = false

    @State private var templates: [CustomTemplateEntity] = []
    @State private var isLoading: Bool = false
    @State private var isHoveringTemplatesButton: Bool = false
    @State private var showMigrationFilePrompt: Bool = false

    var body: some View {
        ZStack {
            mainContent
                .blur(radius: showMigrationFilePrompt ? 8 : 0)
                .animation(.easeInOut(duration: 0.2), value: showMigrationFilePrompt)
                .allowsHitTesting(!showMigrationFilePrompt)

            if showMigrationFilePrompt {
                migrationFilePromptOverlay
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .cornerRadius(10)
        .task { await reloadTemplates() }
        .onAppear { scheduleMigrationFilePrompt() }
        .onChange(of: inputs.includeTemplates) { _, newValue in
            // If templates are disabled, disable all subtypes.
            if !newValue {
                inputs.includeBatchTaskTemplates = false
                inputs.includePropertyTaskTemplates = false
                inputs.includeNotebookTemplates = false
                inputs.includeGeneralTaskTemplates = false
                inputs.includeSheetTemplates = false
            }
        }
        .onChange(of: inputs.includeBatchTaskTemplates) { _, _ in inputs.includeTemplates = anyTemplateTypeSelected }
        .onChange(of: inputs.includePropertyTaskTemplates) { _, _ in inputs.includeTemplates = anyTemplateTypeSelected }
        .onChange(of: inputs.includeNotebookTemplates) { _, _ in inputs.includeTemplates = anyTemplateTypeSelected }
        .onChange(of: inputs.includeGeneralTaskTemplates) { _, _ in inputs.includeTemplates = anyTemplateTypeSelected }
        .onChange(of: inputs.includeSheetTemplates) { _, _ in inputs.includeTemplates = anyTemplateTypeSelected }
        .onChange(of: inputs.pgFilters.prefix) { _, _ in
            enforcePrefixTagsExclusion(prefix: $inputs.pgFilters.prefix, tagsText: $inputs.pgFilters.tagsText, tags: $inputs.pgFilters.tags)
        }
        .onChange(of: inputs.pgFilters.tagsText) { _, _ in
            enforcePrefixTagsExclusion(prefix: $inputs.pgFilters.prefix, tagsText: $inputs.pgFilters.tagsText, tags: $inputs.pgFilters.tags)
        }
        .onChange(of: inputs.dtFilters.prefix) { _, _ in
            enforcePrefixTagsExclusion(prefix: $inputs.dtFilters.prefix, tagsText: $inputs.dtFilters.tagsText, tags: $inputs.dtFilters.tags)
        }
        .onChange(of: inputs.dtFilters.tagsText) { _, _ in
            enforcePrefixTagsExclusion(prefix: $inputs.dtFilters.prefix, tagsText: $inputs.dtFilters.tagsText, tags: $inputs.dtFilters.tags)
        }
        // Removed onChange handlers for vm.selectedTemplateKind, vm.prefixFilter, vm.tagFilterCSV
        // .onAppear removed: no configure method in vm
    }

    // MARK: - Subviews

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            filters

            Divider()

            content
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Migration Templates")
                    .font(.headline)

                Text("This view allows you to download any and all templates that are ready.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let url = selectedMigrationFileURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(url.path)
                }

                HStack(spacing: 8) {
                    Button("Open Existing...") {
                        Task { await openMigrationFilePanel(closePromptOnSuccess: false) }
                    }
                    .controlSize(.small)

                    if selectedMigrationFileURL != nil {
                        Button("Forget File") {
                            selectedMigrationFileURL = nil
                        }
                        .controlSize(.small)
                    }

                    Button("Reload") {
                        Task { await reloadTemplates() }
                    }
                    .controlSize(.small)
                    .keyboardShortcut("r", modifiers: [.command])
                }
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
                        filterRow("Parameter Groups (PGs)", isOn: $inputs.includeParameterGroups, filters: $inputs.pgFilters, showTags: true)
                    }

                    HStack {
                        Spacer()
                        filterRow("Data Templates (DTs)", isOn: $inputs.includeDataTemplates, filters: $inputs.dtFilters, showTags: true)
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
                                filterRow("Batch Task Templates", isOn: $inputs.includeBatchTaskTemplates, filters: $inputs.batchFilters, showTags: false)

                                filterRow("Property Task Templates", isOn: $inputs.includePropertyTaskTemplates, filters: $inputs.propertyFilters, showTags: false)

                                filterRow("Notebook Templates", isOn: $inputs.includeNotebookTemplates, filters: $inputs.notebookFilters, showTags: false)

                                filterRow("General Task Templates", isOn: $inputs.includeGeneralTaskTemplates, filters: $inputs.generalFilters, showTags: false)

                                filterRow("Sheet Templates", isOn: $inputs.includeSheetTemplates, filters: $inputs.sheetFilters, showTags: false)
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

    private var migrationFilePromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("Would you like to save this to an existing file?")
                    .font(.headline)

                HStack(spacing: 10) {
                    glassButton("Select File") {
                        Task { await openMigrationFilePanel(closePromptOnSuccess: true) }
                    }

                    glassButton("Export Later") {
                        showMigrationFilePrompt = false
                    }
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        inputs.includeBatchTaskTemplates ||
        inputs.includePropertyTaskTemplates ||
        inputs.includeNotebookTemplates ||
        inputs.includeGeneralTaskTemplates ||
        inputs.includeSheetTemplates
    }

    private var selectedTemplatesCount: Int {
        [inputs.includeBatchTaskTemplates,
         inputs.includePropertyTaskTemplates,
         inputs.includeNotebookTemplates,
         inputs.includeGeneralTaskTemplates,
         inputs.includeSheetTemplates].filter { $0 }.count
    }

    private var pillCornerRadius: CGFloat { templatesExpanded ? 16 : 999 }
    private var prefixFieldWidth: CGFloat { 140 }
    private var tagsFieldWidth: CGFloat { 220 }

    // MARK: - Actions

    private func glassButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
    }

    private func scheduleMigrationFilePrompt() {
        guard !didPromptForMigrationFile else { return }
        if selectedMigrationFileURL != nil {
            didPromptForMigrationFile = true
            return
        }
        DispatchQueue.main.async {
            showMigrationFilePrompt = true
            didPromptForMigrationFile = true
        }
    }

    @MainActor
    private func openMigrationFilePanel(closePromptOnSuccess: Bool) async {
        let url = await OpenPanel.show(
            title: "Select migration template",
            message: "Choose an existing Excel file.",
            allowedFileExtensions: ["xlsx"]
        )

        if let url {
            selectedMigrationFileURL = url
            if closePromptOnSuccess {
                showMigrationFilePrompt = false
            }
        }
    }

    private func filterRow(
        _ title: String,
        isOn: Binding<Bool>,
        filters: Binding<MigrationTemplateFilterInputs>,
        showTags: Bool
    ) -> some View {
        let prefixValue = filters.wrappedValue.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagsValue = filters.wrappedValue.tagsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrefix = !prefixValue.isEmpty
        let hasTags = !tagsValue.isEmpty

        return HStack(alignment: .center, spacing: 8) {
            filterToggle(title, isOn: isOn)

            Group {
                if isOn.wrappedValue {
                    HStack(spacing: 8) {
                        TextField("Prefix", text: filters.prefix)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.callout)
                            .frame(width: prefixFieldWidth)
                            .disabled(showTags && hasTags)
                            .opacity(showTags && hasTags ? 0.5 : 1.0)

                        if showTags {
                            TextField("Tags", text: tagsTextBinding(filters))
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .font(.callout)
                                .frame(width: tagsFieldWidth)
                                .disabled(hasPrefix)
                                .opacity(hasPrefix ? 0.5 : 1.0)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isOn.wrappedValue)
    }

    private func filterToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
    }

    private func tagsTextBinding(_ filters: Binding<MigrationTemplateFilterInputs>) -> Binding<String> {
        Binding(
            get: { filters.wrappedValue.tagsText },
            set: { newValue in
                filters.wrappedValue.tagsText = newValue
                filters.wrappedValue.tags = parseTagCSV(newValue)
            }
        )
    }

    private func enforcePrefixTagsExclusion(
        prefix: Binding<String>,
        tagsText: Binding<String>,
        tags: Binding<[String]>
    ) {
        let trimmedPrefix = prefix.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = tagsText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPrefix.isEmpty, !trimmedTags.isEmpty else { return }

        tagsText.wrappedValue = ""
        tags.wrappedValue = []
    }

    private func parseTagCSV(_ csv: String) -> [String] {
        csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    let inputs = MigrationTemplateInputs()

    if let container {
        return MigrationTemplatesView(
            inputs: .constant(inputs),
            selectedMigrationFileURL: .constant(nil),
            didPromptForMigrationFile: .constant(false)
        )
            .modelContainer(container)
    } else {
        return MigrationTemplatesView(
            inputs: .constant(inputs),
            selectedMigrationFileURL: .constant(nil),
            didPromptForMigrationFile: .constant(false)
        )
    }
}

