import AVFoundation
import Foundation
import GoldaData
import Testing

@testable import Golda

/// Android's `VoiceRecorder.stop`: a tap shorter than 0.8 s or silence (judged only when the level
/// was watched: at least 3 samples, the peak under 3 %) is not sent.
@Suite struct RecordingJudgeTests {
    private func judge(_ levels: [Double]) -> RecordingJudge {
        var judge = RecordingJudge()
        levels.forEach { judge.hear($0) }
        return judge
    }

    @Test func aTapShorterThanEightTenthsIsStrayHoweverLoud() {
        #expect(judge([0.5, 0.6, 0.7]).isAccidental(duration: 0.79))
        #expect(!judge([0.5, 0.6, 0.7]).isAccidental(duration: 0.8))
        #expect(RecordingJudge.longest == 60)
    }

    @Test func silenceIsJudgedFromThreeSamplesOn() {
        #expect(judge([0.01, 0.02, 0.029]).isAccidental(duration: 5))
        // Fewer looks than that: nobody watched, so it is not called silence.
        #expect(!judge([0.0, 0.0]).isAccidental(duration: 5))
        #expect(!RecordingJudge().isAccidental(duration: 5))
        // Android's `peak < 0.03f`: exactly 3 % is speech.
        #expect(!judge([0.01, 0.03, 0.0]).isAccidental(duration: 5))
    }

    @Test func thePeakIsTheLoudestMomentHeard() {
        let heard = judge([0.1, 0.4, 0.2])
        #expect(heard.samples == 3)
        #expect(heard.peak == 0.4)
    }

    @Test func decibelsBecomeTheLinearAmplitude() {
        #expect(RecordingJudge.linear(decibels: 0) == 1)
        #expect(abs(RecordingJudge.linear(decibels: -20) - 0.1) < 1e-9)
        #expect(RecordingJudge.linear(decibels: -160) < 1e-7)
        #expect(RecordingJudge.linear(decibels: 6) == 1)
        #expect(RecordingJudge.linear(decibels: -.infinity) == 0)
        #expect(RecordingJudge.linear(decibels: .nan) == 0)
        // The silence line sits near -30 dBFS.
        #expect(RecordingJudge.linear(decibels: -31) < RecordingJudge.silentPeak)
        #expect(RecordingJudge.linear(decibels: -30) > RecordingJudge.silentPeak)
    }

    @Test func theRecorderAsksForSixteenKilohertzMonoSixteenBitPCM() {
        let settings = LiveVoiceRecorder.settings
        #expect(settings[AVFormatIDKey] == Int(kAudioFormatLinearPCM))
        #expect(settings[AVSampleRateKey] == 16_000)
        #expect(settings[AVNumberOfChannelsKey] == 1)
        #expect(settings[AVLinearPCMBitDepthKey] == 16)
        #expect(settings[AVLinearPCMIsFloatKey] == 0)
        #expect(settings[AVLinearPCMIsBigEndianKey] == 0)
    }
}

/// The debug stub that lets the whole flow run without a microphone or a network.
@Suite struct VoiceStubTests {
    @Test func theArgumentPicksTheScriptAndGrantsConsentUnlessToldNot() {
        let shawarma = VoiceStubOptions(arguments: ["Golda", "-golda.inMemory", "-golda.voiceStub=shawarma"])
        #expect(shawarma?.script == .shawarma)
        #expect(shawarma?.grantsConsent == true)
        let asking = VoiceStubOptions(arguments: ["-golda.voiceStub=consider", "-golda.voiceStub.noConsent"])
        #expect(asking?.script == .consider)
        #expect(asking?.grantsConsent == false)
        #expect(VoiceStubOptions(arguments: ["-golda.voiceStub=nokey"])?.script == .noKey)
        #expect(VoiceStubOptions(arguments: ["-golda.voiceStub=unknown"]) == nil)
        #expect(VoiceStubOptions(arguments: ["-golda.inMemory"]) == nil)
    }

    @Test func theScriptsSayWhatTheirNamesPromise() async throws {
        let shawarma = VoiceStubScript.shawarma.result
        #expect(shawarma.items.count == 1)
        #expect(shawarma.items.first?.intent == "expense")
        #expect(shawarma.items.first?.amount == "15")
        #expect(shawarma.items.first?.currency == "GEL")
        #expect(shawarma.items.first?.note == "шаурма")
        #expect(VoiceStubScript.two.result.items.map(\.note) == ["шаурма", "кофе"])
        #expect(VoiceStubScript.consider.result.items.map(\.intent) == ["consider"])
        #expect(VoiceStubScript.unclear.result.items.map(\.intent) == ["unknown"])

        let file = URL(fileURLWithPath: "/dev/null")
        let answer = try await CannedVoiceProvider(script: .two, delay: .zero).parse(audio: file, system: "", model: "")
        #expect(answer == VoiceStubScript.two.result)
        await #expect(throws: VoiceProviderError.offline(message: "the stub is offline")) {
            try await CannedVoiceProvider(script: .offline, delay: .zero).parse(audio: file, system: "", model: "")
        }
        await #expect(throws: VoiceProviderError.noKey) {
            try await CannedVoiceProvider(script: .noKey, delay: .zero).parse(audio: file, system: "", model: "")
        }
    }

    @Test func theStubNoteIsARealWAVInTheRecordersFormat() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "stub-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        try StubWAV.data().write(to: file)

        let audio = try AVAudioFile(forReading: file)
        #expect(audio.fileFormat.sampleRate == 16_000)
        #expect(audio.fileFormat.channelCount == 1)
        #expect(audio.fileFormat.commonFormat == .pcmFormatInt16)
        #expect(audio.length == 4_000)
    }

    @MainActor @Test func theStubRecorderWritesTheNoteOnlyWhenStopped() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "golda-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "1.wav")
        let recorder = StubVoiceRecorder()
        #expect(recorder.permission == .granted)

        try recorder.start(into: file)
        #expect(recorder.isRecording)
        #expect((0...1).contains(recorder.level()))
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        #expect(recorder.stop() == file)
        #expect(!recorder.isRecording)
        #expect(try Data(contentsOf: file) == StubWAV.data())
        #expect(recorder.stop() == nil)
    }
}
