import Foundation

struct MARCSubfield: Equatable, Sendable {
    var code: String
    var value: String
}

struct MARCDataField: Equatable, Sendable {
    var tag: String
    var ind1: String
    var ind2: String
    var subfields: [MARCSubfield] = []

    func first(_ code: String) -> String? {
        subfields.first { $0.code == code }?.value
    }

    func all(_ code: String) -> [String] {
        subfields.filter { $0.code == code }.map(\.value)
    }
}

/// One MARC 21 record as the SRU response carries it: control fields by tag
/// and the data fields in document order.
struct MARCRecord: Equatable, Sendable {
    var controlFields: [String: String] = [:]
    var dataFields: [MARCDataField] = []

    func fields(_ tag: String) -> [MARCDataField] {
        dataFields.filter { $0.tag == tag }
    }

    func field(_ tag: String) -> MARCDataField? {
        dataFields.first { $0.tag == tag }
    }
}

struct MARCParseResult: Sendable {
    var numberOfRecords = 0
    var hasDiagnostic = false
    var records: [MARCRecord] = []
}

/// An `XMLParser` delegate over an SRU searchRetrieve response in MARC21-xml.
/// It reads structure only and does not interpret MARC semantics. Namespaces
/// are ignored: elements match by local name.
final class MARCXMLParser: NSObject, XMLParserDelegate {
    private var result = MARCParseResult()
    private var inRecordData = false
    private var record: MARCRecord?
    private var dataField: MARCDataField?
    private var subfieldCode: String?
    private var controlTag: String?
    private var text = ""
    private var collecting = false

    /// Throws when the data is not well-formed XML.
    static func parse(_ data: Data) throws -> MARCParseResult {
        let delegate = MARCXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return delegate.result
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes: [String: String]
    ) {
        switch localName(elementName) {
        case "recordData":
            inRecordData = true
        case "record" where inRecordData:
            record = MARCRecord()
        case "controlfield" where record != nil:
            controlTag = attributes["tag"]
            text = ""
            collecting = true
        case "datafield" where record != nil:
            dataField = MARCDataField(
                tag: attributes["tag"] ?? "", ind1: attributes["ind1"] ?? " ", ind2: attributes["ind2"] ?? " "
            )
        case "subfield" where dataField != nil:
            subfieldCode = attributes["code"]
            text = ""
            collecting = true
        case "numberOfRecords":
            text = ""
            collecting = true
        case "diagnostic":
            result.hasDiagnostic = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "recordData":
            inRecordData = false
        case "record" where record != nil:
            if let finished = record { result.records.append(finished) }
            record = nil
        case "controlfield":
            if let tag = controlTag { record?.controlFields[tag] = text }
            controlTag = nil
            collecting = false
        case "datafield":
            if let finished = dataField { record?.dataFields.append(finished) }
            dataField = nil
        case "subfield":
            if let code = subfieldCode { dataField?.subfields.append(MARCSubfield(code: code, value: text)) }
            subfieldCode = nil
            collecting = false
        case "numberOfRecords":
            result.numberOfRecords = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            collecting = false
        default:
            break
        }
    }
}
