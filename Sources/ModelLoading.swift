import Foundation

enum ModelFiles {
    static let requiredDirectories = [
        "MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"
    ]

    static func existingFolder(downloadBase: URL, modelName: String) -> URL? {
        // HubApi adds the repository type (models) beneath downloadBase.
        let roots = [downloadBase.appendingPathComponent("models"), downloadBase]
        for root in roots {
            let folder = root.appendingPathComponent("argmaxinc/whisperkit-coreml")
                .appendingPathComponent(modelName)
            let complete = requiredDirectories.allSatisfy { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent(name).path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue
            }
            if complete { return folder }
        }
        return nil
    }

    static func progressAmount(_ progress: Progress) -> String {
        guard progress.totalUnitCount > 0, progress.completedUnitCount >= 0 else { return "" }
        return " (\(progress.completedUnitCount) / \(progress.totalUnitCount) files)"
    }
}

/// Keep non-cancellable Core ML work shared until it actually finishes, even if a waiter times out.
actor InFlightModelTasks<Value> {
    private var tasks: [String: Task<Value, Error>] = [:]

    func value(for key: String, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let task = tasks[key] { return try await task.value }
        let task = Task {
            defer { tasks[key] = nil }
            return try await operation()
        }
        tasks[key] = task
        return try await task.value
    }
}

/// A task group cannot enforce a deadline on an operation that ignores cancellation.
func withAsyncTimeout<Value>(
    nanoseconds: UInt64,
    timeoutError: Error,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let race = TimeoutResult<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard race.install(continuation) else { return }
            let worker = Task.detached {
                do {
                    try Task.checkCancellation()
                    race.finish(.success(try await operation()))
                } catch {
                    race.finish(.failure(error))
                }
            }
            race.track(worker)
            let timer = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                    race.finish(.failure(timeoutError))
                } catch { }
            }
            race.track(timer)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

private final class TimeoutResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func track(_ task: Task<Void, Never>) {
        lock.lock()
        if result != nil {
            lock.unlock()
            task.cancel()
        } else {
            tasks.append(task)
            lock.unlock()
        }
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks.removeAll()
        lock.unlock()
        for task in tasks { task.cancel() }
        continuation?.resume(with: result)
    }
}
