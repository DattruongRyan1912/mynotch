import Foundation

/// The mode of what is at `path`, without following a link; nil when there is nothing.
func mode(of path: String) -> mode_t? {
    var info = stat()
    return lstat(path, &info) == 0 ? info.st_mode & 0o777 : nil
}
