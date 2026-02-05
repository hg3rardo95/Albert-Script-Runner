//
//  MigrationFileBookmarkStore.swift
//  Albert Script Runner
//

import Foundation

enum MigrationFileBookmarkError: LocalizedError {
    case saveFailed
    case resolveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Unable to save the file reference."
        case .resolveFailed:
            return "Unable to restore the saved file reference."
        }
    }
}

final class MigrationFileBookmarkStore {
    static let shared = MigrationFileBookmarkStore()

    private let key = "migrationFileBookmark"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: key)
    }

    func loadURL() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try? save(url: url)
            }

            return url
        } catch {
            clear()
            return nil
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
