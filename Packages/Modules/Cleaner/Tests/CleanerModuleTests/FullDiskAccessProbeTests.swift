import Darwin
import Foundation
import Testing
@testable import CleanerModule

@Suite("FullDiskAccessProbe Tests")
struct FullDiskAccessProbeTests {
    @Test("Trả về .granted khi opener thành công")
    func testGranted() {
        let fakeOpener: (String) -> (fd: Int32, errorNumber: Int32) = { _ in
            return (3, 0)
        }

        let paths = ["/Users/test/Library/Mail"]
        let status = FullDiskAccessProbe.probe(paths: paths, opener: fakeOpener)
        #expect(status == .granted)
    }

    @Test("Trả về .denied khi gặp EPERM theo NC-MYN-026")
    func testDeniedOnEPERM() {
        let fakeOpener: (String) -> (fd: Int32, errorNumber: Int32) = { _ in
            return (-1, EPERM)
        }

        let paths = ["/Users/test/Library/Mail"]
        let status = FullDiskAccessProbe.probe(paths: paths, opener: fakeOpener)
        #expect(status == .denied)
    }

    @Test("Trả về .denied khi gặp EACCES")
    func testDeniedOnEACCES() {
        let fakeOpener: (String) -> (fd: Int32, errorNumber: Int32) = { _ in
            return (-1, EACCES)
        }

        let paths = ["/Users/test/Library/Safari"]
        let status = FullDiskAccessProbe.probe(paths: paths, opener: fakeOpener)
        #expect(status == .denied)
    }

    @Test("Trả về .undetermined khi thư mục không tồn tại (ENOENT)")
    func testUndeterminedOnENOENT() {
        let fakeOpener: (String) -> (fd: Int32, errorNumber: Int32) = { _ in
            return (-1, ENOENT)
        }

        let paths = ["/Users/test/Library/NonExistent"]
        let status = FullDiskAccessProbe.probe(paths: paths, opener: fakeOpener)
        #expect(status == .undetermined)
    }
}
