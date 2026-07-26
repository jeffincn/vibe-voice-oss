import Foundation

/// Fixed-capacity float ring buffer for pre-roll / active speech / post-roll export.
struct AudioRingBuffer: Sendable {
    private var storage: [Float]
    private var writeIndex = 0
    private var count = 0
    let capacity: Int

    /// Samples currently held, up to `capacity`.
    var sampleCount: Int { count }

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = [Float](repeating: 0, count: self.capacity)
    }

    mutating func reset() {
        writeIndex = 0
        count = 0
    }

    mutating func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if count < capacity {
                count += 1
            }
        }
    }

    /// Chronological snapshot of the entire ring contents (oldest → newest).
    func snapshot() -> [Float] {
        guard count > 0 else { return [] }
        var result = [Float](repeating: 0, count: count)
        let start = count < capacity ? 0 : writeIndex
        for index in 0..<count {
            result[index] = storage[(start + index) % capacity]
        }
        return result
    }

    /// Export the last `sampleCount` samples (clamped to available).
    func last(_ sampleCount: Int) -> [Float] {
        let n = min(max(0, sampleCount), count)
        guard n > 0 else { return [] }
        let all = snapshot()
        return Array(all.suffix(n))
    }
}
