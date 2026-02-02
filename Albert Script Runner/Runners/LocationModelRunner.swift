//
//  LocationModelRunner.swift
//  Albert Script Runner
//
//  Created by Gerardo on 1/8/26.
//

import Foundation

/// Orchestrates location-related python-engine calls.
///
/// IMPORTANT: This type does NOT show alerts or mutate SwiftUI state.
/// It returns structured results so Views/ViewModels can decide how to present them.
struct LocationModelRunner {

    // MARK: - Types

    struct UploadLocationResult: Codable, Hashable {
        let name: String?
        let status: String?
        let id: String?
        let error: String?

        var isFailed: Bool {
            (status ?? "").lowercased() == "failed"
        }

        var displayName: String {
            let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "(unknown)" : n
        }

        var displayError: String {
            let e = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? "Unknown error" : e
        }
    }

    struct UpdateLocationResult: Codable, Hashable {
        let index: Int?
        let id: String?
        let name: String?
        let status: String?
        let error: String?

        var isFailed: Bool {
            (status ?? "").lowercased() == "failed"
        }

        var displayId: String {
            let v = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? "(missing id)" : v
        }

        var displayName: String {
            let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "(unknown)" : n
        }

        var displayError: String {
            let e = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? "Unknown error" : e
        }
    }

    // MARK: - Public API

    /// Upload new locations (partial success) using python-engine:
    /// `engine.py upload-locations --token ... --base-url ... --in <jsonfile>`
    static func uploadNewLocations(
        baseURL: String,
        token: String,
        rows: [LocationInputRow]
    ) async throws -> [UploadLocationResult] {

        let payload = buildUploadPayload(from: rows)
        if payload.isEmpty {
            return []
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let inURL = tmpDir.appendingPathComponent("locations_upload_\(UUID().uuidString).json")

        // Write JSON input file
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: inURL, options: [.atomic])

        // Run python + decode results off the main actor
        return try await Task.detached {
            let output = try PythonRunner.run(args: [
                "upload-locations",
                "--token", token,
                "--base-url", baseURL,
                "--in", inURL.path
            ])

            let outData = Data(output.utf8)
            return try JSONDecoder().decode([UploadLocationResult].self, from: outData)
        }.value
    }

    /// Update existing locations (partial success) using python-engine:
    /// `engine.py update-locations --token ... --base-url ... --in <jsonfile>`
    static func updateExistingLocations(
        baseURL: String,
        token: String,
        rows: [LocationInputRow]
    ) async throws -> [UpdateLocationResult] {

        let payload = buildUpdatePayload(from: rows)
        if payload.isEmpty {
            return []
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let inURL = tmpDir.appendingPathComponent("locations_update_\(UUID().uuidString).json")

        // Write JSON input file
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: inURL, options: [.atomic])

        // Run python + decode results off the main actor
        return try await Task.detached {
            let output = try PythonRunner.run(args: [
                "update-locations",
                "--token", token,
                "--base-url", baseURL,
                "--in", inURL.path
            ])

            let outData = Data(output.utf8)
            return try JSONDecoder().decode([UpdateLocationResult].self, from: outData)
        }.value
    }

    // MARK: - Helpers

    /// Build the JSON rows Swift sends to python-engine.
    /// Keep latitude/longitude as strings; python coerces safely.
    private static func buildUploadPayload(from rows: [LocationInputRow]) -> [[String: String]] {
        // Drop completely empty rows
        let nonEmpty = rows.filter { row in
            let joined = [row.locId, row.name, row.address, row.country, row.latitude, row.longitude]
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !joined.isEmpty
        }

        return nonEmpty.map { row in
            [
                "name": row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                "address": row.address.trimmingCharacters(in: .whitespacesAndNewlines),
                "country": row.country.trimmingCharacters(in: .whitespacesAndNewlines),
                "latitude": row.latitude.trimmingCharacters(in: .whitespacesAndNewlines),
                "longitude": row.longitude.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
        }
    }

    /// Build the JSON rows Swift sends to python-engine for updates.
    /// Keep latitude/longitude as strings; python coerces safely.
    private static func buildUpdatePayload(from rows: [LocationInputRow]) -> [[String: String]] {
        // Drop completely empty rows
        let nonEmpty = rows.filter { row in
            let joined = [row.locId, row.name, row.address, row.country, row.latitude, row.longitude]
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !joined.isEmpty
        }

        return nonEmpty.map { row in
            let obj: [String: String] = [
                // For updates, python accepts "id" (or "ID"). We'll always send "id".
                "id": row.locId.trimmingCharacters(in: .whitespacesAndNewlines),
                "name": row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                "address": row.address.trimmingCharacters(in: .whitespacesAndNewlines),
                "country": row.country.trimmingCharacters(in: .whitespacesAndNewlines),
                "latitude": row.latitude.trimmingCharacters(in: .whitespacesAndNewlines),
                "longitude": row.longitude.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            return obj
        }
    }
}

