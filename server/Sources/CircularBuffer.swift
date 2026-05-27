// server/Sources/CircularBuffer.swift
struct CircularBuffer<T> {
    private var storage: [T?]
    private var head = 0
    private var count = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: T) {
        let index = (head + count) % capacity
        storage[index] = element
        if count < capacity {
            count += 1
        } else {
            head = (head + 1) % capacity
        }
    }

    mutating func append(contentsOf elements: some Sequence<T>) {
        for e in elements { append(e) }
    }

    var contents: [T] {
        (0..<count).compactMap { storage[(head + $0) % capacity] }
    }

    var isEmpty: Bool { count == 0 }
}
