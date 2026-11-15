import Foundation

/// Why an engine that needs the user's key could not translate. Its messages and log lines never hold a key, a
/// header or the text; of what a service said it keeps only a short reason, with the key taken out.
nonisolated enum RemoteFailure: Error, Equatable, Sendable {
    /// Something to type in first: the key, the address, the model.
    case notConfigured(String)
    case badAddress
    case rejected(status: Int, detail: String?)
    case quota
    case server(status: Int, detail: String?)
    /// The server answered with a redirect, which is never followed: it would take the key and the text elsewhere.
    case redirected(status: Int)
    /// More text than a request may carry; nothing was sent.
    case tooLong(limit: Int)
    /// A success whose body is not the shape the service documents.
    case unreadable
    case offline
    case timedOut
    case unreachable

    private static let maxDetailLength = 160

    init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: self = .offline
        case .timedOut: self = .timedOut
        default: self = .unreachable
        }
    }

    /// What a reply with a failing status says: 429 is quota, 401 is a refused key, and for the rest the service's own
    /// reason, if it gives one in the usual `{"error": {"message": ...}}`. A 401 gets no reason, since some services
    /// quote a masked copy of the key in it.
    static func of(_ reply: HTTPReply, key: String) -> RemoteFailure {
        switch reply.status {
        case 429: .quota
        case 401: .rejected(status: 401, detail: nil)
        case 300..<400: .redirected(status: reply.status)
        case 400..<500: .rejected(status: reply.status, detail: detail(in: reply.body, hiding: key))
        default: .server(status: reply.status, detail: detail(in: reply.body, hiding: key))
        }
    }

    /// The tab's one-line explanation, in Vietnamese, ending in what the user can do about it.
    func message(for engine: String) -> String {
        switch self {
        case .notConfigured(let what): "Chưa nhập \(what) cho \(engine). Mở Cài đặt → Dịch để thêm."
        case .badAddress: "Địa chỉ của \(engine) chưa đúng: cần https:// (http:// chỉ dùng cho localhost)."
        case .rejected(let status, let detail):
            Self.sentence("\(engine) từ chối yêu cầu (HTTP \(status))", detail) + (status == 401 || status == 403 ? " Kiểm tra lại key." : "")
        case .quota: "\(engine) báo hết hạn mức hoặc nhận quá nhiều yêu cầu (HTTP 429). Thử lại sau."
        case .server(let status, let detail): Self.sentence("\(engine) đang lỗi (HTTP \(status))", detail)
        case .redirected: "Máy chủ của \(engine) chuyển hướng — đã chặn để bảo vệ khoá."
        case .tooLong(let limit):
            "Đoạn chữ dài hơn \(limit.formatted(.number.locale(Locale(identifier: "vi_VN")))) ký tự nên chưa gửi tới \(engine). Chọn đoạn ngắn hơn, hoặc dịch bằng Apple."
        case .unreadable: "Không đọc được trả lời của \(engine)."
        case .offline: "Không có kết nối mạng."
        case .timedOut: "\(engine) trả lời quá lâu."
        case .unreachable: "Không kết nối được tới \(engine)."
        }
    }

    /// For the log: the kind and the status, never a service's words.
    var logDescription: String {
        switch self {
        case .notConfigured: "not configured"
        case .badAddress: "bad address"
        case .rejected(let status, _): "rejected (HTTP \(status))"
        case .quota: "quota (HTTP 429)"
        case .server(let status, _): "server error (HTTP \(status))"
        case .redirected(let status): "redirect refused (HTTP \(status))"
        case .tooLong: "text too long"
        case .unreadable: "unreadable reply"
        case .offline: "offline"
        case .timedOut: "timed out"
        case .unreachable: "unreachable"
        }
    }

    private static func sentence(_ head: String, _ detail: String?) -> String {
        guard let detail else { return head + "." }
        return "\(head): \(detail.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))."
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            var message: String?
        }

        var error: Detail?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Some servers answer `{"error": "text"}` instead of `{"error": {"message": "text"}}`.
            if let text = try? container.decode(String.self, forKey: .error) {
                error = Detail(message: text)
            } else {
                error = try? container.decode(Detail.self, forKey: .error)
            }
        }

        enum CodingKeys: String, CodingKey { case error }
    }

    private static func detail(in body: Data, hiding key: String) -> String? {
        guard var text = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error?.message else { return nil }
        if !key.isEmpty { text = text.replacingOccurrences(of: key, with: "***") }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return text.count > maxDetailLength ? String(text.prefix(maxDetailLength)) + "…" : text
    }
}
