import Foundation
import Testing
@testable import Murmur

@Suite(.serialized)
struct ModelLoadingTests {
    private enum TestError: Error { case deadline, loadFailed }

    @Test func findsHubCacheAndPrefersItToLegacyLayout() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = try makeModel(at: base.appendingPathComponent("argmaxinc/whisperkit-coreml/test"))
        #expect(ModelFiles.existingFolder(downloadBase: base, modelName: "test")?.path == legacy.path)
        let current = try makeModel(at: base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/test"))
        #expect(ModelFiles.existingFolder(downloadBase: base, modelName: "test")?.path == current.path)
    }

    @Test func missingOrIncompleteModelIsNotConsideredLocal() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(ModelFiles.existingFolder(downloadBase: base, modelName: "test") == nil)
        let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/test")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true
        )
        #expect(ModelFiles.existingFolder(downloadBase: base, modelName: "test") == nil)
        for name in ["MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        #expect(ModelFiles.existingFolder(downloadBase: base, modelName: "test") == nil)
    }

    @Test func progressUsesFileCounts() {
        let progress = Progress(totalUnitCount: 19)
        progress.completedUnitCount = 19
        #expect(ModelFiles.progressAmount(progress) == " (19 / 19 files)")
        #expect(ModelFiles.progressAmount(Progress(totalUnitCount: 0)) == "")
    }

    @Test func timeoutReturnsWhileOperationIgnoresCancellation() async throws {
        let load = BlockingLoad()
        defer { load.release() }
        // Independent watchdog lets a broken timeout fail without hanging the test suite.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { load.release() }
        let start = ContinuousClock.now
        do {
            _ = try await withAsyncTimeout(nanoseconds: 20_000_000, timeoutError: TestError.deadline) {
                await load.run()
            }
            Issue.record("Expected deadline")
        } catch TestError.deadline { }
        #expect(start.duration(to: .now) < .milliseconds(500))
    }

    @Test func cancellationReturnsWhileOperationIgnoresCancellation() async throws {
        let load = BlockingLoad()
        defer { load.release() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { load.release() }
        let waiter = Task {
            try await withAsyncTimeout(nanoseconds: 5_000_000_000, timeoutError: TestError.deadline) {
                await load.run()
            }
        }
        let deadline = ContinuousClock.now + .seconds(1)
        while !load.hasStarted, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(load.hasStarted)
        let start = ContinuousClock.now
        waiter.cancel()
        do {
            _ = try await waiter.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        #expect(start.duration(to: .now) < .milliseconds(500))
    }

    @Test func alreadyCancelledCallerDoesNotWaitForDeadline() async throws {
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withAsyncTimeout(nanoseconds: 5_000_000_000, timeoutError: TestError.deadline) { 42 }
        }
        do {
            _ = try await waiter.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
    }

    @Test func operationResultAndErrorArePreserved() async throws {
        let value = try await withAsyncTimeout(nanoseconds: 1_000_000_000, timeoutError: TestError.deadline) { 42 }
        #expect(value == 42)
        do {
            let _: Int = try await withAsyncTimeout(nanoseconds: 1_000_000_000, timeoutError: TestError.deadline) {
                throw TestError.loadFailed
            }
            Issue.record("Expected original error")
        } catch TestError.loadFailed { }
    }

    @Test func timedOutLoadRemainsSharedUntilItActuallyFinishes() async throws {
        let loads = InFlightModelTasks<Int>()
        let load = BlockingLoad()
        defer { load.release() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { load.release() }
        do {
            _ = try await withAsyncTimeout(nanoseconds: 20_000_000, timeoutError: TestError.deadline) {
                try await loads.value(for: "model") { await load.run() }
            }
            Issue.record("Expected deadline")
        } catch TestError.deadline { }
        let second = Task {
            try await loads.value(for: "model") {
                Issue.record("Must reuse the original load")
                return -1
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        load.release()
        #expect(try await second.value == 42)
    }

    @Test func failedLoadCanBeRetried() async throws {
        let loads = InFlightModelTasks<Int>()
        do {
            _ = try await loads.value(for: "model") { throw TestError.loadFailed }
            Issue.record("Expected failure")
        } catch TestError.loadFailed { }
        #expect(try await loads.value(for: "model") { 42 } == 42)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_TEST_AUDIO"] != nil))
    func localModelTranscribesAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["MURMUR_TEST_AUDIO"])
        let option: WhisperModelOption = environment["MURMUR_TEST_MODEL"] == "best" ? .maxAccuracy : .fast
        let transcriber = Transcriber(modelSelection: { option })
        async let preload: Void = transcriber.preloadSelectedModel()
        let transcript = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: path))
        await preload
        let activeModel = await transcriber.currentModelLabel()
        #expect(activeModel == option.label)
        #expect(!transcript.isEmpty)
        if let expected = environment["MURMUR_TEST_EXPECTED"] {
            #expect(transcript.localizedCaseInsensitiveContains(expected), "Transcript: \(transcript)")
        }
        print("Local model smoke test: \(transcript)")
        let second = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: path))
        #expect(!second.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("murmur-tests-\(UUID().uuidString)")
    }

    private func makeModel(at folder: URL) throws -> URL {
        for name in ModelFiles.requiredDirectories {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return folder
    }
}

private final class BlockingLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Never>?
    private var released = false
    private var started = false

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func run() async -> Int {
        await withCheckedContinuation { continuation in
            lock.lock()
            started = true
            if released {
                lock.unlock()
                continuation.resume(returning: 42)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        released = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: 42)
    }
}
