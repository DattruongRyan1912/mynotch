import AppKit
import MyNotchCore

/// `NSApp.servicesProvider`. Each method's name is the `NSMessage` of one `NSServices` entry in project.yml;
/// it forwards the text to whichever module registered the matching service in `ServiceRegistry`.
final class ServicesProvider: NSObject {
    private let registry: ServiceRegistry

    init(registry: ServiceRegistry) {
        self.registry = registry
    }

    /// "Dịch bằng MyNotch". `pboard` is the private pasteboard the system fills for this request, never the general one.
    @objc func translateWithMyNotch(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string) else {
            error.pointee = "MyNotch không đọc được văn bản đã chọn."
            return
        }
        if !registry.handle(name: "translate", text: text) {
            error.pointee = "Mô-đun Dịch của MyNotch chưa chạy."
        }
    }
}
