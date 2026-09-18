import SwiftUI
import UIKit
import MeditationCore

struct AudioCatalogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var profileName = ""
    @State private var showingSaveProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.catalog.catalogProfiles) { profile in
                        Button {
                            model.apply(profile)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(.headline)
                                Text(profile.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Sesiones preparadas") }

                if !model.catalog.savedProfiles.isEmpty {
                    Section("Mis perfiles") {
                        ForEach(model.catalog.savedProfiles) { profile in
                            Button(profile.name) {
                                model.apply(profile)
                                dismiss()
                            }
                            .swipeActions {
                                Button("Eliminar", role: .destructive) { model.deleteProfile(id: profile.id) }
                            }
                        }
                    }
                }

                Section {
                    ForEach(model.catalog.tracks) { track in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title).font(.headline)
                                    Text(track.detail).font(.caption).foregroundStyle(.secondary)
                                    Text(durationLabel(track.durationSeconds))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: model.catalog.isAvailable(track) ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                                    .foregroundStyle(model.catalog.isAvailable(track) ? Palette.green : .secondary)
                            }
                            HStack {
                                Button("Vista previa", systemImage: "play.fill") {
                                    Task { await model.catalog.togglePreview(track) }
                                }
                                .buttonStyle(.bordered)
                                if !model.catalog.isAvailable(track) {
                                    Button(model.catalog.isDownloading.contains(track.id) ? "Descargando…" : "Descargar") {
                                        Task {
                                            do { _ = try await model.catalog.download(track) }
                                            catch { model.error = error.localizedDescription }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.catalog.isDownloading.contains(track.id))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: { Text("Audios") } footer: {
                    Text("Los audios descargados se verifican antes de activarse y quedan disponibles sin conexión.")
                }

                Section {
                    Button("Guardar la configuración actual como perfil", systemImage: "bookmark") {
                        showingSaveProfile = true
                    }
                }

                Section {
                    TextField("https://…/catalog.json", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Button(model.catalog.isRefreshing ? "Actualizando…" : "Guardar y actualizar") {
                        model.catalog.saveEndpoint(endpoint)
                        Task { await model.catalog.refresh() }
                    }
                    .disabled(model.catalog.isRefreshing)
                    if let message = model.catalog.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Actualizaciones sin App Store") } footer: {
                    Text("Esta dirección se configura una vez. Después, publicar un catálogo nuevo añade audios y perfiles sin actualizar la app.")
                }
            }
            .navigationTitle("Audios y perfiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear { endpoint = model.catalog.endpoint }
            .onDisappear { model.catalog.stopPreview() }
            .alert("Guardar perfil", isPresented: $showingSaveProfile) {
                TextField("Nombre", text: $profileName)
                Button("Guardar") {
                    model.saveCurrentProfile(named: profileName)
                    profileName = ""
                }
                Button("Cancelar", role: .cancel) { profileName = "" }
            } message: {
                Text("Guardará duración y audios.")
            }
        }
    }

    private func durationLabel(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return "\(rounded / 60) min \(rounded % 60) s"
    }
}

struct ProfileStrip: View {
    @Environment(AppModel.self) private var model
    let showCatalog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Perfiles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Ver todos") { showCatalog() }.font(.caption)
            }
            ForEach(model.catalog.catalogProfiles.prefix(2)) { profile in
                Button {
                    model.apply(profile)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.subheadline.weight(.medium))
                            Text(profile.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(13)
                    .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
