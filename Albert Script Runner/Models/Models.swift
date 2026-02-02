//
//  Models.swift
//  Albert Script Runner
//

import Foundation

// MARK: - Environment

enum Environment: String, CaseIterable, Identifiable {
    case sandbox = "Sandbox"
    case production = "Production"
    case dev = "Dev"

    var id: String { rawValue }

    /// Equivalent to your Python getBaseURL(env)
    var baseURL: String {
        switch self {
        case .sandbox:
            return "https://sandbox.albertinvent.com"
        case .production:
            return "https://app.albertinvent.com"
        case .dev:
            return "https://dev.albertinventdev.com/"
        }
    }
}

// MARK: - Top-level action selection

enum AppAction: String, CaseIterable, Identifiable {
    case downloadUsers = "Download All Users"
    case addLocations = "Locations Manager"
    case migration = "Delivery Tracker and Migration Tool"

    var id: String { rawValue }
}

// MARK: - Universal Run Button Intent

enum RunIntent: Equatable {
    case none
    case downloadUsers
    case listLocations
    case uploadLocations
    case updateLocations
    case migration
}

extension AppAction {
    func runIntent(locAction: LocationAction?) -> RunIntent {
        switch self {
        case .downloadUsers:
            return .downloadUsers
        case .addLocations:
            // Locations Manager uses the inner segmented control to decide intent.
            return (locAction == .updateExisting) ? .updateLocations : .uploadLocations
        case .migration:
            return .migration
        }
    }

    func runButtonTitle(locAction: LocationAction?) -> String {
        switch runIntent(locAction: locAction) {
        case .downloadUsers:
            return "Download Users"
        case .uploadLocations:
            return "Upload Locations"
        case .updateLocations:
            return "Update Locations"
        case .migration:
            return "Download Migration Data"
        case .listLocations:
            return "Refresh Locations"
        case .none:
            return "Run Script"
        }
    }
}

extension RunIntent {
    var requiresTokenAndEnv: Bool {
        switch self {
        case .none:
            return false
        default:
            return true
        }
    }
}

// MARK: - Location action selection (inside Locations Manager)

enum LocationAction: String, CaseIterable, Identifiable {
    case uploadNew = "Upload New Location"
    case updateExisting = "Update Existing Location"

    var id: String { rawValue }
}

// MARK: - Location DTO (decoded from Python JSON)

struct LocationDTO: Identifiable, Codable {
    /// Server-provided id from Albert (e.g., LOC1)
    var remoteId: String?
    var name: String?
    var address: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?

    // Stable identity: prefer server id when available, otherwise use a generated UUID per decode
    private let generatedUUID: String = UUID().uuidString
    var id: String { (remoteId?.isEmpty == false) ? remoteId! : generatedUUID }

    /// Convenience for UI rendering (shows the LOC id if present)
    var idValueForUI: String { remoteId ?? "" }

    enum CodingKeys: String, CodingKey {
        case remoteId = "id"
        case name, address, country, latitude, longitude
    }
}

// MARK: - Location Inputs (UI state)

struct LocationInputRow: Identifiable {
    let id = UUID()

    /// Used only for updates (LOC id)
    var locId: String = ""

    var name: String = ""
    var address: String = ""
    var country: String = ""

    /// Keep as String for UI entry; we’ll validate/convert before calling Python
    var latitude: String = ""
    var longitude: String = ""
}

// MARK: - Shared UI messages

struct UIMessage {
    var title: String
    var body: String
}
