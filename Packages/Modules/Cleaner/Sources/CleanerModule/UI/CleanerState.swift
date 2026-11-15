import AppKit
import Foundation
import NotchUI
import Observation

/// Trạng thái hoạt động của phân hệ Gỡ ứng dụng (CleanerModule).
@Observable
@MainActor
public final class CleanerState {
    public enum Phase: Equatable {
        case idle
        case analyzing(URL)
        case preview(AppBundleInfo, [Residual], DeletionPlan, isRunning: Bool, selectedIDs: Set<String>)
        case confirming(AppBundleInfo, DeletionPlan, isRunning: Bool)
        case deleting(String)
        case success(appName: String, freedBytes: Int64)
        case error(String)

        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.analyzing(let u1), .analyzing(let u2)):
                return u1 == u2
            case (.preview(let i1, let r1, _, let run1, let s1), .preview(let i2, let r2, _, let run2, let s2)):
                return i1 == i2 && r1 == r2 && run1 == run2 && s1 == s2
            case (.confirming(let i1, _, let run1), .confirming(let i2, _, let run2)):
                return i1 == i2 && run1 == run2
            case (.deleting(let n1), .deleting(let n2)):
                return n1 == n2
            case (.success(let a1, let f1), .success(let a2, let f2)):
                return a1 == a2 && f1 == f2
            case (.error(let m1), .error(let m2)):
                return m1 == m2
            default:
                return false
            }
        }
    }

    public var phase: Phase = .idle
    public var isTargeted: Bool = false

    private(set) var currentAppInfo: AppBundleInfo?
    private(set) var currentResiduals: [Residual] = []
    public var selectedResidualIDs: Set<String> = []

    private let runningChecker: any RunningAppChecking

    public init(
        runningChecker: any RunningAppChecking = DefaultRunningAppChecker()
    ) {
        self.runningChecker = runningChecker
    }

    /// Tiếp nhận URL ứng dụng được kéo thả và bắt đầu quét
    public func analyze(appURL: URL) {
        let standardizedURL = appURL.standardized
        guard DropRouting.isApplicationURL(standardizedURL) else {
            phase = .error("Tệp được kéo vào không phải là ứng dụng macOS (.app)")
            return
        }

        phase = .analyzing(standardizedURL)

        Task {
            do {
                let info = try AppBundleAnalyzer.analyze(url: standardizedURL)
                let installedIDs = InstalledAppIndex.scan(excludingAppURL: standardizedURL)
                let residuals = ResidualScanner.scan(info: info, installedAppIDs: installedIDs)

                self.currentAppInfo = info
                self.currentResiduals = residuals

                // Chỉ chọn mặc định các mục Tier 1 (selectedByDefault == true), bỏ qua Tier 2 và các mục locked/denied
                let defaultSelected = Set(residuals.filter { $0.selectedByDefault && !$0.locked && !$0.deniedFDA }.map(\.id))
                self.selectedResidualIDs = defaultSelected

                let selectedItems = residuals.filter { defaultSelected.contains($0.id) }
                let plan = UninstallEngine.makePlan(info: info, selectedResiduals: selectedItems)

                let running = !runningChecker.runningApplications(bundleID: info.bundleID).isEmpty
                self.phase = .preview(info, residuals, plan, isRunning: running, selectedIDs: defaultSelected)
            } catch {
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    /// Đảo trạng thái chọn / bỏ chọn một residual item
    public func toggleResidual(id: String) {
        guard let info = currentAppInfo else { return }
        guard let item = currentResiduals.first(where: { $0.id == id }), !item.locked, !item.deniedFDA else { return }

        if selectedResidualIDs.contains(id) {
            selectedResidualIDs.remove(id)
        } else {
            selectedResidualIDs.insert(id)
        }

        let selected = currentResiduals.filter { selectedResidualIDs.contains($0.id) }
        let newPlan = UninstallEngine.makePlan(info: info, selectedResiduals: selected)
        let running = !runningChecker.runningApplications(bundleID: info.bundleID).isEmpty

        self.phase = .preview(info, currentResiduals, newPlan, isRunning: running, selectedIDs: selectedResidualIDs)
    }

    /// Chuyển sang bước xác nhận gỡ bỏ
    public func proceedToConfirmation() {
        guard case .preview(let info, _, let plan, let isRunning, _) = phase else { return }
        // Cấm tiến hành nếu ứng dụng đang chạy
        guard !isRunning else { return }
        phase = .confirming(info, plan, isRunning: isRunning)
    }

    /// Quay lại màn hình xem trước (bảo toàn danh sách residuals và selections)
    public func backToPreview() {
        guard let info = currentAppInfo else { return }
        let selected = currentResiduals.filter { selectedResidualIDs.contains($0.id) }
        let plan = UninstallEngine.makePlan(info: info, selectedResiduals: selected)
        let running = !runningChecker.runningApplications(bundleID: info.bundleID).isEmpty
        phase = .preview(info, currentResiduals, plan, isRunning: running, selectedIDs: selectedResidualIDs)
    }

    /// Thực thi gỡ bỏ ứng dụng
    public func executeUninstall() {
        guard case .confirming(let info, let plan, _) = phase else { return }

        // Kiểm tra lại trạng thái app đang chạy: TUYỆT ĐỐI KHÔNG tự ý kill tiến trình người dùng
        let runningNames = runningChecker.runningApplications(bundleID: info.bundleID)
        guard runningNames.isEmpty else {
            self.phase = .error("Ứng dụng \(info.displayName) vẫn đang chạy (\(runningNames.joined(separator: ", "))). Vui lòng lưu dữ liệu và đóng ứng dụng trước khi gỡ bỏ.")
            return
        }

        phase = .deleting(info.displayName)

        Task {
            do {
                let report = try UninstallEngine.execute(plan: plan, runningChecker: runningChecker)
                if report.failed.isEmpty {
                    self.phase = .success(appName: info.displayName, freedBytes: report.freedBytes)
                } else {
                    let errs = report.failed.map { "\($0.url.lastPathComponent): \($0.error)" }.joined(separator: "\n")
                    self.phase = .error("Có lỗi xảy ra khi xoá một số tệp:\n\(errs)")
                }
            } catch {
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    /// Đặt lại trạng thái về ban đầu
    public func reset() {
        phase = .idle
        isTargeted = false
        currentAppInfo = nil
        currentResiduals = []
        selectedResidualIDs = []
    }
}
