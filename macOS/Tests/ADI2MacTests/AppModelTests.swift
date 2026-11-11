import Foundation
import CoreMIDI
import ADI2Core
#if canImport(ADI2Mac)
@testable import ADI2Mac
#endif
#if canImport(XCTest)
import XCTest
#else
private var assertionCount = 0
private var failureCount = 0
class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message:String = "", file:StaticString=#filePath,line:UInt=#line) { assertionCount += 1; do { if try !value() {failureCount += 1; print("FAIL \(file):\(line) \(message)")} } catch {failureCount += 1; print("FAIL \(file):\(line) \(error)")} }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message:String = "", file:StaticString=#filePath,line:UInt=#line) { XCTAssertTrue(try !value(),message,file:file,line:line) }
func XCTAssertEqual<T:Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message:String = "", file:StaticString=#filePath,line:UInt=#line) { XCTAssertTrue(try a() == b(),message,file:file,line:line) }
func XCTAssertNotNil<T>(_ value:T?,file:StaticString=#filePath,line:UInt=#line) { XCTAssertTrue(value != nil,file:file,line:line) }
func XCTUnwrap<T>(_ value:T?,file:StaticString=#filePath,line:UInt=#line) throws -> T { guard let value else {XCTAssertTrue(false,file:file,line:line);throw ADI2Error.invalid("Missing fixture value")};return value }
#endif

@MainActor private final class FakeMIDIConnection: MIDIConnection {
    var onDevicesChanged: (() -> Void)?
    var onMessage: (([UInt8]) -> Void)?
    var sent: [[UInt8]] = []
    var attempts: [[UInt8]] = []
    var failNextSend = false
    var connectedDevice: MIDIDevice?
    let libraryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
    deinit { try? FileManager.default.removeItem(at:libraryDirectory) }
    var available = [MIDIDevice(id:1,name:"ADI-2 DAC test fixture",model:.dac,destination:1,source:1)]
    func devices() -> [MIDIDevice] { available }
    func connect(_ device:MIDIDevice) throws { connectedDevice = device }
    func send(_ bytes:[UInt8]) throws {
        attempts.append(bytes)
        if failNextSend { failNextSend = false; throw ADI2Error.invalid("Injected MIDI send failure") }
        guard connectedDevice != nil else { throw ADI2Error.invalid("Fake MIDI is disconnected") }
        sent.append(bytes)
    }
    func disconnect() { connectedDevice = nil }
    func deliver(_ containers:[[UInt8]],device:UInt8 = 0x71) {
        onMessage?(ADI2Protocol.message(device:device,command:1,payload:containers.flatMap {$0}))
    }
}

@MainActor final class AppModelTests: XCTestCase {
    private func fixture(output:Output = .phones) throws -> [[UInt8]] {
        var p=EQProfile.flat;p.output=output
        return try p.containers() + [ADI2Protocol.encode(address:output.channel,index:12,raw:-300)]
    }
    private func ready(_ fake:FakeMIDIConnection,_ model:AppModel,output:Output = .phones) throws {
        model.connect();fake.deliver(try fixture(output:output))
        XCTAssertTrue(model.canWrite)
    }
    func testInitialConnectionRequiresWholeFreshStateBeforeWrites() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        model.connect()
        XCTAssertTrue(model.syncing);XCTAssertFalse(model.connected);XCTAssertFalse(model.canWrite)
        XCTAssertEqual(fake.sent,[ADI2Protocol.requestAll(device:0x71)])
        let volume=try XCTUnwrap(model.parameters.first {$0.index == 12})
        model.setParameter(volume,value:-20);model.applyProfile()
        XCTAssertEqual(fake.sent.count,1)
        let containers=try fixture()
        fake.deliver(Array(containers.prefix(20)))
        XCTAssertFalse(model.connected);XCTAssertFalse(model.canWrite)
        fake.deliver(Array(containers.dropFirst(20)))
        XCTAssertTrue(model.connected);XCTAssertTrue(model.canWrite)
        model.setParameter(volume,value:-20)
        XCTAssertEqual(fake.sent.count,2)
        let write=try XCTUnwrap(ADI2Protocol.parse(fake.sent.last!))
        XCTAssertEqual(write.command,2)
        XCTAssertEqual(try ADI2Protocol.parseParameters(write.payload),[ParameterValue(address:6,index:12,raw:-200)])
        model.sync()
        XCTAssertFalse(model.canWrite)
        fake.deliver(Array(containers.prefix(20)))
        XCTAssertFalse(model.canWrite,"A new sync cannot reuse values from its predecessor.")
        fake.deliver(Array(containers.dropFirst(20)))
        XCTAssertTrue(model.canWrite)
    }
    func testWrongDeviceRepliesCannotCompleteConnection() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        model.connect();fake.deliver(try fixture(),device:0x72)
        XCTAssertFalse(model.canWrite);XCTAssertFalse(model.connected)
        fake.deliver(try fixture())
        XCTAssertTrue(model.canWrite)
    }
    func testChangingOutputDuringInitialSyncStartsIndependentState() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        model.connect()
        fake.deliver(Array(try fixture().prefix(10)))
        model.selectOutput(.line)
        XCTAssertEqual(fake.sent.count,2)
        XCTAssertTrue(model.syncing);XCTAssertFalse(model.canWrite)
        fake.deliver(try fixture(output:.phones))
        XCTAssertFalse(model.canWrite,"The former output cannot establish readiness for the newly selected output.")
        fake.deliver(try fixture(output:.line))
        XCTAssertTrue(model.canWrite)
        XCTAssertEqual(model.profile.output,.line)
    }
    func testConnectedOutputSwitchWaitsForPreviouslyUnseenOutput() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        try ready(fake,model)
        model.selectOutput(.line)
        XCTAssertTrue(fake.connectedDevice != nil,"An uncached output must trigger a read without dropping the MIDI connection.")
        XCTAssertTrue(model.syncing);XCTAssertFalse(model.canWrite)
        XCTAssertEqual(fake.sent.count,2)
        fake.deliver(try fixture(output:.line))
        XCTAssertTrue(model.canWrite)
        XCTAssertEqual(model.profile.output,.line)
    }
    func testOfflineImportedDraftSurvivesConnectingAndSyncing() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        let imported=try EQImporter.parse(text:"Filter 1: ON PK Fc 100 Hz Gain 3 dB Q 1",output:.phones)
        model.profile=imported.profile
        model.updateBand(index:0,band:imported.profile.bands[0])
        let draft=model.profile
        XCTAssertTrue(model.hasDraft)
        try ready(fake,model)
        XCTAssertEqual(model.profile,draft)
        XCTAssertTrue(model.hasDraft)
        XCTAssertEqual(fake.sent.count,1,"Connecting and reading must not apply an offline draft.")
    }
    func testFailedProfileWriteDisconnectsAndPreservesDraft() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        try ready(fake,model)
        model.loadExample();let draft=model.profile
        fake.failNextSend=true
        model.applyProfile()
        XCTAssertFalse(model.canWrite);XCTAssertFalse(model.connected)
        XCTAssertTrue(model.hasDraft);XCTAssertEqual(model.profile,draft)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(fake.connectedDevice == nil)
        XCTAssertEqual(fake.attempts.count,2)
    }
    func testDisconnectedAndDemoControlsSendNoMIDI() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        let volume=try XCTUnwrap(model.parameters.first {$0.index == 12})
        model.loadExample();model.setParameter(volume,value:-30);model.applyProfile();model.sync()
        XCTAssertEqual(fake.attempts.count,0)
        model.startDemo()
        model.setParameter(volume,value:-40)
        model.loadExample();model.applyProfile();model.sync()
        let gain=try XCTUnwrap(ParameterRegistry.eq.first {$0.index == 4})
        model.setEQParameter(gain,value:2)
        XCTAssertTrue(model.demoMode);XCTAssertFalse(model.canWrite)
        XCTAssertEqual(fake.attempts.count,0)
        model.stopDemo();model.applyProfile()
        XCTAssertEqual(fake.attempts.count,0)
    }
    func testSampleRateDisplayCannotSendWrite() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        model.connect()
        fake.deliver(try fixture() + [ADI2Protocol.encodeDevice(index:16,raw:1)])
        XCTAssertTrue(model.canWrite)
        model.section="device"
        let rate=try XCTUnwrap(model.parameters.first {$0.index == 16})
        let count=fake.sent.count
        model.setParameter(rate,value:2)
        XCTAssertEqual(fake.sent.count,count)
        XCTAssertEqual(model.values[ParameterAddress(address:12,index:16)],1)
    }
    func testCompleteButInvalidStateDisconnectsBeforeAllowingWrites() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        model.connect()
        fake.deliver(try fixture() + [ADI2Protocol.encode(address:8,index:6,raw:0)])
        XCTAssertFalse(model.connected);XCTAssertFalse(model.canWrite)
        XCTAssertFalse(model.syncing);XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(fake.connectedDevice == nil)
        XCTAssertEqual(fake.sent.count,1)
    }
    func testInvalidLiveStateWhileEditingRevokesWrites() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        try ready(fake,model)
        model.loadExample();let draft=model.profile
        fake.deliver([try ADI2Protocol.encode(address:8,index:6,raw:0)])
        XCTAssertFalse(model.canWrite);XCTAssertFalse(model.connected)
        XCTAssertTrue(model.hasDraft);XCTAssertEqual(model.profile,draft)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(fake.connectedDevice == nil)
    }
    func testPresetSaveStagesBandsThenCommitsAndRecallResyncs() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory),capabilities:ReleaseCapabilities(deviceMemory:true))
        defer {model.disconnect()}
        try ready(fake,model)
        model.loadExample();model.selectedPresetSlot=2;model.presetName="Studio"
        let messages=try model.profile.presetMessages(device:0x71,slot:2,name:"Studio")
        model.saveDevicePreset()
        XCTAssertEqual(Array(fake.sent.suffix(3)),messages)
        XCTAssertEqual(fake.sent.count,4)
        XCTAssertTrue(model.canWrite)
        fake.deliver([try ADI2Protocol.encode(address:13,index:2,raw:16)])
        XCTAssertTrue(model.canWrite,"Preset buffer flag echoes must not be treated as invalid live EQ switches.")
        model.loadDevicePreset()
        XCTAssertEqual(fake.sent.count,6)
        XCTAssertEqual(fake.sent[4],try ADI2Protocol.loadEQPreset(device:0x71,output:.phones,slot:2))
        XCTAssertEqual(fake.sent[5],ADI2Protocol.requestAll(device:0x71))
        XCTAssertTrue(model.syncing);XCTAssertFalse(model.canWrite)
        fake.deliver(try fixture())
        XCTAssertTrue(model.canWrite);XCTAssertFalse(model.hasDraft)
    }
    func testInvalidMemorySlotsAndNamesNeverSendMIDI() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory),capabilities:ReleaseCapabilities(deviceMemory:true))
        defer {model.disconnect()}
        try ready(fake,model)
        model.selectedPresetSlot=0;model.saveDevicePreset();model.loadDevicePreset()
        model.selectedSetupSlot=0;model.saveDeviceSetup();model.loadDeviceSetup()
        model.selectedPresetSlot=1;model.presetName="Not ASCII é";model.saveDevicePreset()
        XCTAssertEqual(fake.attempts.count,1)
        XCTAssertTrue(model.canWrite)
        XCTAssertNotNil(model.errorMessage)
    }
    func testDemoMemoryRoundTripsWithoutPhysicalMIDI() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory),capabilities:ReleaseCapabilities(deviceMemory:true))
        defer {model.disconnect()}
        model.startDemo();model.selectedPresetSlot=3;model.presetName="Demo reference"
        let reference=model.profile.bands
        model.saveDevicePreset();model.loadFlat();model.loadDevicePreset()
        XCTAssertEqual(model.profile.bands,reference)
        model.selectedSetupSlot=2;model.saveDeviceSetup()
        let volume=try XCTUnwrap(model.parameters.first {$0.index == 12})
        model.setParameter(volume,value:-40)
        model.loadDeviceSetup()
        XCTAssertEqual(model.realValue(volume),volume.defaultValue)
        XCTAssertEqual(fake.attempts.count,0)
        XCTAssertTrue(model.demoMode);XCTAssertFalse(model.canWrite)
    }
    func testSetupCommandsRequireFreshReadAndFailureRevokesReadiness() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory),capabilities:ReleaseCapabilities(deviceMemory:true))
        defer {model.disconnect()}
        try ready(fake,model)
        model.selectedSetupSlot=4;model.saveDeviceSetup()
        XCTAssertEqual(fake.sent.last,try ADI2Protocol.setup(device:0x71,slot:4,save:true))
        model.loadDeviceSetup()
        XCTAssertEqual(fake.sent[2],try ADI2Protocol.setup(device:0x71,slot:4,save:false))
        XCTAssertTrue(model.syncing);XCTAssertFalse(model.canWrite)
        fake.deliver(try fixture())
        XCTAssertTrue(model.canWrite)
        fake.failNextSend=true;model.saveDevicePreset()
        XCTAssertFalse(model.canWrite);XCTAssertFalse(model.connected)
        XCTAssertTrue(fake.connectedDevice == nil)
        XCTAssertNotNil(model.errorMessage)
    }
    func testLocalProfileLoadStaysDraftUntilExplicitApply() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        model.loadExample();model.profile.name="Local reference";model.saveLocalProfile()
        XCTAssertEqual(model.localProfiles.count,1)
        model.selectOutput(.line)
        let saved=try XCTUnwrap(model.localProfiles.first)
        model.loadLocalProfile(saved)
        XCTAssertEqual(model.profile.output,.line)
        XCTAssertEqual(model.profile.bands,EQProfile.example.bands)
        XCTAssertTrue(model.hasDraft)
        XCTAssertEqual(fake.attempts.count,0)
    }
    func testRightEQSurfaceAndWriteGuardExcludeSharedControls() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory),capabilities:ReleaseCapabilities(deviceMemory:true))
        defer {model.disconnect()}
        try ready(fake,model)
        XCTAssertTrue(model.channelNotice == nil,"Equal bands do not differ because optional right shared fields are absent.")
        // Some firmware reports right enable; tolerate that inbound report, but
        // never treat it or any reported extra shared field as a writable control.
        fake.deliver([try ADI2Protocol.encode(address:8,index:2,raw:0),try ADI2Protocol.encode(address:8,index:20,raw:1),try ADI2Protocol.encode(address:8,index:28,raw:3)])
        XCTAssertTrue(model.canWrite)
        XCTAssertTrue(model.channelNotice == nil,"A different optional right enable report cannot create a band asymmetry warning.")
        model.eqSide="right"
        XCTAssertEqual(model.eqParameters.map(\.index).sorted(),Array(3...19))
        let before=fake.attempts.count
        for index in [2,20,28] {
            let shared=try XCTUnwrap(ParameterRegistry.eq.first {$0.index == index})
            model.setEQParameter(shared,value:shared.defaultValue)
        }
        XCTAssertEqual(fake.attempts.count,before,"Direct method calls cannot bypass the right-side control filter, even for observed fields.")
        XCTAssertTrue(model.canWrite)
        let gain=try XCTUnwrap(ParameterRegistry.eq.first {$0.index == 4})
        model.setEQParameter(gain,value:1)
        XCTAssertEqual(fake.attempts.count,before+1,"Documented right-band edits remain available.")
        let message=try XCTUnwrap(ADI2Protocol.parse(fake.sent.last!))
        XCTAssertEqual(try ADI2Protocol.parseParameters(message.payload),[ParameterValue(address:8,index:4,raw:2)])
        model.eqSide="left"
        for index in [2,20,28] { XCTAssertTrue(model.eqParameters.contains {$0.index == index}) }
    }
    func testStoreReleaseBlocksDeviceMemoryAndKeepsLiveControlAndLocalProfiles() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        defer {model.disconnect()}
        XCTAssertFalse(model.deviceMemoryAvailable)
        try ready(fake,model)
        var observed = [try ADI2Protocol.encode(address:7,index:27,raw:0),try ADI2Protocol.encode(address:7,index:28,raw:0)]
        for index in [25,26,27,28,29,62] { observed.append(try ADI2Protocol.encodeDevice(index:index,raw:0)) }
        fake.deliver(observed)
        let before=fake.attempts.count
        model.selectedPresetSlot=1;model.presetName="A valid name";model.selectedSetupSlot=1
        model.saveDevicePreset();model.loadDevicePreset();model.saveDeviceSetup();model.loadDeviceSetup()
        XCTAssertEqual(fake.attempts.count,before,"The Store capability blocks otherwise valid device-memory calls before any MIDI.")
        XCTAssertTrue(model.canWrite,"Rejecting memory operations does not revoke ordinary live controls.")
        XCTAssertTrue([2,4,20,21,26].allSatisfy { index in model.eqParameters.contains {$0.index == index} })
        XCTAssertFalse(model.eqParameters.contains {[27,28].contains($0.index)})
        for index in [27,28] {
            let parameter=try XCTUnwrap(ParameterRegistry.eq.first {$0.index == index})
            model.setEQParameter(parameter,value:1)
        }
        model.section="device"
        XCTAssertFalse(model.parameters.contains { [25,26,27,28,29,62].contains($0.index) })
        for index in [25,26,27,28,29,62] {
            let parameter=try XCTUnwrap(ParameterRegistry.device(for:.dac).first {$0.index == index})
            model.setParameter(parameter,value:1)
        }
        XCTAssertEqual(fake.attempts.count,before,"Generic parameter methods cannot restore the hidden memory or recall-key controls.")
        model.section="output"
        let volume=try XCTUnwrap(model.parameters.first {$0.index == 12})
        model.setParameter(volume,value:-35)
        XCTAssertEqual(fake.sent.count,before+1,"Live volume control remains available.")
        model.loadExample();model.applyProfile()
        XCTAssertEqual(fake.sent.count,before+3,"Live EQ Apply and its fresh read remain available.")
        XCTAssertEqual(ADI2Protocol.parse(fake.sent[fake.sent.count-2])?.command,2)
        XCTAssertEqual(ADI2Protocol.parse(fake.sent.last!)?.command,3)
        model.startDemo();model.loadExample()
        let draft=model.profile,values=model.values,attempts=fake.attempts.count
        model.saveDevicePreset();model.loadDevicePreset();model.saveDeviceSetup();model.loadDeviceSetup()
        XCTAssertEqual(model.profile,draft)
        XCTAssertEqual(model.values,values)
        XCTAssertTrue(model.hasDraft)
        XCTAssertEqual(fake.attempts.count,attempts)
        model.profile.name="Local Store profile";model.saveLocalProfile()
        let saved=try XCTUnwrap(model.localProfiles.first)
        model.loadFlat();model.loadLocalProfile(saved)
        XCTAssertEqual(model.profile.bands,draft.bands)
        XCTAssertTrue(model.hasDraft,"Loading a local profile remains an offline draft.")
        XCTAssertEqual(fake.attempts.count,attempts)
    }
    func testDeviceRemovalRevokesWriteReadiness() async throws {
        let fake=FakeMIDIConnection(),model=AppModel(midi:fake,library:FileProfileLibrary(directory:fake.libraryDirectory))
        try ready(fake,model)
        fake.available=[];fake.onDevicesChanged?()
        XCTAssertFalse(model.connected);XCTAssertFalse(model.canWrite)
        XCTAssertTrue(fake.connectedDevice == nil)
        model.applyProfile()
        XCTAssertEqual(fake.sent.count,1)
    }
}

#if !canImport(XCTest)
@main struct AppModelTestRunner {
    @MainActor static func main() async throws {
        let tests=AppModelTests()
        try await tests.testInitialConnectionRequiresWholeFreshStateBeforeWrites()
        try await tests.testWrongDeviceRepliesCannotCompleteConnection()
        try await tests.testChangingOutputDuringInitialSyncStartsIndependentState()
        try await tests.testConnectedOutputSwitchWaitsForPreviouslyUnseenOutput()
        try await tests.testOfflineImportedDraftSurvivesConnectingAndSyncing()
        try await tests.testFailedProfileWriteDisconnectsAndPreservesDraft()
        try await tests.testDisconnectedAndDemoControlsSendNoMIDI()
        try await tests.testSampleRateDisplayCannotSendWrite()
        try await tests.testCompleteButInvalidStateDisconnectsBeforeAllowingWrites()
        try await tests.testInvalidLiveStateWhileEditingRevokesWrites()
        try await tests.testPresetSaveStagesBandsThenCommitsAndRecallResyncs()
        try await tests.testInvalidMemorySlotsAndNamesNeverSendMIDI()
        try await tests.testDemoMemoryRoundTripsWithoutPhysicalMIDI()
        try await tests.testSetupCommandsRequireFreshReadAndFailureRevokesReadiness()
        try await tests.testLocalProfileLoadStaysDraftUntilExplicitApply()
        try await tests.testRightEQSurfaceAndWriteGuardExcludeSharedControls()
        try await tests.testStoreReleaseBlocksDeviceMemoryAndKeepsLiveControlAndLocalProfiles()
        try await tests.testDeviceRemovalRevokesWriteReadiness()
        print("AppModel: 18 cases, \(assertionCount) assertions, \(failureCount) failures")
        if failureCount > 0 {exit(1)}
    }
}
#endif
