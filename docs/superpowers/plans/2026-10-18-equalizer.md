# Bộ chỉnh âm (EQ) cho cả máy: Kế hoạch triển khai

> **Trạng thái (2026-10-18):** đã làm hết sáu việc (EQ1 đến EQ5 do các agent làm, việc 6 ghép vào app do người điều phối: `f772706`). Kế hoạch giữ nguyên như lúc viết; chỗ khác và kết quả: [ghi chú triển khai Âm thanh](../notes/2026-10-18-equalizer-implementation.html).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** EQ 10 băng có preamp, áp lên mọi âm thanh của máy theo từng thiết bị đầu ra. Hồ sơ dạng danh sách thả xuống, đổi nhanh trong tab Nhạc, chỉnh trong tab "Âm thanh".

**Architecture:**
- **Trạng thái dùng chung:** `EqualizerState` (`@Observable`, trong MyNotchCore) giữ hồ sơ, hồ sơ đang chọn và công tắc. AppDelegate tạo nó, rồi đưa cho `EqualizerModule` và `MediaModule` qua `ModuleList.make`, giống tiền lệ `ActivityCenter`.
- **Gói mới `Packages/Modules/Equalizer`**, ba target:
  - `EqualizerDSP`: biquad thuần, không cấp phát khi xử lý;
  - `EqualizerAudio`: process tap theo từng thiết bị, kèm aggregate device và IOProc;
  - `EqualizerModule`: module, các view, cài đặt.

**Tech Stack:** Swift 6.2 tools, macOS 26, SwiftUI kết hợp AppKit, Core Audio (`CATapDescription`, `AudioHardwareSystem`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-18-equalizer-design.md`

## Global Constraints

- **Băng:** 32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz. Mỗi băng ±12 dB, preamp ±12 dB.
- **Hồ sơ mặc định:** Nhạc, Phim, Họp. Thêm, đổi tên, xoá được, và xoá hết cũng được (khi đó EQ phẳng). Kéo thanh là lưu ngay vào hồ sơ đang chọn.
- **Cùng một hồ sơ** áp lên mọi thiết bị đang có tiếng. Âm thanh ra đúng thiết bị app đã gửi tới.
- **Tắt EQ** thì dỡ hết tap, không còn xử lý gì.
- MyNotch thoát hoặc crash thì tiếng gốc tự trở lại, nên dùng `muteBehavior = .mutedWhenTapped`.
- **Module không import nhau.** `ModuleSettings` chỉ đọc được khoá `module.<id>.`, nên khoá dùng chung đặt dưới `app.equalizer.*` qua `SettingsStore`.
- **Luồng âm thanh thời gian thực** không cấp phát, không khoá, không gọi Swift runtime có thể cấp phát. Tiền lệ là `SampleRing`.
- Giao diện tiếng Việt, viết hoa đầu câu. Dùng `NotchTokens` và tuân theo `NotchTab.heightRange` (120…240).
- Mỗi gói: `xcrun swift test` ×3, không cảnh báo. Không ghi vào thiết bị âm thanh thật trong test.

## Review Focus

1. **Thiết bị đổi giữa lúc phát** (AirPods kết nối, đổi thiết bị mặc định, rút tai nghe): tiếng tiếp tục trên thiết bị mới và vẫn có EQ, không im quá khoảng 1 s. Đặt test ở Task 3.
2. **Đổi tần số lấy mẫu** (44,1 sang 48 kHz): hệ số lọc tính lại theo tần số mới. Đặt test ở Task 2 và Task 3.
3. **Xoá hồ sơ đang chọn hoặc xoá hồ sơ cuối cùng; đổi tên thành chuỗi rỗng**: EQ phẳng, không crash, tên rỗng bị từ chối. Đặt test ở Task 1.
4. **Mọi băng +12 dB và preamp 0**: đầu ra không vượt ±1,0, không nổ loa. Đặt test ở Task 2.
5. **Dựng đường ống thất bại một phần** (tạo được tap, hỏng aggregate): dỡ sạch phần đã tạo và thử lại theo lịch. Đặt test ở Task 3.

---

### Task 1: `EQProfile` và `EqualizerState` trong MyNotchCore

**Files:**
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Equalizer/EQProfile.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Equalizer/EqualizerState.swift`
- Modify: `Packages/MyNotchCore/Sources/MyNotchCore/Permission/Permission.swift`. Đổi `summary` và `hint` của `.systemAudio` cho nói cả hai việc: vẽ phổ nhạc và chỉnh âm (EQ).
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/EqualizerStateTests.swift`

**Interfaces:**
- Produces:

```swift
nonisolated public struct EQProfile: Codable, Equatable, Identifiable, Sendable {
    public static let frequencies: [Double]          // 10 tần số ở trên
    public static let gainRange: ClosedRange<Double> // -12...12
    public var id: UUID
    public var name: String
    public var gains: [Double]                       // luôn đúng 10 phần tử
    public var preamp: Double
    public static func flat(named: String) -> EQProfile
    public static func defaults() -> [EQProfile]     // Nhạc, Phim, Họp
    public func clamped() -> EQProfile               // 10 băng, mọi giá trị trong gainRange
}

@Observable public final class EqualizerState {      // MainActor (mặc định của gói)
    public init(settings: SettingsStore)
    public private(set) var profiles: [EQProfile]
    public private(set) var selectedID: UUID?
    public var isEnabled: Bool                       // lưu ngay
    public var isAvailable: Bool                     // module Âm thanh đặt khi chạy; không lưu
    public var openEditor: (() -> Void)?             // module Âm thanh đặt; tab Nhạc gọi
    public var selected: EQProfile? { get }
    /// Thứ đường ống cần áp: nil khi tắt; hồ sơ đang chọn, hoặc phẳng khi không có hồ sơ nào.
    public var activeProfile: EQProfile? { get }
    public func select(_ id: UUID)
    @discardableResult public func addProfile(named: String) -> EQProfile?  // bản sao của hồ sơ đang chọn (hoặc phẳng); chọn luôn
    @discardableResult public func rename(_ id: UUID, to name: String) -> Bool
    public func delete(_ id: UUID)                   // xoá hồ sơ đang chọn thì chọn hồ sơ đầu tiên còn lại, hoặc nil
    public func setGain(_ value: Double, band: Int)  // kẹp vào gainRange; lưu ngay
    public func setPreamp(_ value: Double)
    public func resetSelectedToFlat()
}
```

**Giá trị đã chốt:**
- Khoá `app.equalizer.profiles` (`[EQProfile]?`, mặc định nil). Nil nghĩa là chưa từng tạo, khi đó gieo `defaults()`. Mảng rỗng nghĩa là người dùng đã xoá hết.
- Khoá `app.equalizer.selected` (`UUID?`) và `app.equalizer.enabled` (`Bool`, mặc định `false`).
- Tên được cắt khoảng trắng hai đầu, dài 1…40 ký tự.
- Đường cong mặc định, theo thứ tự 32 Hz … 16 kHz:

| Hồ sơ | Các băng (dB) | Preamp |
|---|---|---|
| Nhạc | `[4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4]` | -4 |
| Phim | `[5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0]` | -4 |
| Họp | `[-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0]` | -2 |

- [ ] **Step 1: Viết test hỏng.** Các test và khẳng định:
  - `seedsThreeDefaultsOnFirstRun`: tên `["Nhạc","Phim","Họp"]`, đã chọn "Nhạc", `isEnabled == false`.
  - `emptyListStaysEmptyAfterReload`: xoá hết, tạo lại `EqualizerState` cùng store, `profiles.isEmpty`, `activeProfile` là hồ sơ phẳng khi bật.
  - `deletingSelectedSelectsFirstRemaining`.
  - `renameRejectsBlankAndOverlong`: `rename(id, to: "  ")` và tên 41 ký tự đều trả `false`, tên giữ nguyên.
  - `setGainClampsAndPersists`: 15 thành 12, -20 thành -12, đọc lại sau khi tạo state mới.
  - `activeProfileIsNilWhenDisabled`.
  - `addProfileCopiesSelectedAndSelectsIt`.
  - `clampedFixesWrongBandCount`: 7 băng thì đệm số 0 thành 10, 12 băng thì cắt còn 10.
- [ ] **Step 2: Chạy và xác nhận hỏng.** `cd Packages/MyNotchCore && xcrun swift test --filter EqualizerStateTests`. Kết quả mong đợi: FAIL vì chưa có type.
- [ ] **Step 3: Viết hai file.** Dùng API khoá cấp app của `SettingsStore` như `app.tabOverflow`. Đọc và ghi bằng `SettingKey`, không dùng `UserDefaults` trực tiếp.
- [ ] **Step 4: Chạy lại.** Cùng lệnh, rồi chạy cả gói ×3. Kết quả mong đợi: PASS, không cảnh báo.
- [ ] **Step 5: Commit.** `git add <các file trên> && git commit -m "feat(core): shared equalizer profiles and switch" -- <các file trên>`

### Task 2: `EqualizerDSP`, gồm bộ lọc và chuỗi xử lý

**Files:**
- Create: `Packages/Modules/Equalizer/Package.swift`. Ba target `EqualizerDSP`, `EqualizerAudio`, `EqualizerModule`, kèm các test target. Chỉ `EqualizerModule` dùng `.defaultIsolation(MainActor.self)`. Mẫu là `Packages/Modules/Performance/Package.swift`, gói đó có target helper không mặc định MainActor. Trong task này chỉ tạo `EqualizerDSP` và `EqualizerDSPTests`; khai báo hai target kia ở task của chúng.
- Create: `Packages/Modules/Equalizer/Sources/EqualizerDSP/Biquad.swift`
- Create: `Packages/Modules/Equalizer/Sources/EqualizerDSP/EQChain.swift`
- Test: `Packages/Modules/Equalizer/Tests/EqualizerDSPTests/EQChainTests.swift`

**Interfaces:**
- Produces:

```swift
nonisolated public struct BiquadCoefficients: Equatable, Sendable {
    public var b0, b1, b2, a1, a2: Float
    public static let identity: BiquadCoefficients
    /// Bộ lọc peaking theo RBJ Audio EQ Cookbook.
    public static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> BiquadCoefficients
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double   // cho test
}
nonisolated public final class EQChain: @unchecked Sendable {
    public static let q = 1.41                       // một quãng tám; lựa chọn của kế hoạch
    public init(channels: Int)                       // cấp phát mọi thứ ở đây
    /// Gọi từ bất kỳ luồng nào; công bố bộ hệ số mới không khoá (đổi qua lại hai bộ đặt sẵn bằng chỉ số atomic).
    public func setParameters(gains: [Double], preampDB: Double, sampleRate: Double)
    /// Luồng thời gian thực. Xử lý tại chỗ, không cấp phát, không khoá. Kẹp đầu ra vào [-1, 1].
    public func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int)
}
```

**Đã chốt:**
- Băng nào 0 dB thì bỏ qua.
- Hồ sơ phẳng (mọi băng 0 và preamp 0) thì đi thẳng, đầu ra giống hệt đầu vào từng bit.
- Đổi tham số giữa chừng: chuyển dần từ bộ cũ sang bộ mới trong khoảng một buffer, để không nghe tiếng "tách". Cách chuyển do người làm chọn.
- Đầu vào NaN hoặc vô cực thì đặt lại trạng thái bộ lọc và xuất 0.

- [ ] **Step 1: Viết test hỏng.**
  - `peakingHitsGainAtCentre`: với 48 kHz, cả 10 tần số, +12 và -12 dB, `magnitudeDB` ở tâm sai không quá 0,5 dB.
  - `flatIsBitExact`: nhiễu ngẫu nhiên 2 kênh × 512 mẫu, đầu ra bằng đầu vào.
  - `preampMinus6Halves`: sin 1 kHz biên độ 0,5, đỉnh còn khoảng 0,25 (±0,01).
  - `allBandsMaxNeverExceedsUnity`: mọi băng +12, preamp 0, nhiễu biên độ 0,9, `max(abs) <= 1.0`.
  - `sampleRateChangeRecomputes`: đặt 44,1 kHz rồi 48 kHz, tâm 1 kHz vẫn khoảng +12 dB.
  - `parameterChangeHasNoJump`: sin 1 kHz biên độ 0,5, đổi từ phẳng sang +12 ở 1 kHz giữa hai buffer, bước nhảy lớn nhất giữa hai mẫu liền nhau ≤ 0,1.
  - `nonFiniteInputResets`.
  - `processDoesNotAllocate`: so `malloc_zone_statistics(nil, &stats).blocks_in_use` trước và sau 10.000 lần gọi `process`, chênh lệch 0.
- [ ] **Step 2: Chạy và xác nhận hỏng.** `cd Packages/Modules/Equalizer && xcrun swift test --filter EqualizerDSPTests`. Kết quả mong đợi: FAIL.
- [ ] **Step 3: Viết code.** Viết `peaking` theo cookbook. Trạng thái bộ lọc ở dạng Direct Form II transposed, mỗi kênh một bộ, cấp phát sẵn. Không dùng `for … in` trên luồng âm thanh, dùng con trỏ như `SampleRing`.
- [ ] **Step 4: Chạy lại.** `xcrun swift test` ×3. Kết quả mong đợi: PASS, không cảnh báo.
- [ ] **Step 5: Commit.** `feat(equalizer): a ten-band filter chain that never allocates on the audio thread`

### Task 3: `EqualizerAudio`, mỗi thiết bị đầu ra một đường ống

**Files:**
- Modify: `Packages/Modules/Equalizer/Package.swift`. Thêm `EqualizerAudio` (phụ thuộc `EqualizerDSP` và `MyNotchCore`, không mặc định MainActor) và `EqualizerAudioTests`.
- Create trong `Sources/EqualizerAudio/`:
  - `AudioSystem.swift`: protocol và bản thật trên `AudioHardwareSystem`.
  - `TapRecipe.swift`: hàm thuần dựng `CATapDescription` và dictionary aggregate.
  - `DevicePipeline.swift`: tap, aggregate, IOProc và một `EQChain`.
  - `PipelineManager.swift`
  - `AudioPropertyListener.swift`: **chép** từ `SystemAudioTap.swift` của module Nhạc (registry token và mutex). Module không import nhau nên chép, và ghi trong commit là một bản sao có chủ ý.
- Test: `Tests/EqualizerAudioTests/PipelineManagerTests.swift`, `TapRecipeTests.swift`, `FakeAudioSystem.swift`

**Interfaces:**
- Consumes: `EQChain` (Task 2) và `EQProfile` (Task 1).
- Produces:

```swift
nonisolated public enum EqualizerEngineEvent: Equatable, Sendable {
    case devices([String])            // tên các thiết bị đang được xử lý
    case permissionLikelyDenied
    case failed(String)
}
@MainActor public protocol EqualizerEngine: AnyObject {
    var onEvent: ((EqualizerEngineEvent) -> Void)? { get set }
    func start()
    func stop()
    func apply(_ profile: EQProfile)
}
nonisolated public protocol AudioSystem: Sendable {
    var ownProcessID: AudioObjectID? { get }
    /// UID của mọi thiết bị đầu ra đang có tiến trình **khác MyNotch** phát ra (theo thiết bị và isRunningOutput của từng tiến trình).
    func activeOutputDeviceUIDs() -> Set<String>
    func deviceName(uid: String) -> String?
    func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject  // token; bỏ token là ngừng nghe
}
nonisolated public protocol PipelineHandle: AnyObject, Sendable { func tearDown() }
@MainActor public final class PipelineManager: EqualizerEngine {
    public init(system: any AudioSystem = CoreAudioSystem(), scheduler: any Scheduler)
}
```

**Đã chốt:**
- **`TapRecipe.tapDescription(deviceUID:excluding:)`**:
  - `CATapDescription(excludingProcesses: [own], deviceUID: uid, stream: 0)`;
  - `isPrivate = true`;
  - `muteBehavior = .mutedWhenTapped`;
  - tên là `"MyNotch EQ <uid>"`.
- **`TapRecipe.aggregate(deviceUID:tapUID:)`**: private, không stacked. Main subdevice và danh sách subdevice đều là `uid`. Tap list gồm `kAudioSubTapUIDKey` và `kAudioSubTapDriftCompensationKey: true`, đặt `kAudioAggregateDeviceTapAutoStartKey: false`. Giống `SystemAudioTap.swift:139-153`, chỉ khác thiết bị.
- **IOProc:** chép buffer đầu vào của tap sang buffer đầu ra, rồi gọi `chain.process(output, frames:)`. Kiểm định dạng như `SystemAudioTap.swift:134-138` (linear PCM, float 32-bit, tần số lấy mẫu dương). Đổi tần số lấy mẫu thì gọi `setParameters` lại với tần số mới, hoặc dựng lại đường ống.
- **Thứ tự dỡ:** `AudioDeviceStop`, huỷ IOProc, huỷ aggregate, huỷ tap. Dỡ được cả sau khi dựng dở.
- **Thay đổi** (thiết bị, tiến trình, tần số lấy mẫu): gom lại 300 ms rồi đối chiếu tập thiết bị đang phát với tập đường ống. Thiết bị mới thì tạo đường ống, thiết bị hết tiếng thì dỡ. Tạo hỏng thì thử lại sau 1 s rồi 3 s.
- **Phát hiện chưa có quyền:** chép `SilenceDetector`. Ra tuyệt đối 0 quá 10 s trong khi vẫn có tiến trình đang phát thì phát sự kiện `.permissionLikelyDenied`.

- [ ] **Step 1: Viết test hỏng**, dùng `FakeAudioSystem` và `ManualScheduler`:
  - `oneActiveDeviceMakesOnePipeline`.
  - `secondDeviceAddsPipelineAfterDebounce`: chưa có trước 300 ms, có sau 300 ms.
  - `silentDeviceIsTornDown`.
  - `defaultDeviceSwitchMovesPipeline`: tập đổi từ {A} sang {B} thì A bị dỡ, B được tạo, trong một lần đối chiếu.
  - `stopTearsDownEverything`: mọi handle nhận `tearDown()` đúng một lần.
  - `applyReachesEveryPipelineChain`.
  - `failedMakeRetriesAt1sThen3s`.
  - `partialSetupIsTornDown`: fake ném lỗi sau khi "tạo tap", và tap đó được dỡ.
  - `tapRecipeMutesWhenTappedAndExcludesSelf`.
  - `noActiveDeviceMeansNoPipeline`.
- [ ] **Step 2: Chạy và xác nhận hỏng.** `xcrun swift test --filter EqualizerAudioTests`. Kết quả mong đợi: FAIL.
- [ ] **Step 3: Viết code.** `CoreAudioSystem` lấy thiết bị của từng tiến trình qua `AudioHardwareSystem.shared.processes`, thiết bị của tiến trình và cờ `isRunningOutput`. Chỉ bản thật chạm Core Audio; test không chạm.
- [ ] **Step 4: Chạy lại.** `xcrun swift test` ×3. Kết quả mong đợi: PASS, không cảnh báo.
- [ ] **Step 5: Commit.** `feat(equalizer): one tap and replay per output device that is playing`

### Task 4: `EqualizerModule`, gồm tab "Âm thanh" và cài đặt

**Files:**
- Modify: `Packages/Modules/Equalizer/Package.swift`. Thêm `EqualizerModule` (MainActor; phụ thuộc `EqualizerAudio`, `MyNotchCore`, `NotchUI`) và `EqualizerModuleTests` (cùng `MyNotchTestSupport`).
- Create: `Sources/EqualizerModule/EqualizerModule.swift`, `EqualizerTabView.swift`, `EQSliders.swift`, `EqualizerSettingsView.swift`, `EqMacDetector.swift`
- Test: `Tests/EqualizerModuleTests/EqualizerModuleTests.swift`, `FakeEngine.swift`

**Interfaces:**
- Consumes: `EqualizerState` (Task 1), `EqualizerEngine` và `PipelineManager` (Task 3).
- Produces: `public final class EqualizerModule: FeatureModule` với `public convenience init(state: EqualizerState)` và `init(state:engine:isEqMacRunning:)`.

**Đã chốt:**
- **Descriptor:** id `"equalizer"`, `displayName` "Âm thanh", `systemImage` `"slider.vertical.3"`, `order: 210`, `optionalPermissions: [.systemAudio]`, lý do "Để chỉnh âm thanh của cả máy".
- **Khi module chạy:**
  - `start` đặt `state.isAvailable = true` và `state.openEditor = { context.presenter.open() }`;
  - quan sát `state.activeProfile`: nil thì `engine.stop()`; có giá trị thì `engine.start()` một lần và `engine.apply(profile)` mỗi khi đổi;
  - `stop` gọi `engine.stop()`, rồi đặt `isAvailable = false` và `openEditor = nil`.
- **Tab** (`preferredHeight` ≤ 240):
  - Hàng trên: `Menu` thả xuống các hồ sơ, các nút ＋ ✎ − và công tắc "EQ". ✎ mở ô đổi tên tại chỗ. − hỏi xác nhận "Xoá hồ sơ “…”?".
  - Thanh Preamp: −12 … +12, bước 0,5 dB, hiện "+1,5 dB".
  - 10 thanh dọc, nhãn 32 · 64 · 125 · 250 · 500 · 1k · 2k · 4k · 8k · 16k, bước 0,5 dB. Kéo thì gọi `notch.setDragging(true/false)` như `VolumeRow`. Bấm đúp vào thanh thì về 0.
  - Nút "Về phẳng".
  - Dòng trạng thái: "Đang chỉnh: <tên thiết bị>", hoặc gợi ý cấp quyền kèm nút "Mở System Settings", hoặc cảnh báo eqMac.
- **Cảnh báo eqMac:** khi đang chạy app có bundle id `com.bitgapp.eqmac`, hiện "eqMac đang chạy: hai bộ EQ sẽ chồng lên nhau. Thoát eqMac để dùng EQ của MyNotch."
- **Cài đặt:** công tắc "Bật EQ" (cùng `state.isEnabled`), dòng quyền "Ghi âm thanh hệ thống" kèm link mở Privacy_AudioCapture, và chú thích về độ trễ Bluetooth.

- [ ] **Step 1: Viết test hỏng**, dùng `RegistryHarness([module])` và `FakeEngine`:
  - `enablingStartsAndApplies`.
  - `disablingStops`.
  - `selectingProfileApplies`.
  - `deletingAllAppliesFlat`.
  - `moduleStopStopsEngineAndClearsAvailability`.
  - `openEditorOpensOwnTab`: dùng `FakePresenter`.
  - `eqMacWarningShowsWhenRunning`.
  - `tabFitsHeightRange`: `harness.oversizedTabs.reports` rỗng.
- [ ] **Step 2: Chạy và xác nhận hỏng.** Kết quả mong đợi: FAIL.
- [ ] **Step 3: Viết code** theo đúng mục "Đã chốt".
- [ ] **Step 4: Chạy lại.** `xcrun swift test` ×3 trong gói Equalizer. Kết quả mong đợi: PASS, không cảnh báo.
- [ ] **Step 5: Commit.** `feat(equalizer): the Âm thanh tab, profiles and settings`

### Task 5: Dòng EQ trong tab Nhạc

**Files:**
- Modify: `Packages/Modules/Media/Sources/MediaModule/MediaModule.swift`. Thêm `public init(adapterScript:adapterFramework:equalizer: EqualizerState? = nil)` và truyền `equalizer` vào view ở chỗ dựng `MediaTabView` (`:456-464`).
- Modify: `Packages/Modules/Media/Sources/MediaModule/MediaTabView.swift`
- Create: `Packages/Modules/Media/Sources/MediaModule/EQQuickControl.swift`
- Test: `Packages/Modules/Media/Tests/MediaModuleTests/EQQuickControlTests.swift`

**Interfaces:**
- Consumes: `EqualizerState` (Task 1).

**Đã chốt:**
- `EQQuickControl` gồm chữ "EQ", một `Menu` các hồ sơ (dấu ✓ ở hồ sơ đang chọn), công tắc nhỏ, và nút "Chỉnh…" gọi `equalizer.openEditor?()`.
- Chỉ hiện khi `equalizer?.isAvailable == true`.
- Nằm ở **cuối hàng chip nguồn phát**. Khi không có chip, hàng đó vẫn hiện, chỉ có `EQQuickControl`, và bìa thu nhỏ (`compactArtworkSize`) như khi có chip.
- `preferredHeight` **giữ 160**. Các test chiều cao hiện có không đổi.

- [ ] **Step 1: Viết test hỏng.**
  - `hiddenWithoutEqualizer`.
  - `hiddenWhenUnavailable`.
  - `menuSelectionSelectsProfile`.
  - `toggleFlipsEnabled`.
  - `editCallsOpenEditor`.
  - `rowWithoutChipsUsesCompactCover`.
  - `preferredHeightUnchanged`: vẫn 160.
- [ ] **Step 2: Chạy và xác nhận hỏng.** Kết quả mong đợi: FAIL.
- [ ] **Step 3: Viết code.**
- [ ] **Step 4: Chạy lại.** `xcrun swift test` ×3 trong gói Media. Kết quả mong đợi: PASS, không cảnh báo. Mọi test cũ vẫn qua.
- [ ] **Step 5: Commit.** `feat(media): switch the EQ profile from the player`

### Task 6: Nối vào app (người điều phối làm)

**Files:** `project.yml`, `App/ModuleList.swift`, `App/AppDelegate.swift`

- [ ] **Bước 1:** Trong `project.yml`, thêm gói `EqualizerModule: path: Packages/Modules/Equalizer` và `- package: EqualizerModule` vào target MyNotch. Đổi `NSAudioCaptureUsageDescription` thành "MyNotch dùng âm thanh hệ thống để vẽ phổ nhạc và để chỉnh âm (EQ)."
- [ ] **Bước 2:** AppDelegate tạo `let equalizer = EqualizerState(settings: settings)`.
- [ ] **Bước 3:** Đổi `ModuleList.make(activities:)` thành `make(activities:equalizer:)`, thêm `EqualizerModule(state: equalizer)` và truyền `equalizer:` cho `MediaModule`.
- [ ] **Bước 4:** Chạy gate, cài lên máy, rồi kiểm tra theo spec §8 trên máy thật: loa trong, loa Bluetooth, app họp ra thiết bị riêng, ngủ rồi thức, thoát giữa chừng, CPU và RAM.
- [ ] **Bước 5:** Commit `feat(app): add the equalizer module`.

## Thứ tự

- Task 1 và Task 2 chạy song song, vì khác gói.
- Task 3 cần Task 2.
- Task 4 cần Task 1 và Task 3.
- Task 5 cần Task 1, chạy song song với Task 3 và Task 4 được.
- Task 6 làm sau cùng.
