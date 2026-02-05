//
//  SavedTokenAddSheetView.swift
//  Albert Script Runner
//

import SwiftUI

struct SavedTokenAddSheetView: View {
    @Binding var tokenLabel: String
    @Binding var tokenValue: String
    @Binding var selectedEnv: Environment
    let errorMessage: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedToken: String {
        tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tokenSummary: JwtSummary? {
        guard !trimmedToken.isEmpty else { return nil }
        return decodeJwtSummary(trimmedToken)
    }

    private var tokenIsExpired: Bool {
        guard let exp = tokenSummary?.expiresAt else { return false }
        return exp < Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Saved Token")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("Name", text: $tokenLabel)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Environment")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Picker("", selection: $selectedEnv) {
                    ForEach(Environment.allCases) { env in
                        Text(env.rawValue).tag(env)
                    }
                }
                .frame(width: 180, alignment: .leading)
            }

            Text("JWT")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextEditor(text: $tokenValue)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            if !trimmedToken.isEmpty {
                if let summary = tokenSummary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tenant ID: \(summary.tenantId ?? "Unknown")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(expiryText(for: summary.expiresAt))
                            .font(.caption)
                            .foregroundStyle(tokenIsExpired ? .red : .secondary)
                    }
                } else {
                    Text("Invalid token.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Text("If Name is left blank, it will be auto-generated as tenantId | base_url.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420)
    }

    private func expiryText(for date: Date?) -> String {
        guard let date else { return "Expires: —" }

        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 {
            return "Expired"
        }

        let hours = Int(ceil(seconds / 3600))
        if hours < 24 {
            let unit = hours == 1 ? "hour" : "hours"
            return "Expires in \(hours) \(unit)"
        }

        let days = Int(ceil(seconds / 86400))
        let unit = days == 1 ? "day" : "days"
        return "Expires in \(days) \(unit)"
    }
}
