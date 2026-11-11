import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ADI2Core

typealias ParameterKey = ParameterAddress

/// The first Store release exposes live control and local profiles only.
/// Internal memory protocol coverage opts in explicitly through fake transports.
struct ReleaseCapabilities: Sendable {
    let deviceMemory: Bool
    static let storeRelease = ReleaseCapabilities(deviceMemory: false)

    func permitsEQParameter(_ index: Int) -> Bool {
        deviceMemory || ![27,28].contains(index)
    }
    func permitsDeviceParameter(_ index: Int) -> Bool {
        // Remap-key choices include setup/preset recalls; omit that whole
        // family rather than changing the meaning of the device's enum values.
        deviceMemory || (!(25...29).contains(index) && index != 62)
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var profile = EQProfile.flat
    @Published var selectedOutput: Output = .phones
    @Published var deviceModel: DeviceModel = .dac {
        didSet { if oldValue != deviceModel && activeDevice != nil { disconnect() } }
    }
    @Published var demoMode = false
    @Published var connected = false
    @Published var status = "Connect an ADI-2, or explore the demo."
    @Published var errorMessage: String?
    @Published var importWarnings: [String] = []
    @Published var endpoints: [MIDIDevice] = []
    @Published var selectedEndpointID: Int32?
    @Published var lastSync: Date?
    @Published var values: [ParameterKey: Int] = [:]
    @Published var section = "output"
    @Published var eqSide = "left"
    @Published var hasDraft = false
    @Published var syncing = false
    @Published var channelNotice: String?
    private var accumulator: DeviceStateAccumulator?
    @Published var localProfiles: [SavedProfile] = []
    @Published var libraryWarnings: [String] = []
    @Published var selectedPresetSlot = 1
    @Published var presetName = ""
    @Published var selectedSetupSlot = 1
    private var demoPresets: [Int:EQProfile] = [:]
    private var demoSetups: [Int:[ParameterKey:Int]] = [:]
    private let library: FileProfileLibrary
    private let capabilities: ReleaseCapabilities
    var deviceMemoryAvailable: Bool { capabilities.deviceMemory }
    var availableOutputs: [Output] { deviceModel == .dac ? [.line,.phones] : Output.allCases }
    private let midi: MIDIConnection
    private var activeDevice: MIDIDevice?
    private var generation = 0
    private var drafts: [Output: EQProfile] = [:]
    private var syncTimeout: Task<Void, Never>?
    var canWrite: Bool { connected && !demoMode && !syncing && activeDevice?.model == deviceModel }
    var parameterAddress: Int { section == "device" ? 12 : section == "input" ? 0 : selectedOutput.channel }
    var eqParameterAddress: Int { section == "input" ? (eqSide == "right" ? 2 : 1) : (eqSide == "right" ? selectedOutput.right : selectedOutput.left) }
    var eqParameters: [ParameterDefinition] {
        ParameterRegistry.eq.filter {
            capabilities.permitsEQParameter($0.index) && (eqSide != "right" || (3...19).contains($0.index))
        }
    }
    func eqRealValue(_ p: ParameterDefinition) -> Double {
        guard let raw = values[ParameterKey(address:eqParameterAddress,index:p.index)] else { return p.defaultValue }
        return p.kind == "freq" ? Double(raw) : Double(raw) * p.increment
    }
    func setEQParameter(_ p: ParameterDefinition, value: Double) {
        guard capabilities.permitsEQParameter(p.index) else { return }
        guard eqSide != "right" || (3...19).contains(p.index) else { return }
        guard value.isFinite, (p.minimum...p.maximum).contains(value), demoMode || (canWrite && values[ParameterKey(address:eqParameterAddress,index:p.index)] != nil) else { return }
        do {
            let raw = Int((value / p.increment).rounded(.toNearestOrEven))
            let box = p.kind == "freq" ? try ADI2Protocol.encodeFrequency(address:eqParameterAddress,index:p.index,hz:value) : try ADI2Protocol.encode(address:eqParameterAddress,index:p.index,raw:raw)
            if !demoMode { try midi.send(ADI2Protocol.parameters(device:deviceModel.deviceID,containers:[box])) }
            let encoded = try ADI2Protocol.parseParameters(box).first!
            values[ParameterKey(address:eqParameterAddress,index:p.index)] = encoded.raw
            updateChannelNotice()
            if !hasDraft { readProfile() }
        } catch { errorMessage = error.localizedDescription; disconnect() }
    }
    var parameters: [ParameterDefinition] {
        if section == "device" {
            return ParameterRegistry.device(for: deviceModel).filter { capabilities.permitsDeviceParameter($0.index) }
        }
        return section == "input" ? ParameterRegistry.input(for: deviceModel) : ParameterRegistry.output(for: deviceModel, output: selectedOutput)
    }

    init(midi: MIDIConnection? = nil, library: FileProfileLibrary? = nil, capabilities: ReleaseCapabilities = .storeRelease) {
        self.capabilities = capabilities
        self.library = library ?? FileProfileLibrary(directory:(try? FileProfileLibrary.defaultDirectory()) ?? FileManager.default.temporaryDirectory.appendingPathComponent("ADI2Companion-Profiles"))
        self.midi = midi ?? CoreMIDILink()
        self.midi.onDevicesChanged = { [weak self] in self?.refreshDevices() }
        self.midi.onMessage = { [weak self] bytes in self?.receive(bytes) }
        refreshDevices()
        refreshProfiles()
    }
    func refreshDevices() {
        endpoints = midi.devices()
        if let activeDevice, !endpoints.contains(where: { $0 == activeDevice }) {
            disconnect(); status = "The ADI-2 was disconnected. Reconnect its USB cable."
        }
        if !endpoints.contains(where: { $0.id == selectedEndpointID }) { selectedEndpointID = endpoints.first?.id }
    }
    func connect() {
        guard let endpoint = endpoints.first(where: { $0.id == selectedEndpointID }) else {
            errorMessage = "No supported MIDI port found. Connect the ADI-2 by USB and enable Setup → Device Mode / DSD → MIDI Control."
            return
        }
        disconnect()
        demoMode = false; deviceModel = endpoint.model
        if deviceModel == .dac && selectedOutput == .phones34 { selectOutput(.phones) }
        if hasDraft { drafts[selectedOutput] = profile }
        values = [:]
        do {
            try midi.connect(endpoint)
            activeDevice = endpoint
            status = "Reading \(endpoint.name)…"
            requestSync()
        } catch { errorMessage = error.localizedDescription; disconnect() }
    }
    func disconnect() {
        generation += 1; syncTimeout?.cancel(); syncTimeout = nil
        midi.disconnect(); activeDevice = nil; connected = false; lastSync = nil; syncing = false; accumulator = nil; channelNotice = nil
        values = [:]
        status = demoMode ? "Demo mode. No hardware is being controlled." : "Disconnected. EQ editing is available offline."
    }
    func startDemo() {
        disconnect(); demoMode = true
        demoPresets = [1:.example]; demoSetups = [:]
        values = [:]; hasDraft = false; drafts = [:]
        for output in Output.allCases {
            for p in ParameterRegistry.output(for: deviceModel, output: output) {
                values[ParameterKey(address: output.channel, index: p.index)] = Int((p.defaultValue / p.increment).rounded(.toNearestOrEven))
            }
        }
        for p in ParameterRegistry.device(for: deviceModel) { values[ParameterKey(address:12,index:p.index)] = Int((p.defaultValue / p.increment).rounded(.toNearestOrEven)) }
        for p in ParameterRegistry.input(for:deviceModel) { values[ParameterKey(address:0,index:p.index)] = Int((p.defaultValue / p.increment).rounded(.toNearestOrEven)) }
        for address in [1,2,4,5,7,8,10,11] {
            for p in ParameterRegistry.eq { values[ParameterKey(address:address,index:p.index)] = Int((p.defaultValue / p.increment).rounded(.toNearestOrEven)) }
        }
        profile = .example; profile.output = selectedOutput; hasDraft = false
        if let parameters = try? ADI2Protocol.parseParameters(profile.containers().flatMap { $0 }) {
            for p in parameters { values[ParameterKey(address:p.address,index:p.index)] = p.raw }
        }
        status = "Demo mode. No hardware is being controlled."
    }
    func stopDemo() { demoMode = false; disconnect(); profile = .flat; profile.output = selectedOutput; hasDraft = false }
    func sync() { guard activeDevice != nil, !demoMode else { return }; requestSync() }
    private func requestSync() {
        guard let device = activeDevice else { return }
        generation += 1; let expected = generation
        syncing = true; accumulator = DeviceStateAccumulator(output:selectedOutput)
        syncTimeout?.cancel()
        do {
            try midi.send(ADI2Protocol.requestAll(device: device.model.deviceID))
            status = "Reading hardware settings…"
            syncTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, let self, self.generation == expected else { return }
                self.disconnect()
                self.errorMessage = "The ADI-2 did not return a complete EQ state. Enable MIDI Control on the device, close other MIDI control apps, then reconnect."
            }
        } catch { errorMessage = error.localizedDescription; disconnect() }
    }
    private func receive(_ bytes: [UInt8]) {
        guard !demoMode, let device = activeDevice, let message = ADI2Protocol.parse(bytes), message.device == device.model.deviceID, message.command == 1 else { return }
        do {
            let parameters = try ADI2Protocol.parseParameters(message.payload)
            if syncing {
                accumulator?.receive(parameters)
                guard let accumulator, accumulator.output == selectedOutput, accumulator.isComplete else { return }
                try accumulator.validate(device:deviceModel)
                _ = try accumulator.profile(right:true)
                values = accumulator.values
                self.accumulator = nil
                syncing = false
            } else {
                var candidate = values
                for p in parameters { candidate[ParameterKey(address:p.address,index:p.index)] = p.raw }
                try DeviceStateAccumulator(output:selectedOutput,values:candidate).validate(device:deviceModel)
                values = candidate
            }
            connected = true; lastSync = Date(); syncTimeout?.cancel()
            status = "Connected to \(device.name)"
            updateChannelNotice()
            if !hasDraft { readProfile() }
        } catch { errorMessage = error.localizedDescription; disconnect() }
    }
    private func updateChannelNotice() {
        var indices: [Int] = []
        for layout in EQProfile.layout {
            indices.append(contentsOf: [layout.gain, layout.frequency, layout.q])
            if let typeIndex = layout.type { indices.append(typeIndex) }
        }
        let differs = indices.contains(where: { index in
            values[ParameterKey(address:selectedOutput.left,index:index)] != values[ParameterKey(address:selectedOutput.right,index:index)]
        })
        channelNotice = differs ? "Left and right EQ differ. The editor shows the left channel; Apply EQ replaces both channels." : nil
    }
    private func readProfile() {
        do { profile = try DeviceStateAccumulator(output:selectedOutput, values:values).profile() }
        catch { errorMessage = error.localizedDescription; if !demoMode { disconnect() } }
    }
    func selectOutput(_ output: Output) {
        if hasDraft { drafts[selectedOutput] = profile }
        selectedOutput = output; section = "output"
        if let draft = drafts[output] { profile = draft; hasDraft = true }
        else { hasDraft = false; profile = .flat; profile.output = output; if demoMode { readProfile() } }
        importWarnings = []
        if activeDevice != nil && !demoMode { requestSync() }
    }
    func selectPresetOutput(_ output: Output) { selectOutput(output); section = "presets" }
    func refreshProfiles() {
        do { let listing = try library.list(); localProfiles = listing.profiles; libraryWarnings = listing.warnings }
        catch { libraryWarnings = [error.localizedDescription] }
    }
    func saveLocalProfile() {
        do {
            var saved = profile
            if saved.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { saved.name = "Untitled EQ" }
            _ = try library.save(saved); refreshProfiles()
            status = "Saved \(saved.name) in your Mac profile library."
        } catch { errorMessage = error.localizedDescription }
    }
    func loadLocalProfile(_ item: SavedProfile) {
        do {
            try item.profile.validate()
            profile = item.profile; profile.output = selectedOutput
            hasDraft = true; importWarnings = []; section = "output"
            status = "Loaded \(profile.name) as a draft for \(selectedOutput.title)."
        } catch { errorMessage = error.localizedDescription }
    }
    func saveDevicePreset() {
        var attempted = false
        do {
            try requireDeviceMemory()
            guard canWrite || demoMode else { throw ADI2Error.invalid("Connect and sync the ADI-2 before writing a device slot.") }
            let messages = try profile.presetMessages(device:deviceModel.deviceID,slot:selectedPresetSlot,name:presetName)
            if demoMode {
                var saved = profile
                saved.name = presetName.isEmpty ? "Preset \(selectedPresetSlot)" : presetName
                demoPresets[selectedPresetSlot] = saved
                status = "Saved demo EQ slot \(selectedPresetSlot). No MIDI was sent."
                return
            }
            for message in messages { attempted = true; try midi.send(message) }
            status = "EQ slot \(selectedPresetSlot) write sent. Recall it to verify the device memory."
        } catch {
            errorMessage = attempted ? "The EQ slot write may be incomplete. \(error.localizedDescription)" : error.localizedDescription
            if attempted { disconnect() }
        }
    }
    func loadDevicePreset() {
        var attempted = false
        do {
            try requireDeviceMemory()
            guard canWrite || demoMode else { throw ADI2Error.invalid("Connect and sync the ADI-2 before recalling a device slot.") }
            let message = try ADI2Protocol.loadEQPreset(device:deviceModel.deviceID,output:selectedOutput,slot:selectedPresetSlot)
            if demoMode {
                var loaded = demoPresets[selectedPresetSlot] ?? .flat
                loaded.output = selectedOutput
                // Device EQ slots replace bands; the live switches remain independent.
                profile.bands = loaded.bands; profile.name = loaded.name
                for p in try ADI2Protocol.parseParameters(profile.containers().flatMap { $0 }) { values[ParameterKey(address:p.address,index:p.index)] = p.raw }
                hasDraft = false; drafts[selectedOutput] = nil
                status = "Loaded demo EQ slot \(selectedPresetSlot). No MIDI was sent."
                return
            }
            attempted = true; try midi.send(message)
            hasDraft = false; drafts[selectedOutput] = nil; importWarnings = []
            requestSync()
        } catch { errorMessage = error.localizedDescription; if attempted { disconnect() } }
    }
    func saveDeviceSetup() {
        var attempted = false
        do {
            try requireDeviceMemory()
            guard canWrite || demoMode else { throw ADI2Error.invalid("Connect and sync the ADI-2 before saving a setup.") }
            let message = try ADI2Protocol.setup(device:deviceModel.deviceID,slot:selectedSetupSlot,save:true)
            if demoMode { demoSetups[selectedSetupSlot] = values; status = "Saved demo setup \(selectedSetupSlot). No MIDI was sent."; return }
            attempted = true; try midi.send(message)
            status = "Save setup \(selectedSetupSlot) command sent. Verify the slot on the device."
        } catch { errorMessage = error.localizedDescription; if attempted { disconnect() } }
    }
    func loadDeviceSetup() {
        var attempted = false
        do {
            try requireDeviceMemory()
            guard canWrite || demoMode else { throw ADI2Error.invalid("Connect and sync the ADI-2 before recalling a setup.") }
            let message = try ADI2Protocol.setup(device:deviceModel.deviceID,slot:selectedSetupSlot,save:false)
            if demoMode {
                guard let saved = demoSetups[selectedSetupSlot] else { throw ADI2Error.invalid("Save this demo setup before recalling it. Demo memory starts empty.") }
                values = saved; hasDraft = false; drafts = [:]; readProfile(); updateChannelNotice()
                status = "Loaded demo setup \(selectedSetupSlot). No MIDI was sent."; return
            }
            attempted = true; try midi.send(message)
            hasDraft = false; drafts = [:]; importWarnings = []
            requestSync()
        } catch { errorMessage = error.localizedDescription; if attempted { disconnect() } }
    }
    private func requireDeviceMemory() throws {
        guard deviceMemoryAvailable else { throw ADI2Error.invalid("Device memory operations are not available in this release.") }
    }
    func updateBand(index: Int, band: Band) {
        guard profile.bands.indices.contains(index) else { return }
        profile.bands[index] = band; hasDraft = true
    }
    func setEQEnabled(_ value: Bool) { profile.eqEnabled = value; hasDraft = true }
    func setBassTrebleEnabled(_ value: Bool) { profile.bassTrebleEnabled = value; hasDraft = true }
    func setLoudnessEnabled(_ value: Bool) { profile.loudnessEnabled = value; hasDraft = true }
    func loadFlat() { profile = .flat; profile.output = selectedOutput; importWarnings = []; hasDraft = true }
    func loadExample() { profile = .example; profile.output = selectedOutput; importWarnings = []; hasDraft = true }
    func applyProfile() {
        var attemptedWrite = false
        do {
            try profile.validate()
            if demoMode {
                for p in try ADI2Protocol.parseParameters(profile.containers().flatMap { $0 }) { values[ParameterKey(address:p.address,index:p.index)] = p.raw }
                status = "Demo EQ applied. No MIDI was sent."; hasDraft = false; drafts[selectedOutput] = nil; return
            }
            guard canWrite else { throw ADI2Error.invalid("Connect and sync the ADI-2 before applying EQ.") }
            let containers = try profile.containers()
            for start in stride(from:0,to:containers.count,by:80) {
                attemptedWrite = true
                try midi.send(ADI2Protocol.parameters(device:deviceModel.deviceID, containers:Array(containers[start..<min(start+80,containers.count)])))
            }
            hasDraft = false; drafts[selectedOutput] = nil
            sync()
        } catch {
            hasDraft = true; errorMessage = error.localizedDescription
            if attemptedWrite { disconnect() }
        }
    }
    func realValue(_ p: ParameterDefinition) -> Double {
        guard let raw = values[ParameterKey(address:parameterAddress,index:p.index)] else { return p.defaultValue }
        return p.kind == "freq" ? Double(raw) : Double(raw) * p.increment
    }
    func setParameter(_ p: ParameterDefinition, value: Double) {
        guard parameterAddress != 12 || capabilities.permitsDeviceParameter(p.index) else { return }
        // Read-only sample-rate display, missing state and out-of-range edits never write.
        guard !(parameterAddress == 12 && p.index == 16), value.isFinite, (p.minimum...p.maximum).contains(value) else { return }
        guard demoMode || (canWrite && values[ParameterKey(address:parameterAddress,index:p.index)] != nil) else { return }
        let raw = Int((value / p.increment).rounded(.toNearestOrEven))
        do {
            if !demoMode {
                let box = parameterAddress == 12 ? try ADI2Protocol.encodeDevice(index:p.index,raw:raw) : p.kind == "freq" ? try ADI2Protocol.encodeFrequency(address:parameterAddress,index:p.index,hz:value) : try ADI2Protocol.encode(address:parameterAddress,index:p.index,raw:raw)
                try midi.send(ADI2Protocol.parameters(device:deviceModel.deviceID,containers:[box]))
            }
            values[ParameterKey(address:parameterAddress,index:p.index)] = p.kind == "freq" ? Int(value) : raw
        } catch { errorMessage = error.localizedDescription; disconnect() }
    }
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json,.plainText,.commaSeparatedText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000 else { throw ADI2Error.invalid("Choose an EQ file smaller than 2 MB.") }
            let data = try Data(contentsOf:url,options:.mappedIfSafe)
            guard data.count <= 2_000_000, let text = String(data:data,encoding:.utf8) else { throw ADI2Error.invalid("Choose a UTF-8 EQ file smaller than 2 MB.") }
            let result = try EQImporter.parse(text:text,name:url.deletingPathExtension().lastPathComponent,output:selectedOutput)
            profile = result.profile; importWarnings = result.warnings; hasDraft = true
            status = "Imported EQ draft. Review the bands, then apply when ready."
        } catch { errorMessage = error.localizedDescription }
    }
    func exportProfile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            try profile.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(profile).write(to:url,options:.atomic)
            status = "Saved \(url.lastPathComponent)."
        } catch { errorMessage = error.localizedDescription }
    }
}
