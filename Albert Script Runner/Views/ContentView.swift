//
//  ContentView.swift
//  Albert Script Runner
//

import SwiftUI
import AppKit
import LocalAuthentication

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
    @State private var showTemplateAlert: Bool = false
    @State private var templateAlertBody: String = ""
    @State private var templateDecisionContinuation: CheckedContinuation<TemplateDecision, Never>? = nil
    @State private var isRunning: Bool = false
    @State private var migrationToken: String = ""
    @State private var migrationEnv: Environment = .production
    @State private var migrationBarExpanded: Bool = true
    @State private var migrationBarHovering: Bool = false
    @State private var migrationInputs = MigrationTemplateInputs()
    @State private var selectedMigrationFileURL: URL? = nil
    @State private var didPromptForMigrationFile: Bool = false
    @State private var didLoadMigrationBookmark: Bool = false
    @State private var showSavedTokensPopoverTop: Bool = false
    @State private var showSavedTokensPopoverMigration: Bool = false
    @State private var savedTokensUnlocked: Bool = false
    @State private var savedTokensAuthInProgress: Bool = false
    @State private var savedTokens: [SavedTokenMetadata] = []
    @State private var savedTokensError: String = ""
    @State private var savedTokensLastUnlockAt: Date? = nil
    @State private var savedTokensAuthContext: LAContext? = nil
    @State private var showAddTokenSheet: Bool = false
    @State private var addTokenValue: String = ""
    @State private var addTokenError: String = ""
    @State private var addTokenLabel: String = ""
    @State private var addTokenEnv: Environment = .sandbox

    private let savedTokensAuthReuseSeconds: TimeInterval = 300

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

    private var locationInputValidationError: String {
        validateLocationInputs() ?? ""
    }

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
        .onAppear {
            guard !didLoadMigrationBookmark else { return }
            didLoadMigrationBookmark = true
            guard selectedMigrationFileURL == nil else { return }
            if let url = MigrationFileBookmarkStore.shared.loadURL() {
                selectedMigrationFileURL = url
            }
        }
        .onChange(of: selectedMigrationFileURL) { _, newValue in
            if let url = newValue {
                do {
                    try MigrationFileBookmarkStore.shared.save(url: url)
                } catch {
                    showWarning("Unable to remember file", error.localizedDescription)
                }
            } else {
                MigrationFileBookmarkStore.shared.clear()
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
        .onChange(of: showSavedTokensPopoverTop) { _, isPresented in
            handleSavedTokensPopoverChange(isPresented)
        }
        .onChange(of: showSavedTokensPopoverMigration) { _, isPresented in
            handleSavedTokensPopoverChange(isPresented)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertBody)
        }
        .alert("Template mismatch", isPresented: $showTemplateAlert) {
            Button("Cancel", role: .cancel) {
                templateDecisionContinuation?.resume(returning: .cancel)
                templateDecisionContinuation = nil
            }
            Button("Replace", role: .destructive) {
                templateDecisionContinuation?.resume(returning: .replace)
                templateDecisionContinuation = nil
            }
        } message: {
            Text(templateAlertBody)
        }
        .sheet(isPresented: $showAddTokenSheet) {
            SavedTokenAddSheetView(
                tokenLabel: $addTokenLabel,
                tokenValue: $addTokenValue,
                selectedEnv: $addTokenEnv,
                errorMessage: addTokenError,
                onCancel: {
                    dismissAddTokenSheet()
                },
                onSave: {
                    saveNewToken()
                }
            )
        }
    }

    private enum TemplateDecision {
        case cancel
        case replace
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

                        if tokenBarHovering || showSavedTokensPopoverTop {
                            SavedTokensMenuButton(
                                isVisible: true,
                                isPresented: $showSavedTokensPopoverTop
                            ) {
                                savedTokensPopoverContent
                            }
                        }
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
                .onTapGesture { }

            } else {
                // Collapsed summary state
                HStack(spacing: 10) {
                    Text(tokenSummary?.name ?? "—")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(tokenSummary?.tenantId ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(env.rawValue)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if tokenBarHovering {
                        Text("Click to edit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .transition(.opacity)
                    }

                    if tokenBarHovering || showSavedTokensPopoverTop {
                        SavedTokensMenuButton(
                            isVisible: true,
                            isPresented: $showSavedTokensPopoverTop
                        ) {
                            savedTokensPopoverContent
                        }
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            tokenBarExpanded = true
                        }
                    }
                )
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

                        if migrationBarHovering || showSavedTokensPopoverMigration {
                            SavedTokensMenuButton(
                                isVisible: true,
                                isPresented: $showSavedTokensPopoverMigration
                            ) {
                                savedTokensPopoverContent
                            }
                        }
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
                .onTapGesture { }

            } else {
                // Collapsed summary state
                HStack(spacing: 10) {
                    Text(migrationTokenSummary?.name ?? "—")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(migrationTokenSummary?.tenantId ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(migrationEnv.rawValue)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if migrationBarHovering {
                        Text("Click bar to edit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .transition(.opacity)
                    }

                    if migrationBarHovering || showSavedTokensPopoverMigration {
                        SavedTokensMenuButton(
                            isVisible: true,
                            isPresented: $showSavedTokensPopoverMigration
                        ) {
                            savedTokensPopoverContent
                        }
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            migrationBarExpanded = true
                        }
                    }
                )
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
                    validationError: locationInputValidationError,
                    onRefresh: { refreshExistingLocations() }
                )
                .glassEffectTransition(.materialize)
                .transition(.opacity)

            case .downloadUsers:
                downloadUsersSection
                    .glassEffectTransition(.materialize)
                    .transition(.opacity)

            case .migration:
                MigrationTemplatesView(
                    inputs: $migrationInputs,
                    selectedMigrationFileURL: $selectedMigrationFileURL,
                    didPromptForMigrationFile: $didPromptForMigrationFile
                )
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

            Button(isRunning ? "Running..." : (action?.runButtonTitle(
                locAction: locAction,
                hasMigrationFile: action == .migration && selectedMigrationFileURL != nil
            ) ?? "Run Script")) {
                onRunClicked()
            }
            .frame(width: 160)
            .id(selectedMigrationFileURL?.path ?? "no-migration-file")
            .disabled(isRunning || (action == .addLocations && !locationInputValidationError.isEmpty))

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

    // MARK: - Saved Tokens UI helpers

    private var savedTokensPopoverContent: some View {
        SavedTokensPopoverView(
            isUnlocked: savedTokensUnlocked,
            isAuthenticating: savedTokensAuthInProgress,
            tokens: savedTokens,
            errorMessage: savedTokensError.isEmpty ? nil : savedTokensError,
            onUnlock: {
                unlockSavedTokens()
            },
            onSelect: { token in
                selectSavedToken(token)
            },
            onRename: { token in
                promptRenameToken(token)
            },
            onDelete: { token in
                confirmDeleteToken(token)
            },
            onAdd: {
                presentAddTokenSheet()
            }
        )
        .interactiveDismissDisabled(savedTokensAuthInProgress)
    }

    private func handleSavedTokensPopoverChange(_ isPresented: Bool) {
        if isPresented {
            savedTokensAuthInProgress = false
            savedTokensError = ""

            if let last = savedTokensLastUnlockAt,
               Date().timeIntervalSince(last) <= savedTokensAuthReuseSeconds,
               savedTokensAuthContext != nil {
                savedTokensUnlocked = true
                do {
                    savedTokens = try SavedTokenStore.shared.listMetadata()
                } catch {
                    savedTokensError = error.localizedDescription
                }
            } else {
                savedTokensUnlocked = false
            }
            return
        }

        if !showSavedTokensPopoverTop, !showSavedTokensPopoverMigration {
            savedTokensUnlocked = false
            savedTokensAuthInProgress = false
            savedTokensError = ""
        }
    }

    private func unlockSavedTokens() {
        guard !savedTokensAuthInProgress else { return }

        if let last = savedTokensLastUnlockAt,
           Date().timeIntervalSince(last) <= savedTokensAuthReuseSeconds,
           savedTokensAuthContext != nil {
            savedTokensUnlocked = true
            savedTokensLastUnlockAt = Date()
            do {
                savedTokens = try SavedTokenStore.shared.listMetadata()
            } catch {
                savedTokensError = error.localizedDescription
            }
            return
        }

        savedTokensError = ""
        let context = LAContext()
        var authError: NSError?

        context.touchIDAuthenticationAllowableReuseDuration = savedTokensAuthReuseSeconds

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            savedTokensError = authError?.localizedDescription ?? "Authentication is unavailable."
            return
        }

        savedTokensAuthInProgress = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock saved tokens"
        ) { success, error in
            Task { @MainActor in
                savedTokensAuthInProgress = false
                if success {
                    savedTokensUnlocked = true
                    savedTokensLastUnlockAt = Date()
                    savedTokensAuthContext = context
                    do {
                        savedTokens = try SavedTokenStore.shared.listMetadata()
                    } catch {
                        savedTokensError = error.localizedDescription
                    }
                } else {
                    savedTokensUnlocked = false
                    savedTokensAuthContext = nil
                    if let error {
                        savedTokensError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func makeSavedTokensContext() -> LAContext {
        if let existing = savedTokensAuthContext {
            return existing
        }

        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = savedTokensAuthReuseSeconds
        return context
    }

    private func selectSavedToken(_ tokenMetadata: SavedTokenMetadata) {
        savedTokensError = ""

        do {
            let tokenValue = try SavedTokenStore.shared.loadToken(
                id: tokenMetadata.id,
                prompt: "Unlock saved token",
                context: makeSavedTokensContext()
            )

            token = tokenValue
            if let environment = Environment.fromBaseURL(tokenMetadata.baseURL) {
                env = environment
            } else {
                savedTokensError = "Saved base URL does not match a known environment."
            }
        } catch {
            savedTokensError = error.localizedDescription
        }
    }

    private func presentAddTokenSheet() {
        addTokenValue = ""
        addTokenError = ""
        addTokenLabel = ""
        addTokenEnv = currentSavedTokensEnvironment()
        showAddTokenSheet = true
    }

    private func dismissAddTokenSheet() {
        showAddTokenSheet = false
        addTokenError = ""
    }

    private func saveNewToken() {
        addTokenError = ""
        let trimmed = addTokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = decodeJwtSummary(trimmed) else {
            addTokenError = "Invalid token."
            return
        }

        if let exp = summary.expiresAt, exp < Date() {
            let alert = NSAlert()
            alert.messageText = "Token is expired"
            alert.informativeText = "This token has already expired. Save anyway?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save Anyway")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
        }

        do {
            let _ = try SavedTokenStore.shared.saveToken(
                jwt: trimmed,
                baseURL: addTokenEnv.baseURL,
                label: addTokenLabel
            )
            savedTokens = try SavedTokenStore.shared.listMetadata()
            showAddTokenSheet = false
        } catch {
            addTokenError = error.localizedDescription
        }
    }

    private func currentSavedTokensEnvironment() -> Environment {
        if showSavedTokensPopoverMigration {
            return migrationEnv
        }
        return env
    }

    private func promptRenameToken(_ tokenMetadata: SavedTokenMetadata) {
        let alert = NSAlert()
        alert.messageText = "Rename Saved Token"
        alert.informativeText = "Enter a new name for this token."
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = tokenMetadata.label
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let newLabel = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newLabel.isEmpty else {
            savedTokensError = "Name cannot be empty."
            return
        }

        do {
            _ = try SavedTokenStore.shared.renameToken(id: tokenMetadata.id, newLabel: newLabel)
            savedTokens = try SavedTokenStore.shared.listMetadata()
        } catch {
            savedTokensError = error.localizedDescription
        }
    }

    private func confirmDeleteToken(_ tokenMetadata: SavedTokenMetadata) {
        let alert = NSAlert()
        alert.messageText = "Delete Saved Token?"
        alert.informativeText = "This removes the token from your Mac's keychain."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        do {
            try SavedTokenStore.shared.deleteToken(id: tokenMetadata.id)
            savedTokens = try SavedTokenStore.shared.listMetadata()
        } catch {
            savedTokensError = error.localizedDescription
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
            if let error = validateLocationInputs() {
                showWarning("Invalid coordinate input", error)
                return
            }
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
            if let error = validateLocationInputs() {
                showWarning("Invalid coordinate input", error)
                return
            }
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
            runMigrationTemplateExport(
                token: t,
                baseURL: baseURL,
                outputURLOverride: selectedMigrationFileURL
            )
        }
    }

    private func validateLocationInputs() -> String? {
        for (i, row) in locationInputs.enumerated() {
            let joined = [row.locId, row.name, row.address, row.country, row.latitude, row.longitude]
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if joined.isEmpty {
                continue
            }

            let rowNumber = i + 1
            if locAction == .updateExisting,
               row.locId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Row \(rowNumber): LOC ID is required for updates."
            }

            if let latitudeError = validateCoordinate(
                value: row.latitude,
                min: -90,
                max: 90,
                label: "Latitude",
                rowNumber: rowNumber
            ) {
                return latitudeError
            }

            if let longitudeError = validateCoordinate(
                value: row.longitude,
                min: -180,
                max: 180,
                label: "Longitude",
                rowNumber: rowNumber
            ) {
                return longitudeError
            }
        }
        return nil
    }

    private func validateCoordinate(
        value: String,
        min: Double,
        max: Double,
        label: String,
        rowNumber: Int
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        guard let numeric = Double(trimmed) else {
            return "Row \(rowNumber): \(label) must be a numeric coordinate."
        }

        if numeric < min || numeric > max {
            return "Row \(rowNumber): \(label) must be between \(min) and \(max)."
        }

        return nil
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

    private func runMigrationTemplateExport(
        token: String,
        baseURL: String,
        outputURLOverride: URL?
    ) {
        Task { @MainActor in
            isRunning = true
            defer { isRunning = false }

            let outputURL: URL
            if let override = outputURLOverride {
                outputURL = override
            } else {
                let saveURL = await SavePanel.show(
                    title: "Save migration templates as…",
                    message: "Choose where to save the Excel file.",
                    defaultFileName: "03 - Production Migration Template.xlsx",
                    allowedFileExtensions: ["xlsx"]
                )

                guard let saveURL else { return }
                outputURL = saveURL
            }

            do {
                let didStartAccess = outputURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        outputURL.stopAccessingSecurityScopedResource()
                    }
                }

                if outputURLOverride != nil,
                   !FileManager.default.fileExists(atPath: outputURL.path) {
                    selectedMigrationFileURL = nil
                    showWarning(
                        "Selected file not found",
                        "The selected migration file could not be found. Please choose another file."
                    )
                    return
                }

                var backupURL: URL? = nil
                let requiredSheets = MigrationTemplateRunner.requiredSheets(for: migrationInputs)

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    if !requiredSheets.isEmpty {
                        let validation = try await MigrationTemplateRunner.validateTemplate(
                            at: outputURL,
                            sheets: requiredSheets
                        )

                        if !validation.ok {
                            let detail = MigrationTemplateRunner.formatValidationMessage(validation)
                            let message = """
The selected file does not match the official migration template.

\(detail)

Replace will back up the existing file and copy the official template into place.
"""
                            let decision = await promptTemplateMismatch(message)
                            if decision == .replace {
                                backupURL = try MigrationTemplateRunner.replaceWithBundledTemplate(at: outputURL)
                            } else {
                                return
                            }
                        }
                    }
                } else {
                    try MigrationTemplateRunner.copyBundledTemplate(to: outputURL)
                }

                let output = try await MigrationTemplateRunner.export(
                    baseURL: baseURL,
                    token: token,
                    inputs: migrationInputs,
                    outputURL: outputURL
                )

                let backupLine = backupURL.map { "\n\nBackup:\n\($0.path)" } ?? ""
                showInfo(
                    "Migration templates exported",
                    "Saved to:\n\(outputURL.path)\(backupLine)\n\n\(output)"
                )
            } catch {
                showWarning("Migration export error", error.localizedDescription)
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

    @MainActor
    private func promptTemplateMismatch(_ message: String) async -> TemplateDecision {
        await withCheckedContinuation { continuation in
            templateAlertBody = message
            templateDecisionContinuation = continuation
            showTemplateAlert = true
        }
    }
}

private struct SavedTokensMenuButton<PopoverContent: View>: View {
    let isVisible: Bool
    @Binding var isPresented: Bool
    let popoverContent: () -> PopoverContent

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popoverContent()
        }
    }
}

#Preview {
    ContentView()
}
