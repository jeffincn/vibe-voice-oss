import Foundation

/// `multipart/form-data` body builder (RFC 7578).
///
/// The two hand-rolled versions this replaces interpolated names and filenames straight
/// into the `Content-Disposition` header. Every caller happens to pass a literal today,
/// so nothing was broken, but a name containing a quote or a newline would have produced
/// a header the server parses as something other than what was intended — and the next
/// caller to pass a user-supplied filename would have found that out in production.
struct MultipartForm {
    let boundary: String
    private var body = Data()

    /// A boundary the payload cannot contain: RFC 7578 requires the delimiter to be
    /// unique within the body, and a UUID gives that without having to scan the audio.
    static func randomBoundary(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addField(_ name: String, _ value: String) {
        guard !value.isEmpty else { return }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(Self.escaped(name))\"\r\n\r\n")
        body.appendUTF8(value)
        body.appendUTF8("\r\n")
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"\(Self.escaped(name))\";"
                + " filename=\"\(Self.escaped(filename))\"\r\n"
        )
        body.appendUTF8("Content-Type: \(Self.escaped(contentType))\r\n\r\n")
        body.append(data)
        body.appendUTF8("\r\n")
    }

    func finished() -> Data {
        var result = body
        result.appendUTF8("--\(boundary)--\r\n")
        return result
    }

    /// Percent-escape the characters RFC 7578 §5.1 says cannot appear literally inside a
    /// quoted header parameter.
    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}
