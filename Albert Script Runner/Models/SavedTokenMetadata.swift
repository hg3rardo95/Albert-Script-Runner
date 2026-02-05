//
//  SavedTokenMetadata.swift
//  Albert Script Runner
//

import Foundation

struct SavedTokenMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var tenantId: String
    var baseURL: String
    var expiresAt: Date?
    var createdAt: Date
}
