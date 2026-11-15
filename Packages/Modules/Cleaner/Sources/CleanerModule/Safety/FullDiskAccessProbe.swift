import Darwin
import Foundation

/// Probes whether MyNotch has been granted Full Disk Access (FDA) via TCC (NC-MYN-026).
nonisolated public enum FullDiskAccessProbe {
    public enum Status: String, Equatable, Sendable {
        case granted
        case denied
        case undetermined
    }

    /// Default probe paths inside user's home directory.
    public static func defaultProbePaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let homePath = home.path
        return [
            (homePath as NSString).appendingPathComponent("Library/Safari"),
            (homePath as NSString).appendingPathComponent("Library/Mail"),
            (homePath as NSString).appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        ]
    }

    /// Evaluates Full Disk Access permission using low-level POSIX open().
    /// Distinguishes EPERM/EACCES (denied) from ENOENT (not found).
    public static func probe(
        paths: [String]? = nil,
        opener: ((String) -> (fd: Int32, errorNumber: Int32))? = nil
    ) -> Status {
        let targetPaths = paths ?? defaultProbePaths()
        let performOpen = opener ?? { path in
            let fd = open(path, O_RDONLY)
            let err = errno
            return (fd, err)
        }

        for path in targetPaths {
            let (fd, err) = performOpen(path)
            if fd >= 0 {
                close(fd)
                return .granted
            }

            if err == EPERM || err == EACCES {
                return .denied
            } else if err == ENOENT {
                continue
            }
        }

        // Khi tất cả đường dẫn probe đều không tồn tại hoặc không thể kết luận quyền
        return .undetermined
    }
}
