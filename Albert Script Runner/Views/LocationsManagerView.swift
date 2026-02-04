//
//  LocationsManagerView.swift
//  Albert Script Runner
//
//  Created by Gerardo on 1/7/26.
//

import SwiftUI

struct LocationsManagerView: View {
    // Bindings from ContentView
    @Binding var existingLocations: [LocationDTO]
    @Binding var isLoadingLocations: Bool
    @Binding var locationsError: String
    @Binding var locAction: LocationAction
    @Binding var locationInputs: [LocationInputRow]

    var onRefresh: () -> Void

    // MARK: - Inputs helpers

    private func addInputRow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            locationInputs.append(LocationInputRow())
        }
    }

    private func removeInputRow(id: UUID) {
        guard let idx = locationInputs.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if locationInputs.count > 1 {
                locationInputs.remove(at: idx)
            } else {
                locationInputs = [LocationInputRow()]
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Locations Manager")
                    .font(.headline)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingLocations {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoadingLocations ? "Loading…" : "Refresh")
                    }
                }
                .disabled(isLoadingLocations)
            }

            HStack(spacing: 8) {
                Text("Existing Locations (read-only)")
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Loaded: \(existingLocations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !locationsError.isEmpty {
                Text(locationsError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack(alignment: .top, spacing: 12) {
                // LEFT: Existing Locations list
                VStack(alignment: .leading, spacing: 8) {
                    ExistingLocationsList(existingLocations: existingLocations)
                }
                .frame(maxWidth: .infinity)

                // RIGHT: Input panel
                VStack(alignment: .leading, spacing: 10) {
                    Text("Inputs")
                        .font(.headline)

                    Picker("", selection: $locAction) {
                        ForEach(LocationAction.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)

                    LocationInputEditor(
                        locAction: $locAction,
                        locationInputs: $locationInputs,
                        onRemove: removeInputRow,
                        onAdd: addInputRow
                    )
                    .frame(minHeight: 420)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    )

                    Text ("(Deleting capability update will be reserved for future versions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 420)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .cornerRadius(10)
    }
}
private struct ExistingLocationsList: View {
    let existingLocations: [LocationDTO]

    var body: some View {
        List(existingLocations) { loc in
            ExistingLocationRow(loc: loc)
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 420)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25))
        )
    }
}

private struct ExistingLocationRow: View {
    let loc: LocationDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(loc.idValueForUI) | \(loc.name ?? "")")
                .font(.system(.headline, design: .monospaced))

            if let address = loc.address, !address.isEmpty {
                Text("\tAddress: \(address)")
            }
            if let country = loc.country, !country.isEmpty {
                Text("\tCountry: \(country)")
            }
            if let lat = loc.latitude {
                Text("\tLatitude: \(lat)")
            }
            if let lon = loc.longitude {
                Text("\tLongitude: \(lon)")
            }
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocationInputEditor: View {
    @Binding var locAction: LocationAction
    @Binding var locationInputs: [LocationInputRow]

    var onRemove: (UUID) -> Void
    var onAdd: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach($locationInputs) { $row in
                    LocationInputCard(
                        row: $row,
                        canRemove: locationInputs.count > 1,
                        showIdField: locAction == .updateExisting
                    ) {
                        onRemove(row.id)
                    }
                    .animation(.easeInOut(duration: 0.3), value: locAction)
                }

                HStack(spacing: 10) {
                    Button("+") {
                        onAdd()
                    }

                    Button("-") {
                        // Remove the most recently added row
                        if let lastId = locationInputs.last?.id {
                            onRemove(lastId)
                        }
                    }
                    .disabled(locationInputs.count <= 1)
                }
                .padding(.top, 2)
            }
            .animation(.easeInOut(duration: 0.3), value: locationInputs.count)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
    }
}

private struct LocationInputCard: View {
    @Binding var row: LocationInputRow
    var canRemove: Bool
    var showIdField: Bool
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Location")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove") {
                    onRemove()
                }
                .disabled(!canRemove)
            }

            if showIdField {
                TextField("LOC ID (required for update)", text: $row.locId)
                    .textFieldStyle(.roundedBorder)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TextField("Name", text: $row.name)
                .textFieldStyle(.roundedBorder)
            TextField("Address", text: $row.address)
                .textFieldStyle(.roundedBorder)
            TextField("Country", text: $row.country)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Latitude", text: $row.latitude)
                    .textFieldStyle(.roundedBorder)
                TextField("Longitude", text: $row.longitude)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .cornerRadius(10)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }
}
