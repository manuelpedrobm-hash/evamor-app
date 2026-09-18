import SwiftUI
import UniformTypeIdentifiers
import MeditationCore

struct HistoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    private var data: Data

    init(records: [SessionRecord]) {
        let payload = HistoryExport(exportedAt: .now, app: "Ecuanimidad", sessions: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        data = (try? encoder.encode(payload)) ?? Data("{}".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    private struct HistoryExport: Codable {
        var exportedAt: Date
        var app: String
        var sessions: [SessionRecord]
    }
}
