//
//  SavedTokensPopoverView.swift
//  Albert Script Runner
//

import SwiftUI

struct SavedTokensPopoverView: View {
    @SwiftUI.Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isUnlocked: Bool
    let isAuthenticating: Bool
    let tokens: [SavedTokenMetadata]
    let errorMessage: String?
    let onUnlock: () -> Void
    let onSelect: (SavedTokenMetadata) -> Void
    let onRename: (SavedTokenMetadata) -> Void
    let onDelete: (SavedTokenMetadata) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Tokens")
                    .font(.headline)

                Spacer()

                if isAuthenticating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Authenticating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isUnlocked {
                if tokens.isEmpty {
                    Text("No saved tokens yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(tokens) { token in
                        SavedTokenTileView(
                            token: token,
                            onSelect: {
                                onSelect(token)
                            },
                            onRename: {
                                onRename(token)
                            },
                            onDelete: {
                                onDelete(token)
                            }
                        )
                    }

                    SavedTokenAddTileView {
                        onAdd()
                    }
                }
            } else {
                VStack {
                    Spacer(minLength: 10)

                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text("Saved tokens are protected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("View Saved Tokens") {
                            onUnlock()
                        }
                        .keyboardShortcut(.defaultAction)

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if isAuthenticating {
                            Text("Waiting for authentication…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 10)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 420, idealWidth: 520)
        .background(
            Group {
                if reduceTransparency {
                    Color(.windowBackgroundColor).opacity(0.9)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
        )
        .cornerRadius(12)
    }
}

private struct SavedTokenTileView: View {
    let token: SavedTokenMetadata
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(token.label.isEmpty ? "Unnamed Token" : token.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                TimelineView(.periodic(from: Date(), by: 60)) { context in
                    Text(expiryText(for: token.expiresAt, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(minWidth: 120, minHeight: 70, alignment: .leading)

            if hovering {
                Menu {
                    Button("Rename") {
                        onRename()
                    }
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .background(.thinMaterial)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.hovering = hovering
            }
        }
    }

    private func expiryText(for date: Date?, now: Date) -> String {
        guard let date else { return "Expires: —" }

        let seconds = date.timeIntervalSince(now)
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

private struct SavedTokenAddTileView: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title2)
                Text("Add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 120, minHeight: 70)
            .background(.thinMaterial)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
