import SwiftUI
import ADI2Core

// Use the property wrapper explicitly; the newer SDK also exports a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum InstrumentStyle {
    static let bandColors: [Color] = [.blue, .teal, .orange, .purple, .pink]
    static let blue = Color(red: 0.14, green: 0.49, blue: 0.83)
}

struct ControlView: View {
    @ObservedObject var model: AppModel
    @ViewState<Bool> private var showHelp = false
    @ViewState<Bool> private var showAdvanced = false
    @ViewState<Bool> private var showChannelEQ = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 290)
        } detail: {
            VStack(spacing: 0) {
                connectionBanner
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.section == "presets" {
                            PresetsView(model: model)
                        } else {
                            heading
                            if model.section == "output" {
                                outputControls
                                equalizer
                                profileActions
                                channelEQControls
                                DisclosureGroup("All output parameters", isExpanded: $showAdvanced) {
                                    parameterList
                                        .padding(.top, 12)
                                }
                                .font(.headline)
                            } else {
                                parameterList
                                if model.section == "input" { channelEQControls }
                            }
                        }
                        Text("Independent software for RME ADI-2 hardware. Not affiliated with or endorsed by RME.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(28)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItemGroup {
                    Button(action: model.importProfile) { Label("Import EQ", systemImage: "square.and.arrow.down") }
                        .keyboardShortcut("o", modifiers: .command)
                        .help("Import a profile, Equalizer APO text, or CSV")
                    Button(action: model.exportProfile) { Label("Export EQ", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                    Divider()
                    Button(action: model.sync) { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(!model.connected || model.syncing)
                        .help("Read the current settings from your ADI-2")
                    Button { showHelp = true } label: { Label("Connection help", systemImage: "questionmark.circle") }
                }
            }
        }
        .tint(InstrumentStyle.blue)
        .frame(minWidth: 1000, minHeight: 700)
        .alert("ADI-2 Companion", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showHelp) { connectionHelp }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List {
                Section("Outputs") {
                    outputItem(.line, icon: "hifispeaker.2")
                    outputItem(.phones, icon: "headphones")
                    if model.deviceModel != .dac {
                        outputItem(.phones34, icon: "headphones")
                    }
                }
                Section("Hardware") {
                    sidebarItem("Device settings", icon: "dial.low", section: "device")
                    if model.deviceModel != .dac {
                        sidebarItem("Analog input", icon: "waveform.path", section: "input")
                    }
                }
                Section("Profiles") {
                    sidebarItem("Local profiles", icon: "folder", section: "presets")
                    Button { model.section = "output"; model.loadFlat() } label: { Label("Flat response", systemImage: "line.diagonal") }
                    Button { model.section = "output"; model.loadExample() } label: { Label("Example EQ", systemImage: "slider.horizontal.3") }
                }
            }
            .listStyle(.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label(model.demoMode ? "Demo hardware" : "USB MIDI", systemImage: model.demoMode ? "play.rectangle" : "cable.connector")
                    .font(.headline)
                if model.connected {
                    Text(model.endpoints.first(where: { $0.id == model.selectedEndpointID })?.name ?? model.deviceModel.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Disconnect", action: model.disconnect)
                        .frame(maxWidth: .infinity)
                } else if model.demoMode {
                    Text("Explore every control without sending MIDI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Exit demo", action: model.stopDemo)
                        .frame(maxWidth: .infinity)
                } else {
                    Picker("Device", selection: $model.selectedEndpointID) {
                        Text("Select a device").tag(nil as Int32?)
                        ForEach(model.endpoints, id: \.id) { endpoint in
                            Text(endpoint.name).tag(Optional(endpoint.id))
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("MIDI device")
                    Picker("Offline model", selection: $model.deviceModel) {
                        ForEach(DeviceModel.allCases, id: \.self) { device in
                            Text(device.title).tag(device)
                        }
                    }
                    .font(.caption)
                    HStack {
                        Button("Refresh", action: model.refreshDevices)
                        Spacer(minLength: 4)
                        Button("Connect", action: model.connect)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.selectedEndpointID == nil)
                    }
                    Button("Explore demo", action: model.startDemo)
                        .buttonStyle(.link)
                }
            }
            .controlSize(.small)
            .padding(16)
        }
        .navigationTitle("ADI-2 Companion")
    }

    private func outputItem(_ output: Output, icon: String) -> some View {
        Button {
            model.section = "output"
            model.selectOutput(output)
        } label: {
            Label(output.title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 5)
                .background(model.section == "output" && model.selectedOutput == output ? InstrumentStyle.blue.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.section == "output" && model.selectedOutput == output ? .isSelected : [])
    }

    private func sidebarItem(_ title: String, icon: String, section: String) -> some View {
        Button { model.section = section } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 5)
                .background(model.section == section ? InstrumentStyle.blue.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.section == section ? .isSelected : [])
    }

    private var connectionBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.connected ? Color.green : model.demoMode ? Color.orange : Color.secondary)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(model.status)
                .lineLimit(2)
            Spacer(minLength: 12)
            if model.demoMode {
                Text("No MIDI is sent").foregroundStyle(.secondary)
            } else if let lastSync = model.lastSync, model.connected {
                Text(lastSync, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Last synchronized at \(lastSync.formatted(date: .omitted, time: .standard))")
            } else if !model.connected {
                Button("Setup help") { showHelp = true }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.section == "device" ? "Device settings" : model.section == "input" ? "Analog input" : model.selectedOutput.title)
                    .font(.largeTitle.weight(.semibold))
                Text(model.section == "output" ? "Edit an EQ profile for this output." : model.deviceModel.title)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.section == "output" {
                Text("5-band parametric EQ")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputControls: some View {
        HStack(spacing: 24) {
            if let volume = model.parameters.first(where: { $0.name == "Volume" }) {
                SmoothVolumeControl(
                    value: model.realValue(volume),
                    bounds: volume.minimum...volume.maximum,
                    step: volume.increment,
                    enabled: model.canWrite || model.demoMode,
                    context: "\(model.selectedOutput.rawValue):\(model.deviceModel.rawValue):\(model.selectedEndpointID ?? 0):\(model.connected):\(model.demoMode)",
                    onChange: { model.setParameter(volume, value: $0) }
                )
                .frame(maxWidth: 420)
                // A different output or connection starts at its actual value.
                .id("\(model.selectedOutput.rawValue):\(model.deviceModel.rawValue):\(model.selectedEndpointID ?? 0):\(model.connected):\(model.demoMode)")
            }
            if let mute = model.parameters.first(where: { $0.name == "Mute" }) {
                Toggle(isOn: Binding(get: { model.realValue(mute) != 0 }, set: { model.setParameter(mute, value: $0 ? 1 : 0) })) {
                    Label("Mute", systemImage: model.realValue(mute) != 0 ? "speaker.slash.fill" : "speaker.slash")
                }
                .toggleStyle(.button)
                .disabled(!model.canWrite && !model.demoMode)
            }
            Spacer(minLength: 0)
            if !model.canWrite && !model.demoMode {
                Text("Connect your device to adjust its output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 180, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Equalizer", isOn: Binding(get: { model.profile.eqEnabled }, set: model.setEQEnabled))
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                Toggle("Bass / Treble", isOn: Binding(get: { model.profile.bassTrebleEnabled }, set: model.setBassTrebleEnabled))
                Toggle("Loudness", isOn: Binding(get: { model.profile.loudnessEnabled }, set: model.setLoudnessEnabled))
            }
            .controlSize(.small)
            EQPlot(profile: model.profile, onChange: { index, band in model.updateBand(index: index, band: band) })
                .frame(height: 260)
            Text("EQ preview at 192 kHz. Bass / Treble and Loudness are not included in the curve.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Band").frame(width: 42, alignment: .leading)
                    Text("Filter").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Frequency / Hz").frame(width: 130, alignment: .leading)
                    Text("Gain / dB").frame(width: 108, alignment: .leading)
                    Text("Q").frame(width: 95, alignment: .leading)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                ForEach(Array(model.profile.bands.enumerated()), id: \.offset) { index, band in
                    Divider()
                    BandEditor(index: index, band: band) { model.updateBand(index: index, band: $0) }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : Color.clear)
                }
            }
        }
    }

    private var profileActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TextField("Profile name", text: $model.profile.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
                    .accessibilityLabel("Profile name")
                Spacer()
                if model.hasDraft {
                    Text("EQ draft").font(.caption).foregroundStyle(.secondary)
                }
                Button(model.demoMode ? "Apply demo EQ" : "Apply EQ to both channels", action: model.applyProfile)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canWrite && !model.demoMode)
                    .help("Send this EQ and its switches to both channels of the selected output")
            }
            Text("EQ edits stay in this profile until you choose Apply. Apply replaces both left and right EQ on \(model.selectedOutput.title). Output volume and hardware parameters take effect immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notice = model.channelNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.importWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Import adjustments", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                    ForEach(Array(model.importWarnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.caption).textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var channelEQControls: some View {
        DisclosureGroup("Channel EQ and tone controls", isExpanded: $showChannelEQ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Channel", selection: $model.eqSide) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    Spacer()
                    Text("Changes take effect immediately")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(model.section == "input" ? "Adjust the left and right input EQ independently. Changes apply to the selected input channel." : "Adjust left and right bands independently. Choose Left for shared EQ and Bass / Treble controls. Applying a profile above replaces both channels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(model.eqParameters, id: \.index) { definition in
                        HStack(spacing: 20) {
                            Text(definition.name)
                                .font(.body)
                                .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                            parameterControl(definition, equalizer: true)
                                .frame(width: 300, alignment: .trailing)
                                .disabled((!model.canWrite && !model.demoMode) || (!model.demoMode && model.values[ParameterKey(address: model.eqParameterAddress, index: definition.index)] == nil))
                        }
                        .padding(.vertical, 9)
                        Divider()
                    }
                }
            }
            .padding(.top, 12)
        }
        .font(.headline)
    }

    private var parameterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.canWrite {
                Text(model.demoMode ? "Demo values are simulated and stay on this Mac." : "Read and change these settings after connecting your ADI-2.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
            ForEach(model.parameters, id: \.index) { definition in
                HStack(spacing: 20) {
                    Text(definition.name)
                        .font(.body)
                        .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                    parameterControl(definition)
                        .frame(width: 300, alignment: .trailing)
                        .disabled((!model.canWrite && !model.demoMode) || (model.parameterAddress == 12 && definition.index == 16) || (!model.demoMode && model.values[ParameterKey(address: model.parameterAddress, index: definition.index)] == nil))
                }
                .padding(.vertical, 9)
                Divider()
            }
        }
    }

    @ViewBuilder
    private func parameterControl(_ definition: ParameterDefinition, equalizer: Bool = false) -> some View {
        let value = Binding<Double>(get: {
            equalizer ? model.eqRealValue(definition) : model.realValue(definition)
        }, set: { newValue in
            if equalizer { model.setEQParameter(definition, value: newValue) }
            else { model.setParameter(definition, value: newValue) }
        })
        if definition.kind == "bool" {
            Toggle(definition.name, isOn: Binding(get: { value.wrappedValue != 0 }, set: { value.wrappedValue = $0 ? 1 : 0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(definition.name)
        } else if definition.kind == "enum", !definition.labels.isEmpty {
            Picker(definition.name, selection: value) {
                ForEach(Array(definition.labels.enumerated()), id: \.offset) { index, label in
                    Text(label).tag(Double(index))
                }
            }
            .labelsHidden()
            .accessibilityLabel(definition.name)
        } else {
            HStack {
                TextField(definition.name, value: value, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .accessibilityLabel(definition.name)
                Text(definition.unit).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                Stepper(definition.name, value: value, in: definition.minimum...definition.maximum, step: definition.increment)
                    .labelsHidden()
                    .accessibilityLabel(definition.name)
            }
        }
    }

    private var connectionHelp: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Connect your ADI-2", systemImage: "cable.connector")
                .font(.title.weight(.semibold))
            VStack(alignment: .leading, spacing: 14) {
                Text("1. Connect the ADI-2 to this Mac with USB and switch it on.")
                Text("2. On the device, open Setup → Device Mode / DSD and enable MIDI Control.")
                Text("3. Choose its MIDI endpoint in the sidebar, then click Connect. Sync reads its current settings before you make changes.")
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("The app controls the DAC's DSP through CoreMIDI. It does not route audio, change your Mac's sample rate, or turn the ADI-2 on remotely.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("You can build and export EQ profiles while disconnected, or explore simulated hardware in Demo mode. Apply sends the EQ to both channels of the selected output.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Explore demo") {
                    model.startDemo()
                    showHelp = false
                }
                Spacer()
                Button("Done") { showHelp = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 530)
    }
}

/// Digit motion is decorative; the main fader owns its explicit layer animation.
private struct SmoothVolumeControl: View {
    let value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let enabled: Bool
    let context: String
    var onChange: (Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Output volume", systemImage: "speaker.wave.2")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(value, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .font(.title3.weight(.medium))
                    .contentTransition(reduceMotion ? .identity : .numericText(value: value))
                    .animation(reduceMotion || !enabled ? nil : .easeOut(duration: 0.12), value: value)
                Text("dB").foregroundStyle(.secondary)
            }
            VolumeFader(value: value, bounds: bounds, step: step, enabled: enabled, reduceMotion: reduceMotion, context: context, onChange: onChange)
                .frame(height: 28)
        }
    }
}

private struct BandEditor: View {
    let index: Int
    let band: Band
    var onChange: (Band) -> Void

    private var types: [String] {
        index == 0 ? ["Peak", "Shelf", "High Pass", "High Cut"] : index == 4 ? ["Peak", "Shelf", "High Cut"] : ["Peak"]
    }

    private func binding(_ path: WritableKeyPath<Band, Double>, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { band[keyPath: path] }, set: { value in
            guard value.isFinite else { return }
            var copy = band
            copy[keyPath: path] = min(range.upperBound, max(range.lowerBound, value))
            onChange(copy)
        })
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(InstrumentStyle.bandColors[index])
                .frame(width: 26, height: 26)
                .background(InstrumentStyle.bandColors[index].opacity(0.12), in: Circle())
                .frame(width: 42, alignment: .leading)
                .accessibilityLabel("Band \(index + 1)")
            Picker("Band \(index + 1) filter", selection: Binding(get: { band.type }, set: { value in
                var copy = band
                copy.type = value
                onChange(copy)
            })) {
                ForEach(types, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            numericEditor("Band \(index + 1) frequency in hertz", value: binding(\.frequency, range: (index >= 3 ? 200 : 20)...20000), range: (index >= 3 ? 200 : 20)...20000, step: 1, decimals: 0)
                .frame(width: 130)
            numericEditor("Band \(index + 1) gain in decibels", value: binding(\.gainDB, range: -12...12), range: -12...12, step: 0.5, decimals: 1)
                .frame(width: 108)
                .disabled(band.type == "High Pass" || band.type == "High Cut")
            numericEditor("Band \(index + 1) Q", value: binding(\.q, range: 0.5...(index >= 3 ? 5 : 9.9)), range: 0.5...(index >= 3 ? 5 : 9.9), step: 0.1, decimals: 1)
                .frame(width: 95)
        }
        .controlSize(.small)
    }

    private func numericEditor(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, decimals: Int) -> some View {
        HStack(spacing: 4) {
            TextField(label, value: value, format: .number.precision(.fractionLength(decimals)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .accessibilityLabel(label)
            Stepper(label, value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }
}

private struct EQPlot: View {
    let profile: EQProfile
    var onChange: (Int, Band) -> Void
    @ViewState<Int?> private var draggedBand = nil
    @Environment(\.colorScheme) private var colorScheme

    private let leftInset: CGFloat = 38
    private let rightInset: CGFloat = 18
    private let topInset: CGFloat = 16
    private let bottomInset: CGFloat = 26
    private let ticks: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]

    var body: some View {
        GeometryReader { geometry in
            plotCanvas(in: plotRect(for: geometry.size))
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Parametric equalizer response preview")
        .accessibilityValue(profile.eqEnabled ? "Equalizer on. Edit each band using the labeled controls below." : "Equalizer bypassed. Flat response.")
        .help("Drag a numbered point to change frequency and gain. Use the controls below for precise values.")
    }

    private func plotRect(for size: CGSize) -> CGRect {
        CGRect(x: leftInset, y: topInset,
               width: max(1, size.width - leftInset - rightInset),
               height: max(1, size.height - topInset - bottomInset))
    }

    private func plotCanvas(in rect: CGRect) -> some View {
        Canvas { context, _ in
            drawGrid(in: &context, rect: rect)
            context.clip(to: Path(rect))
            drawResponse(in: &context, rect: rect)
            if profile.eqEnabled { drawBandMarkers(in: &context, rect: rect) }
        }
        .contentShape(Rectangle())
        .gesture(plotDrag(in: rect))
    }

    private func drawGrid(in context: inout GraphicsContext, rect: CGRect) {
        let gridColor = Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.1)
        for hz in ticks {
            let x = xPosition(hz, rect: rect)
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            let label = hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))"
            let text = Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            context.draw(text, at: CGPoint(x: x, y: rect.maxY + 15))
        }
        for db in stride(from: -12, through: 12, by: 6) {
            let y = yPosition(Double(db), rect: rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            let color = Color.primary.opacity(db == 0 ? 0.3 : 0.1)
            let style = StrokeStyle(lineWidth: db == 0 ? 1 : 0.5)
            context.stroke(path, with: .color(color), style: style)
            let label = db > 0 ? "+\(db)" : "\(db)"
            let text = Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            context.draw(text, at: CGPoint(x: rect.minX - 18, y: y))
        }
    }

    private func drawResponse(in context: inout GraphicsContext, rect: CGRect) {
        var response = Path()
        for point in 0...400 {
            let proportion = Double(point) / 400.0
            let frequency = 20.0 * pow(1000.0, proportion)
            let db = profile.eqEnabled ? EQResponse.decibels(profile: profile, frequency: frequency) : 0
            let position = CGPoint(x: rect.minX + rect.width * CGFloat(proportion),
                                   y: yPosition(min(18.0, max(-18.0, db)), rect: rect))
            if point == 0 { response.move(to: position) } else { response.addLine(to: position) }
        }
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        context.stroke(response, with: .color(InstrumentStyle.blue), style: style)
    }

    private func drawBandMarkers(in context: inout GraphicsContext, rect: CGRect) {
        for (index, band) in profile.bands.enumerated() {
            let position = CGPoint(x: xPosition(band.frequency, rect: rect), y: yPosition(band.gainDB, rect: rect))
            let circle = Path(ellipseIn: CGRect(x: position.x - 10, y: position.y - 10, width: 20, height: 20))
            context.fill(circle, with: .color(InstrumentStyle.bandColors[index]))
            context.stroke(circle, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 2)
            let text = Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
            context.draw(text, at: position)
        }
    }

    private func plotDrag(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { updateBand(for: $0, rect: rect) }
            .onEnded { _ in draggedBand = nil }
    }

    private func updateBand(for drag: DragGesture.Value, rect: CGRect) {
        guard profile.eqEnabled else { return }
        if draggedBand == nil {
            let closest = profile.bands.enumerated().min { a, b in
                distance(drag.startLocation, band: a.element, rect: rect) < distance(drag.startLocation, band: b.element, rect: rect)
            }
            if let closest, distance(drag.startLocation, band: closest.element, rect: rect) < 28 {
                draggedBand = closest.offset
            }
        }
        guard let index = draggedBand, profile.bands.indices.contains(index) else { return }
        var band = profile.bands[index]
        let proportion = Double(min(1, max(0, (drag.location.x - rect.minX) / rect.width)))
        let frequency = max(index >= 3 ? 200.0 : 20.0, 20.0 * pow(1000.0, proportion))
        band.frequency = frequency > 2047 ? (frequency / 10.0).rounded() * 10.0 : frequency.rounded()
        if band.type != "High Pass" && band.type != "High Cut" {
            let normalizedGain = Double((drag.location.y - rect.minY) / rect.height)
            band.gainDB = (min(12.0, max(-12.0, 12.0 - 24.0 * normalizedGain)) * 2.0).rounded() / 2.0
        }
        onChange(index, band)
    }

    private func xPosition(_ frequency: Double, rect: CGRect) -> CGFloat {
        rect.minX + rect.width * CGFloat(log10(min(20000.0, max(20.0, frequency)) / 20.0) / 3.0)
    }

    private func yPosition(_ db: Double, rect: CGRect) -> CGFloat {
        rect.minY + rect.height * CGFloat((12.0 - db) / 24.0)
    }

    private func distance(_ point: CGPoint, band: Band, rect: CGRect) -> Double {
        Double(hypot(point.x - xPosition(band.frequency, rect: rect), point.y - yPosition(band.gainDB, rect: rect)))
    }
}
