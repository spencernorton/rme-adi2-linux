import SwiftUI
import ADI2Core

// Explicit wrapper name also supports Command Line Tools SDKs that omit SwiftUI macros.
private typealias PresetViewState<Value> = SwiftUI.State<Value>

struct PresetsView: View {
    @ObservedObject var model: AppModel
    @PresetViewState<Bool> private var confirmLoadPreset = false
    @PresetViewState<Bool> private var confirmSavePreset = false
    @PresetViewState<Bool> private var confirmLoadSetup = false
    @PresetViewState<Bool> private var confirmSaveSetup = false

    private var canUseDeviceMemory: Bool { model.deviceMemoryAvailable && (model.canWrite || model.demoMode) }
    private var presetNameIsValid: Bool {
        model.presetName.utf8.count <= 14 && model.presetName.unicodeScalars.allSatisfy { (32...126).contains($0.value) }
    }
    private var currentProfileName: String {
        let name = model.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Profiles")
                    .font(.largeTitle.weight(.semibold))
                Text("Keep EQ profiles in a local library on this Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                Text("Destination output").font(.callout.weight(.medium))
                Picker("Destination output", selection: Binding(get: { model.selectedOutput }, set: model.selectPresetOutput)) {
                    ForEach(model.availableOutputs, id: \.self) { output in
                        Text(output.title).tag(output)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 430)
                .disabled(model.syncing)
                Spacer(minLength: 0)
            }
            localLibrary
            if model.deviceMemoryAvailable {
                deviceMemory
            }
        }
        .onAppear(perform: model.refreshProfiles)
    }

    private var localLibrary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current profile name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Untitled", text: $model.profile.name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Local profile name")
                    }
                    Button("Save to library", action: model.saveLocalProfile)
                        .help("Save the current EQ bands and switches on this Mac")
                    Button(action: model.refreshProfiles) {
                        Label("Refresh library", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .help("Refresh the saved profiles")
                }
                Text("Local profiles include all five bands and the EQ, Bass / Treble and Loudness switches. Loading stages a draft for \(model.selectedOutput.title); Apply EQ sends it to your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                if model.localProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your first profile starts with the current EQ.")
                            .font(.callout.weight(.medium))
                        Text("Give it a name and choose Save to library. You can also import an existing EQ file from the toolbar.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.localProfiles, id: \.id) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                    Text(item.profile.name.isEmpty ? "Untitled" : item.profile.name)
                                        .font(.body)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .help(item.profile.name)
                                    Button("Load draft") { model.loadLocalProfile(item) }
                                        .accessibilityLabel("Load \(item.profile.name) as an EQ draft for \(model.selectedOutput.title)")
                                }
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                    .frame(height: min(250, CGFloat(model.localProfiles.count) * 49))
                    .accessibilityLabel("Saved local EQ profiles")
                }
                if !model.libraryWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Library notices", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.medium))
                        ForEach(Array(model.libraryWarnings.prefix(8).enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if model.libraryWarnings.count > 8 {
                            Text("\(model.libraryWarnings.count - 8) more library notices.")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
        } label: {
            Label("Local profile library", systemImage: "folder")
                .font(.headline)
        }
    }

    private var deviceMemory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Device memory").font(.title2.weight(.semibold))
                Text("Experimental")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.10), in: Capsule())
                Spacer()
            }
            Text(model.demoMode ? "Demo mode simulates device memory. No MIDI is sent." : "Device memory operations have not yet been verified with connected hardware.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                eqMemory
                setupMemory
            }
            if !canUseDeviceMemory {
                Label("Connect and sync your ADI-2 to use device memory, or explore the demo.", systemImage: "cable.connector")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Load EQ preset \(model.selectedPresetSlot) on \(model.selectedOutput.title)?", isPresented: $confirmLoadPreset, titleVisibility: .visible) {
            Button("Load EQ preset \(model.selectedPresetSlot) on \(model.selectedOutput.title)", action: model.loadDevicePreset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes the live output EQ and replaces the current editor draft.")
        }
        .confirmationDialog("Overwrite EQ preset \(model.selectedPresetSlot)?", isPresented: $confirmSavePreset, titleVisibility: .visible) {
            Button("Save \(model.selectedOutput.title) draft to EQ preset \(model.selectedPresetSlot)", role: .destructive, action: model.saveDevicePreset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replace this device slot with the five EQ bands from “\(currentProfileName)”. Bass / Treble and Loudness settings are not saved in this operation.")
        }
        .confirmationDialog("Load device setup \(model.selectedSetupSlot)?", isPresented: $confirmLoadSetup, titleVisibility: .visible) {
            Button("Load device setup \(model.selectedSetupSlot)", action: model.loadDeviceSetup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Loading a setup can change volume, routing and settings across the whole device. It also replaces the current editor state.")
        }
        .confirmationDialog("Overwrite device setup \(model.selectedSetupSlot)?", isPresented: $confirmSaveSetup, titleVisibility: .visible) {
            Button("Save current device to setup \(model.selectedSetupSlot)", role: .destructive, action: model.saveDeviceSetup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the slot with the settings currently on your ADI-2. Unapplied EQ drafts are not included.")
        }
    }

    private var eqMemory: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("EQ preset", selection: $model.selectedPresetSlot) {
                    ForEach(1...20, id: \.self) { Text("Slot \($0)").tag($0) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preset name").font(.caption).foregroundStyle(.secondary)
                    TextField("Optional", text: $model.presetName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Device EQ preset name, up to fourteen printable ASCII characters")
                    Text(presetNameIsValid ? "Up to 14 ASCII characters; a blank name is allowed." : "Use up to 14 printable ASCII characters.")
                        .font(.caption)
                        .foregroundStyle(presetNameIsValid ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Loads onto \(model.selectedOutput.title). Saves use only the five bands in the current editor draft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Load EQ slot onto \(model.selectedOutput.title)") { confirmLoadPreset = true }
                    .disabled(!canUseDeviceMemory)
                Button("Save draft to EQ slot…") { confirmSavePreset = true }
                    .disabled(!canUseDeviceMemory || !presetNameIsValid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        } label: {
            Label("20 EQ presets", systemImage: "slider.horizontal.3").font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var setupMemory: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Device setup", selection: $model.selectedSetupSlot) {
                    ForEach(1...9, id: \.self) { Text("Setup \($0)").tag($0) }
                }
                Text("Setups store device-wide settings, including volume and routing. Saving uses the settings currently on the hardware.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Load device setup…") { confirmLoadSetup = true }
                    .disabled(!canUseDeviceMemory)
                Button("Save device setup…") { confirmSaveSetup = true }
                    .disabled(!canUseDeviceMemory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        } label: {
            Label("9 device setups", systemImage: "dial.low").font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
