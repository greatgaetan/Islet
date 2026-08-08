import Foundation

/// Storage, behind a protocol.
///
/// JSON rather than SwiftData, and not for simplicity: with a store written by
/// hand, this code controls to the millisecond *when* state changes, and
/// therefore when springs fire. `@Query` refreshes when it decides, and an
/// animation starting at a moment nobody chose is exactly the defect this whole
/// project exists to avoid. The protocol keeps a later move to SwiftData cheap.
public protocol Persisting<Value>: Sendable {
    associatedtype Value: Codable & Sendable
    func load() async -> Value
    func save(_ value: Value) async
}

/// One `Codable` value, one file on disk.
public actor JSONFile<Value: Codable & Sendable>: Persisting {
    private let url: URL
    private let fallback: Value

    public init(url: URL, fallback: Value) {
        self.url = url
        self.fallback = fallback
    }

    /// `~/Library/Application Support/Islet/<name>.json`
    public static func inApplicationSupport(
        named name: String,
        fallback: Value
    ) -> JSONFile<Value> {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("Islet", isDirectory: true)
        return JSONFile(
            url: directory.appendingPathComponent("\(name).json"),
            fallback: fallback
        )
    }

    public var fileURL: URL { url }

    public func load() async -> Value {
        guard let data = try? Data(contentsOf: url) else { return fallback }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A file we cannot read is not a reason to lose the next session's work:
        // fall back, and let the next save rewrite it.
        return (try? decoder.decode(Value.self, from: data)) ?? fallback
    }

    public func save(_ value: Value) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }

        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // Atomic: a crash mid-write must not leave a half-file behind.
        try? data.write(to: url, options: .atomic)
    }

    public func encoded(_ value: Value) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(value)
    }
}

/// For tests, and for the day a store needs swapping out.
public actor InMemoryStore<Value: Codable & Sendable>: Persisting {
    private var value: Value
    public private(set) var saveCount = 0

    public init(_ value: Value) { self.value = value }

    public func load() async -> Value { value }

    public func save(_ value: Value) async {
        self.value = value
        saveCount += 1
    }
}
