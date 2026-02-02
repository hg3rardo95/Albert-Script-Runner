//
//  ContentView.swift
//  Albert Script Runner
//

import SwiftUI
import AppKit

struct ContentView: View {
    @SwiftUI.Environment(\SwiftUI.EnvironmentValues.accessibilityReduceTransparency) private var reduceTransparency

    // Mirrors your PySide UI state
    @State private var token: String = ""
    @State private var env: Environment = .sandbox
    @State private var tokenBarExpanded: Bool = true
    @State private var tokenBarHovering: Bool = false
    @State private var action: AppAction? = nil
    @State private var migrationEnabled: Bool = false

    // Basic UI feedback (like QMessageBox)
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertBody: String = ""
    @State private var isRunning: Bool = false
    @State private var migrationToken: String = ""
    @State private var migrationEnv: Environment = .production
    @State private var migrationBarExpanded: Bool = true
    @State private var migrationBarHovering: Bool = false

    private var tokenIsFilled: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tokenSummary: JwtSummary? {
        decodeJwtSummary(token)
    }

    private var tokenIsExpired: Bool {
        guard let exp = tokenSummary?.expiresAt else { return false }
        return exp < Date()
    }

    private var migrationTokenIsFilled: Bool {
        !migrationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var migrationTokenSummary: JwtSummary? {
        decodeJwtSummary(migrationToken)
    }

    private var migrationTokenIsExpired: Bool {
        guard let exp = migrationTokenSummary?.expiresAt else { return false }
        return exp < Date()
    }

    // MARK: - Locations (list-locations wiring)

    @State private var existingLocations: [LocationDTO] = []
    @State private var isLoadingLocations: Bool = false
    @State private var locationsError: String = ""

    // MARK: - Locations Inputs

    @State private var locAction: LocationAction = .uploadNew
    @State private var locationInputs: [LocationInputRow] = [LocationInputRow()]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // --- Top Bar: Collapsible Token + Environment (pinned) ---
            topBar

            // Everything below the topBar scrolls (scrollbars only appear when needed)
            ScrollView {
                ZStack(alignment: .topLeading) {

                    // Background click-catcher that covers ALL whitespace in the scroll region.
                    // Taps on controls/widgets will still work; taps on empty space will hit this.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            collapseExpandedBars()
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            if action == .migration, migrationEnabled {
                                migrationBar
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .animation(.easeInOut(duration: 0.5), value: migrationEnabled)
                        .animation(.easeInOut(duration: 0.5), value: action == .migration)

                        // Migration toggle: only visible when the Migration tool is selected
                        if action == .migration {
                            Toggle("Migration", isOn: $migrationEnabled)
                                .onChange(of: migrationEnabled) { _, isOn in
                                    // When enabling migration, start destination bar expanded so it's ready to paste.
                                    if isOn {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            migrationBarExpanded = true
                                        }
                                    }
                                }
                        }

                        // --- Action Bar (like your action_frame) ---
                        actionBar

                        // --- Content container (expanding area) ---
                        contentArea
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // --- Run button centered (pinned at bottom) ---
            runButtonRow
        }
        .padding(12)
        .animation(.easeInOut(duration: 0.5), value: migrationEnabled)
        .animation(.easeInOut(duration: 0.5), value: tokenIsFilled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            reduceTransparency
                ? Color(.windowBackgroundColor).opacity(0.5)
                : Color.clear
        )
        // If the token is cleared, always expand so it's ready to paste.
        .onChange(of: token) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.easeInOut(duration: 0.5)) {
                    tokenBarExpanded = true
                }
            }
        }
        .onChange(of: migrationToken) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.easeInOut(duration: 0.5)) {
                    migrationBarExpanded = true
                }
            }
        }
        .onChange(of: action) { _, newValue in
            // Hide migration UI unless the migration tool is selected
            if newValue != .migration, migrationEnabled {
                withAnimation(.easeInOut(duration: 0.5)) {
                    migrationEnabled = false
                }
            }
        }
        // Collapse when the app resigns active (e.g., click outside the window/app)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                if tokenIsFilled, tokenBarExpanded {
                    tokenBarExpanded = false
                }
                if migrationEnabled, migrationTokenIsFilled, migrationBarExpanded {
                    migrationBarExpanded = false
                }
            }
        }
        // Collapse when the key window resigns key (e.g., click into another window)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                if tokenIsFilled, tokenBarExpanded {
                    tokenBarExpanded = false
                }
                if migrationEnabled, migrationTokenIsFilled, migrationBarExpanded {
                    migrationBarExpanded = false
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertBody)
        }
    }

    // MARK: - UI Sections

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if migrationEnabled {
                Text("Source")
                    .font(.headline)
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top)))
            }

            if tokenBarExpanded || !tokenIsFilled {
                // Expanded (editable) state
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Token:")

                        TextField("Paste token here", text: $token)
                            .textFieldStyle(.roundedBorder)

                        Text("Source Environment:")

                        Picker("", selection: $env) {
                            ForEach(Environment.allCases) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        .frame(width: 170)
                    }

                    if tokenIsFilled {
                        VStack(alignment: .leading, spacing: 4) {
                            if tokenIsExpired {
                                Text("Token expired")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                            }
                            Text(decodeJwtPretty(token.trimmingCharacters(in: .whitespacesAndNewlines)))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .transition(.opacity)
                    }
                }
                // Swallow taps in the expanded bar so clicking inside it doesn't collapse it via the root onTapGesture
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { })

            } else {
                // Collapsed summary state
                HStack(spacing: 10) {
                    Text(tokenSummary?.name ?? "—")
                        .font(.headline)

                    Text(tokenSummary?.tenantId ?? "—")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(env.rawValue)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    if tokenBarHovering {
                        Text("Click to edit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        tokenBarExpanded = true
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .background(tokenIsExpired ? Color.red.opacity(0.18) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tokenBarHovering ? Color.secondary.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                tokenBarHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.25), value: tokenBarExpanded)
        .animation(.easeInOut(duration: 0.25), value: tokenIsFilled)
        .animation(.easeInOut(duration: 0.5), value: migrationEnabled)
    }

    private var migrationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination")
                .font(.headline)

            if migrationBarExpanded || !migrationTokenIsFilled {
                // Expanded (editable) state
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Token:")

                        TextField("Paste token here", text: $migrationToken)
                            .textFieldStyle(.roundedBorder)

                        Text("Dest Environment:")

                        Picker("", selection: $migrationEnv) {
                            ForEach(Environment.allCases) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        .frame(width: 170)
                    }

                    if migrationTokenIsFilled {
                        VStack(alignment: .leading, spacing: 4) {
                            if migrationTokenIsExpired {
                                Text("Token expired")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                            }
                            Text(decodeJwtPretty(migrationToken.trimmingCharacters(in: .whitespacesAndNewlines)))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .transition(.opacity)
                    }
                }
                // Swallow taps in the expanded bar so clicking inside it doesn't collapse it via the parent onTapGesture
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { })

            } else {
                // Collapsed summary state
                HStack(spacing: 10) {
                    Text(migrationTokenSummary?.name ?? "—")
                        .font(.headline)

                    Text(migrationTokenSummary?.tenantId ?? "—")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(migrationEnv.rawValue)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    if migrationBarHovering {
                        Text("Click to edit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        migrationBarExpanded = true
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .background(migrationTokenIsExpired ? Color.red.opacity(0.18) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(migrationBarHovering ? Color.secondary.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                migrationBarHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.25), value: migrationBarExpanded)
        .animation(.easeInOut(duration: 0.25), value: migrationTokenIsFilled)
    }


    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("Choose what you'd like to do:")

            Picker("", selection: Binding<AppAction?>(
                get: { action },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        action = newValue
                    }
                }
            )) {
                Text("Select a View").tag(AppAction?.none)
                ForEach(AppAction.allCases) { a in
                    Text(a.rawValue).tag(Optional(a))
                }
            }
            .frame(width: 280)
            .onChange(of: action) { _, newValue in
                guard newValue == .addLocations else { return }
                // Option A: only auto-refresh if we don't already have data
                guard existingLocations.isEmpty, !isLoadingLocations else { return }
                refreshExistingLocations()
            }

            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
        .cornerRadius(8)
        // Also collapse bars when interacting with the action bar (Picker still works)
        .simultaneousGesture(
            TapGesture().onEnded {
                collapseExpandedBars()
            }
        )
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch action {
            case .addLocations:
                LocationsManagerView(
                    existingLocations: $existingLocations,
                    isLoadingLocations: $isLoadingLocations,
                    locationsError: $locationsError,
                    locAction: $locAction,
                    locationInputs: $locationInputs,
                    onRefresh: { refreshExistingLocations() }
                )
                .glassEffectTransition(.materialize)
                .transition(.opacity)

            case .downloadUsers:
                downloadUsersSection
                    .glassEffectTransition(.materialize)
                    .transition(.opacity)

            case .migration:
                MigrationTemplatesView()
                    .glassEffectTransition(.materialize)
                    .transition(.opacity)

            case .none:
                EmptyView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadUsersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download All Users")
                .font(.headline)

            Text("This will download all users present in the current tenant and prompt you to save it in an Excel file.")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .cornerRadius(10)
    }

    private var migrationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Migration Tracker and Tools")
                .font(.headline)

            Text("This action will use Source + Destination token/environment fields above. Wiring comes next.")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .cornerRadius(10)
    }

    private var runButtonRow: some View {
        HStack {
            Spacer()

            Button(isRunning ? "Running..." : (action?.runButtonTitle(locAction: locAction) ?? "Run Script")) {
                onRunClicked()
            }
            .frame(width: 160)
            .disabled(isRunning)

            Spacer()
        }
        .padding(.top, 6)
        // Clicking anywhere on the pinned run row collapses bars (button still runs)
        .simultaneousGesture(
            TapGesture().onEnded {
                collapseExpandedBars()
            }
        )
    }


    // MARK: - Collapse helpers

    private func collapseExpandedBars() {
        withAnimation(.easeInOut(duration: 0.5)) {
            if tokenIsFilled, tokenBarExpanded {
                tokenBarExpanded = false
            }
            if action == .migration, migrationEnabled, migrationTokenIsFilled, migrationBarExpanded {
                migrationBarExpanded = false
            }
        }
    }

    // MARK: - Actions (matches your onRunClicked)

    private func onRunClicked() {
        // Determine intent from the selected action + inner segmented control (for Locations)
        let intent: RunIntent = action.map { $0.runIntent(locAction: locAction) } ?? .none

        // Validate token/env only when needed
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if intent.requiresTokenAndEnv {
            if t.isEmpty {
                showWarning("Missing token", "Please paste a token before running a script.")
                return
            }
        }

        // Base URL (source env)
        let baseURL = env.baseURL

        switch intent {
        case .none:
            showInfo("Select an action", "Please choose an action before clicking Run.")

        case .downloadUsers:
            runDownloadUsers(token: t, baseURL: baseURL)

        case .listLocations:
            // Not currently used by the UI, but supported as an intent.
            refreshExistingLocations()

        case .uploadLocations:
            Task { @MainActor in
                isRunning = true
                defer { isRunning = false }

                do {
                    let results = try await LocationModelRunner.uploadNewLocations(
                        baseURL: baseURL,
                        token: t,
                        rows: locationInputs
                    )

                    presentUploadResults(results)

                    // Refresh existing list after upload
                    refreshExistingLocations()
                } catch {
                    showWarning("Upload error", error.localizedDescription)
                }
            }

        case .updateLocations:
            Task { @MainActor in
                isRunning = true
                defer { isRunning = false }

                do {
                    let results = try await LocationModelRunner.updateExistingLocations(
                        baseURL: baseURL,
                        token: t,
                        rows: locationInputs
                    )

                    presentUpdateResults(results)

                    // Refresh existing list after updates
                    refreshExistingLocations()
                } catch {
                    showWarning("Update error", error.localizedDescription)
                }
            }

        case .migration:
            showInfo(
                "Migration (placeholder)",
                "Migration UI is ready. Next we’ll wire the Python actions using the Source/Destination tokens."
            )
        }
    }

    private func refreshExistingLocations() {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            locationsError = "Paste a valid token and select an environment to load locations."
            existingLocations = []
            return
        }

        let baseURL = env.baseURL

        withAnimation(.easeInOut(duration: 0.5)) {
            isLoadingLocations = true
            locationsError = ""
        }

        Task {
            do {
                // Run python + JSON decode off the main actor
                let decoded: [LocationDTO] = try await Task.detached {
                    let output = try PythonRunner.run(args: [
                        "list-locations",
                        "--token", t,
                        "--base-url", baseURL
                    ])

                    let data = Data(output.utf8)
                    return try JSONDecoder().decode([LocationDTO].self, from: data)
                }.value

                await MainActor.run {
                    self.existingLocations = decoded
                    self.locationsError = decoded.isEmpty ? "No locations returned." : ""
                    self.isLoadingLocations = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingLocations = false
                    self.existingLocations = []
                    self.locationsError = error.localizedDescription
                }
            }
        }
    }

    private func presentUploadResults(_ results: [LocationModelRunner.UploadLocationResult]) {
        let failed = results.filter { $0.isFailed }

        if results.isEmpty {
            showWarning("Missing inputs", "Please add at least one location before uploading.")
            return
        }

        if failed.isEmpty {
            showInfo("Upload complete", "All locations processed without API failures.\n\nProcessed: \(results.count)")
        } else {
            let lines = failed.map { "• \($0.displayName): \($0.displayError)" }
            showWarning(
                "Some uploads failed",
                "Failures: \(failed.count) of \(results.count)\n\n\(lines.joined(separator: "\n"))"
            )
        }
    }

    private func presentUpdateResults(_ results: [LocationModelRunner.UpdateLocationResult]) {
        let failed = results.filter { $0.isFailed }
        let updated = results.filter { ($0.status ?? "").lowercased() == "updated" }

        if results.isEmpty {
            showWarning("Missing inputs", "Please add at least one location before updating.")
            return
        }

        if failed.isEmpty {
            showInfo(
                "Update complete",
                "All locations processed without API failures.\n\nUpdated: \(updated.count)"
            )
        } else {
            let lines = failed.map { "• \($0.displayId) (\($0.displayName)): \($0.displayError)" }
            showWarning(
                "Some updates failed",
                "Updated: \(updated.count) of \(results.count)\nFailures: \(failed.count) of \(results.count)\n\n\(lines.joined(separator: "\n"))"
            )
        }
    }

    private func runDownloadUsers(token: String, baseURL: String) {
        Task { @MainActor in
            isRunning = true
            defer { isRunning = false }

            let saveURL = await SavePanel.show(
                title: "Save users as…",
                message: "Choose where to save the Excel file.",
                defaultFileName: "users.xlsx",
                allowedFileExtensions: ["xlsx"]
            )

            // User cancelled
            guard let saveURL else { return }

            do {
                // Run python off the main thread
                let output = try await Task.detached {
                    try PythonRunner.run(args: [
                        "download-users",
                        "--token", token,
                        "--base-url", baseURL,
                        "--out", saveURL.path
                    ])
                }.value

                showInfo(
                    "Users exported",
                    "Saved to:\n\(saveURL.path)\n\n\(output)"
                )
            } catch {
                showWarning("Error pulling users", error.localizedDescription)
            }
        }
    }

    // MARK: - Alerts helpers

    private func showWarning(_ title: String, _ body: String) {
        alertTitle = title
        alertBody = body
        showAlert = true
    }

    private func showInfo(_ title: String, _ body: String) {
        alertTitle = title
        alertBody = body
        showAlert = true
    }
}

#Preview {
    ContentView()
}

