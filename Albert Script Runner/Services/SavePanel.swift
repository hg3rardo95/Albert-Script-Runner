//
//  SavePanel.swift
//  Albert Script Runner
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Small helper for showing a macOS save dialog (NSSavePanel)
/// and returning the selected file URL.
struct SavePanel {

    /// Shows a Save dialog.
    /// - Parameters:
    ///   - title: Window title.
    ///   - message: Helper message shown in the panel.
    ///   - defaultFileName: The suggested file name (e.g., "users.xlsx").
    ///   - allowedFileExtensions: File extensions without dots (e.g., ["xlsx"]).
    /// - Returns: Selected file URL, or `nil` if the user cancels.
    @MainActor
    static func show(
        title: String = "Save File",
        message: String = "Choose where to save the file.",
        defaultFileName: String,
        allowedFileExtensions: [String]
    ) async -> URL? {

        let panel = NSSavePanel()
        panel.title = title
        panel.message = message
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if !allowedFileExtensions.isEmpty {
            panel.allowedContentTypes = allowedFileExtensions.compactMap { ext in
                // UniformTypeIdentifiers is available on modern macOS, but using AppKit import already.
                // Convert file extension to UTType if possible; if not, the panel still works.
                if #available(macOS 11.0, *) {
                    return UTType(filenameExtension: ext)
                }
                return nil
            }
        }

        return await withCheckedContinuation { continuation in
            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
