import Foundation
import Testing
@testable import CleanerModule

@Suite("UtilityIO QoS Policy Tests")
struct UtilityIOTests {
    @Test("withUtilityPolicy chạy và trả về kết quả")
    func testWithUtilityPolicy() {
        let result = UtilityIO.withUtilityPolicy {
            40 + 2
        }
        #expect(result == 42)
    }

    @Test("withUtilityPolicy ném lỗi đúng cách khi closure ném lỗi")
    func testWithUtilityPolicyThrowing() {
        struct DummyError: Error, Equatable {}
        #expect(throws: DummyError.self) {
            try UtilityIO.withUtilityPolicy {
                throw DummyError()
            }
        }
    }

    @Test("UtilityIO.run thực thi bất đồng bộ trên luồng utility")
    func testRunAsync() async {
        let value = await UtilityIO.run {
            let sum = (1...10).reduce(0, +)
            return sum
        }
        #expect(value == 55)
    }
}
