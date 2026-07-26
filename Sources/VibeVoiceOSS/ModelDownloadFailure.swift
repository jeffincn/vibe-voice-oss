import Foundation

/// Why a model download failed, and whether another attempt could possibly help.
///
/// The previous check searched `error.localizedDescription` for "unauthorized",
/// "forbidden" and "gated". Those words are localized, so on a system running in
/// Chinese or Japanese an auth failure looked transient and was retried three times
/// with backoff before surfacing the same error. It also retried failures that can
/// never succeed — a full disk, a repository that does not exist — and matched "401"
/// anywhere in the text, including inside a byte count.
enum ModelDownloadFailure: Equatable, Sendable {
    case cancelled
    /// Retrying cannot help.
    case permanent(Reason)
    /// A timeout, a dropped connection, a DNS hiccup. Worth another attempt.
    case transient

    enum Reason: Equatable, Sendable {
        case authenticationRequired
        case repositoryNotFound
        case outOfSpace
        case cannotWrite
        case invalidEndpoint
    }

    var isRetryable: Bool {
        if case .transient = self { return true }
        return false
    }

    /// What the user can actually do about it, appended to the underlying message.
    var advice: String? {
        guard case let .permanent(reason) = self else { return nil }
        switch reason {
        case .authenticationRequired:
            return "该仓库需要授权。请在终端执行 `hf auth login` 后重试。"
        case .repositoryNotFound:
            return "找不到该模型仓库。请检查设置中的仓库名是否拼写正确。"
        case .outOfSpace:
            return "磁盘空间不足。模型约需 1–2 GB，请清理后重试。"
        case .cannotWrite:
            return "无法写入模型目录。请检查「文稿」文件夹的权限。"
        case .invalidEndpoint:
            return "端点地址无效。请检查设置中的 HF 端点，或留空以使用默认地址。"
        }
    }

    static func classify(_ error: Error) -> ModelDownloadFailure {
        if error is CancellationError { return .cancelled }

        // Matched on domain and code rather than by casting to URLError / CocoaError:
        // an error pulled back out of NSUnderlyingErrorKey arrives as a plain NSError and
        // does not always re-bridge to the Swift wrapper.
        for candidate in chain(from: error) {
            let nsError = candidate as NSError
            switch nsError.domain {
            case NSURLErrorDomain:
                if let code = URLError.Code(rawValue: nsError.code),
                   let classified = classify(code) {
                    return classified
                }
            case NSCocoaErrorDomain:
                if let classified = classify(CocoaError.Code(rawValue: nsError.code)) {
                    return classified
                }
            case NSPOSIXErrorDomain where nsError.code == Int(ENOSPC):
                return .permanent(.outOfSpace)
            default:
                break
            }
        }

        // Hub and WhisperKit surface HTTP failures as untyped errors, so the text is all
        // there is. `String(describing:)` prints an enum case name, which — unlike
        // `localizedDescription` — is not translated.
        let haystack = chain(from: error)
            .flatMap { [String(describing: $0), $0.localizedDescription] }
            .joined(separator: " ")
            .lowercased()

        if contains(haystack, status: 401) || contains(haystack, status: 403)
            || haystack.contains("unauthorized") || haystack.contains("forbidden")
            || haystack.contains("gated") || haystack.contains("authentication") {
            return .permanent(.authenticationRequired)
        }
        if contains(haystack, status: 404) || haystack.contains("repositorynotfound")
            || haystack.contains("repository not found") {
            return .permanent(.repositoryNotFound)
        }
        if haystack.contains("no space left") || haystack.contains("out of space")
            || haystack.contains("disk full") {
            return .permanent(.outOfSpace)
        }
        return .transient
    }

    /// Nil when the code says nothing useful, so the message is examined instead — a
    /// `.badServerResponse` still carries the HTTP status in its text.
    private static func classify(_ code: URLError.Code) -> ModelDownloadFailure? {
        switch code {
        case .cancelled:
            return .cancelled
        case .userAuthenticationRequired:
            return .permanent(.authenticationRequired)
        case .fileDoesNotExist, .fileIsDirectory:
            return .permanent(.repositoryNotFound)
        case .badURL, .unsupportedURL, .appTransportSecurityRequiresSecureConnection:
            return .permanent(.invalidEndpoint)
        case .cannotWriteToFile, .cannotCreateFile, .noPermissionsToReadFile:
            return .permanent(.cannotWrite)
        default:
            return nil
        }
    }

    private static func classify(_ code: CocoaError.Code) -> ModelDownloadFailure? {
        switch code {
        case .fileWriteOutOfSpace:
            return .permanent(.outOfSpace)
        case .fileWriteNoPermission, .fileWriteVolumeReadOnly, .fileWriteInvalidFileName:
            return .permanent(.cannotWrite)
        case .userCancelled:
            return .cancelled
        default:
            return nil
        }
    }

    /// The error plus any errors nested under `NSUnderlyingErrorKey`. Hub wraps the
    /// URLError that actually explains the failure.
    private static func chain(from error: Error, depth: Int = 4) -> [Error] {
        var result: [Error] = [error]
        var current = error as NSError
        for _ in 0..<depth {
            guard let next = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            result.append(next)
            current = next
        }
        return result
    }

    /// Match an HTTP status without matching it inside a larger number, so a "1401 bytes"
    /// progress message is not read as an authorization failure.
    private static func contains(_ haystack: String, status: Int) -> Bool {
        let digits = String(status)
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: digits, range: searchRange) {
            let beforeIsDigit = found.lowerBound > haystack.startIndex
                && haystack[haystack.index(before: found.lowerBound)].isNumber
            let afterIsDigit = found.upperBound < haystack.endIndex
                && haystack[found.upperBound].isNumber
            if !beforeIsDigit && !afterIsDigit { return true }
            guard found.upperBound < haystack.endIndex else { break }
            searchRange = found.upperBound..<haystack.endIndex
        }
        return false
    }
}
