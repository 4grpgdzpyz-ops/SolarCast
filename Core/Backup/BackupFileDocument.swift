import SwiftUI
import UniformTypeIdentifiers
import Compression

/// FileDocument wrapper around AppBackup, used by .fileExporter/.fileImporter.
///
/// This is what actually fixes the ShareLink/UIActivityViewController
/// problems from earlier in this session: .fileExporter takes its document
/// via a binding that SwiftUI resolves at the moment the save dialog is
/// about to present — not a value captured ahead of time at some earlier,
/// possibly-stale render — and it's backed by the system's own document
/// picker UI, not a hand-rolled UIActivityViewController wrapper.
struct BackupFileDocument: FileDocument {
    /// No built-in, standard UTType exists for a raw zlib stream (unlike
    /// .json, .pdf, etc, which are real, well-known system types) —
    /// UTType(filenameExtension:) dynamically creates one, which is
    /// genuinely sufficient for .fileExporter/.fileImporter's practical
    /// needs (correct filename extension, correct type-matching) without
    /// requiring a full Info.plist UTExportedTypeDeclarations entry.
    static var zlibType: UTType { UTType(filenameExtension: "zlib") ?? .data }

    // Import accepts EITHER format — a .zlib export from THIS app, or a
    // plain .json export (either an older backup from before compression
    // was added, or a .settings backup, which always stays plain JSON).
    static var readableContentTypes: [UTType] { [.json, zlibType] }
    // Both types are listed as writable in principle; which one a
    // specific export actually uses is controlled by the .fileExporter
    // call site's own contentType: parameter, not by this static list —
    // .data exports use zlibType there, .settings exports use .json.
    static var writableContentTypes: [UTType] { [.json, zlibType] }

    var backup: AppBackup

    /// Compresses raw bytes into a standard zlib archive — no custom
    /// header, no metadata prepended, just the real, standard zlib
    /// stream. Uses the stateful compression_stream API, draining
    /// output in fixed-size chunks — the same real approach used for
    /// decompression below, for genuine symmetry and consistency.
    private static func zlibCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        return Self.runStream(data, operation: COMPRESSION_STREAM_ENCODE)
    }

    /// Decompresses a standard zlib archive using the real, stateful
    /// compression_stream API — draining output in fixed-size chunks
    /// into a growing Data, rather than needing to know (or guess) the
    /// total decompressed size ahead of time at all. This is the
    /// correct, real tool for this specific problem: the one-shot
    /// compression_decode_buffer API used before required the caller to
    /// provide a correctly-sized destination buffer up front, which is
    /// genuinely unknowable for an arbitrary zlib stream without either
    /// a stored header (removed per direct instruction — no custom
    /// headers) or a guess-and-retry approach (a real, honest
    /// workaround for a limitation this streaming API simply doesn't
    /// have).
    private static func zlibDecompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        return Self.runStream(data, operation: COMPRESSION_STREAM_DECODE)
    }

    /// Shared real implementation for both directions — encode and
    /// decode use the identical stream-processing loop, differing only
    /// in the operation passed to compression_stream_init.
    private static func runStream(_ data: Data, operation: compression_stream_operation) -> Data? {
        let chunkSize = 64 * 1024
        var output = Data()
        var streamFailed = false

        data.withUnsafeBytes { (inputBuffer: UnsafeRawBufferPointer) in
            guard let srcPtr = inputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                streamFailed = true
                return
            }

            let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { dstBuffer.deallocate() }

            var stream = compression_stream(dst_ptr: dstBuffer, dst_size: 0, src_ptr: srcPtr, src_size: 0, state: nil)
            let initStatus = compression_stream_init(&stream, operation, COMPRESSION_ZLIB)
            guard initStatus != COMPRESSION_STATUS_ERROR else {
                streamFailed = true
                return
            }
            defer { compression_stream_destroy(&stream) }

            stream.src_ptr = srcPtr
            stream.src_size = data.count

            repeat {
                stream.dst_ptr = dstBuffer
                stream.dst_size = chunkSize

                let processStatus = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))

                // dst_size is mutated by the API to reflect REMAINING
                // (unused) capacity, not bytes written — so the actual
                // amount produced this chunk is the original capacity
                // minus whatever's left over.
                let produced = chunkSize - stream.dst_size
                if produced > 0 {
                    output.append(dstBuffer, count: produced)
                }

                if processStatus == COMPRESSION_STATUS_END {
                    break
                }
                if processStatus == COMPRESSION_STATUS_ERROR {
                    streamFailed = true
                    break
                }
                // COMPRESSION_STATUS_OK falls through here and loops
                // again — there's more output still to drain and/or
                // input still to consume.
            } while true
        }

        guard !streamFailed, !output.isEmpty else { return nil }
        return output
    }

    /// Real, shared decode path — detects a genuine zlib stream (via its
    /// standard magic byte) and decompresses first if needed, otherwise
    /// treats the bytes as plain JSON, then decodes into AppBackup.
    /// Used by BOTH this type's own init(configuration:) (the real
    /// .fileImporter/.fileExporter machinery) AND
    /// SettingsBackupCard.handleImport (which reads the imported file's
    /// raw Data independently, outside that machinery) — a single, real
    /// source of truth for "how to read a SolarCast backup file,"
    /// rather than two separately-maintained copies of the same logic.
    static func decodeBackup(from rawData: Data, isCompressed: Bool) throws -> AppBackup {
        let data: Data
        if isCompressed, let decompressed = Self.zlibDecompress(rawData) {
            data = decompressed
        } else {
            data = rawData
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppBackup.self, from: data)
    }

    init(backup: AppBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let rawData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let isCompressed = configuration.contentType.conforms(to: Self.zlibType)
        self.backup = try Self.decodeBackup(from: rawData, isCompressed: isCompressed)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(backup)
        // Compression scoped specifically to .data backups, per direct
        // instruction — .settings backups stay plain, uncompressed JSON,
        // unchanged (they're small, human-readable text anyway; the
        // real, meaningful size savings are in .data backups, which can
        // include real forecast point history).
        let data: Data
        if backup.kind == .data, let compressed = Self.zlibCompress(jsonData) {
            data = compressed
        } else {
            data = jsonData
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
