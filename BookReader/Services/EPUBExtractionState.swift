import Foundation

actor EPUBDataAccumulator {
    private let maximumBytes: Int
    private var data = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ chunk: Data) throws {
        guard chunk.count <= maximumBytes - data.count else { throw ImportFailure.archiveUnsafe }
        data.append(chunk)
    }

    func value() -> Data { data }
}

actor EPUBExtractionState {
    private var entryBytes: Int64 = 0
    private var totalBytes: Int64 = 0

    func beginEntry() { entryBytes = 0 }

    func consume(_ chunk: Data, declaredEntryBytes: Int64, declaredTotalBytes: Int64) throws {
        let count = Int64(chunk.count)
        let (nextEntry, entryOverflow) = entryBytes.addingReportingOverflow(count)
        let (nextTotal, totalOverflow) = totalBytes.addingReportingOverflow(count)
        guard !entryOverflow, !totalOverflow,
              nextEntry <= EPUBArchivePreflight.maximumEntryBytes,
              nextTotal <= EPUBArchivePreflight.maximumUncompressedBytes,
              nextEntry <= declaredEntryBytes, nextTotal <= declaredTotalBytes else { throw ImportFailure.archiveUnsafe }
        entryBytes = nextEntry
        totalBytes = nextTotal
    }

    func entryByteCount() -> Int64 { entryBytes }
}
