import Testing

@testable import Golda

@MainActor @Suite struct StubMicModelTests {
    @Test func eachTapMovesTheMicOnAndTheFourthBringsItBack() {
        let mic = StubMicModel()
        #expect(mic.state == .idle)
        #expect(mic.level == 0)

        mic.tap()
        #expect(mic.state == .recording)
        // Something for the waveform to show while it "listens".
        #expect(mic.level == StubMicModel.recordingLevel)

        mic.tap()
        #expect(mic.state == .thinking)
        #expect(mic.level == 0)

        mic.tap()
        #expect(mic.state == .idle)
        #expect(mic.level == 0)
    }

    @Test func theShellSeesOnlyTheProtocol() {
        let mic: any MicModel = StubMicModel()
        mic.tap()
        #expect(mic.state == .recording)
    }
}
