import SwiftUI

/// Plain rows: the Settings page provides the Form and the section.
struct TranslationSettingsView: View {
    @Binding var preferredPair: PreferredPair
    @Binding var targetLanguage: String
    @Binding var autoTranslateOnOpen: Bool
    @Binding var useChromiumAccessibility: Bool
    @Binding var showReplaceButton: Bool
    @Binding var smartSelection: Bool
    @Binding var showSelectionChip: Bool
    @Binding var showSelectionButton: Bool
    @Binding var showSelectionActivity: Bool
    @Binding var selectionDenyList: [String]
    @Binding var convertCurrency: Bool
    @Binding var currencyTarget: String
    @Binding var firstZone: String
    @Binding var secondZone: String
    @Binding var engine: String
    @Binding var microsoftRegion: String
    @Binding var openAIBaseURL: String
    @Binding var openAIModel: String
    let engines: EngineSettingsModel
    let languages: SupportedLanguages
    let status: (LanguagePair) async -> PairStatus
    let install: (LanguagePair) -> Void
    var applications = RunningApplications.system

    @State private var available: [Locale.Language] = []
    @State private var statuses: [LanguagePair: PairStatus] = [:]

    var body: some View {
        Group {
            // A pair of one language would leave the flip rule nothing to flip to.
            languagePicker("Cặp ưa thích: ngôn ngữ 1", selection: $preferredPair.first, excluding: preferredPair.second)
            languagePicker("Cặp ưa thích: ngôn ngữ 2", selection: $preferredPair.second, excluding: preferredPair.first)
            languagePicker("Dịch sang", selection: $targetLanguage)
            TranslationEngineSettingsView(
                engine: $engine, microsoftRegion: $microsoftRegion, openAIBaseURL: $openAIBaseURL, openAIModel: $openAIModel,
                model: engines
            )
            Toggle(isOn: $autoTranslateOnOpen) {
                Text("Dịch ngay khi mở")
                Text("Chữ nhận được qua phím tắt hoặc Services được dịch luôn.")
            }
            Toggle(isOn: $useChromiumAccessibility) {
                Text("Đọc vùng chọn trong Chrome và app Electron")
                Text("Cho phím tắt và Bôi đen là hiểu. Chrome chuyển sang chế độ hỗ trợ trình đọc màn hình, và một số app đổi cách di chuyển cửa sổ; tắt mục này không hoàn lại chế độ của app đang chạy, mở lại app để trở về như cũ.")
            }
            SmartSelectionSettingsView(
                smartSelection: $smartSelection, showChip: $showSelectionChip, showButton: $showSelectionButton, showActivity: $showSelectionActivity,
                denyList: $selectionDenyList, applications: applications
            )
            Toggle(isOn: $showReplaceButton) {
                Text("Hiện nút thay vào chỗ đang chọn")
                Text("Dưới bản dịch của đoạn chữ đọc bằng phím tắt. Cần quyền Accessibility.")
            }
            Toggle(isOn: $convertCurrency) {
                Text("Quy đổi tiền tệ")
                Text("Đổi số tiền như $12 hay 100.000đ sang tiền của bạn bằng tỷ giá hằng ngày lấy từ internet (Exchange Rate API). Khi tắt, MyNotch không gửi yêu cầu mạng nào.")
            }
            Picker("Đổi sang tiền", selection: $currencyTarget) {
                ForEach(Self.currencyOptions(including: currencyTarget), id: \.code) { option in
                    Text("\(option.code) · \(option.name)").tag(option.code)
                }
            }
            .disabled(!convertCurrency)
            zonePicker("Quy đổi giờ: múi giờ 1", selection: $firstZone)
            zonePicker("Quy đổi giờ: múi giờ 2", selection: $secondZone)
            ForEach(pairs, id: \.self) { pair in
                LabeledContent("\(SupportedLanguages.name(of: pair.source)) → \(SupportedLanguages.name(of: pair.target))") {
                    statusView(for: pair)
                }
            }
        }
        .task { available = await languages.all() }
        // Translation sends no notification when a pack is installed, so the rows re-check while shown.
        .task(id: pairs) {
            while true {
                for pair in pairs { statuses[pair] = await status(pair) }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    private var pairs: [LanguagePair] { Self.statusPairs(preferred: preferredPair, target: targetLanguage) }

    /// Directions the user translates in: both ways within the preferred pair, and into the target from each of
    /// its languages when the target is outside it.
    static func statusPairs(preferred: PreferredPair, target: String) -> [LanguagePair] {
        var directions = [(preferred.first, preferred.second), (preferred.second, preferred.first)]
        if target != preferred.first, target != preferred.second {
            directions += [(preferred.first, target), (preferred.second, target)]
        }
        var seen = Set<LanguagePair>()
        return directions
            .filter { $0.0 != $0.1 }
            .map { LanguagePair(source: Locale.Language(identifier: $0.0), target: Locale.Language(identifier: $0.1)) }
            .filter { seen.insert($0).inserted }
    }

    @ViewBuilder private func statusView(for pair: LanguagePair) -> some View {
        switch statuses[pair] {
        case nil:
            Text("Đang kiểm tra…").foregroundStyle(.secondary)
        case .installed:
            Text("Đã cài").foregroundStyle(.green)
        case .supported:
            HStack {
                Text("Chưa cài").foregroundStyle(.orange)
                Button("Cài đặt…") { install(pair) }
            }
        case .unsupported:
            Text("Không hỗ trợ").foregroundStyle(.secondary)
        }
    }

    /// A time such as "3pm PST" or "9h sáng giờ Tokyo" is also shown in the Mac's zone and these two.
    private func zonePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TimeZoneCatalog.pickerOptions(including: selection.wrappedValue), id: \.id) { option in
                Text(option.title).tag(option.id)
            }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>, excluding excluded: String? = nil) -> some View {
        Picker(title, selection: selection) {
            ForEach(Self.options(available: available, including: selection.wrappedValue, excluding: excluded), id: \.self) { identifier in
                Text(SupportedLanguages.name(of: Locale.Language(identifier: identifier))).tag(identifier)
            }
        }
    }

    /// The currencies to convert into, by code. The current value stays listed even if it is not one of the usual ones.
    static func currencyOptions(including current: String) -> [(code: String, name: String)] {
        let codes = CurrencyCatalog.codes.contains(current) ? CurrencyCatalog.codes : [current] + CurrencyCatalog.codes
        return codes.map { ($0, CurrencyCatalog.name(of: $0)) }
    }

    /// Translation's languages by identifier, without `excluded`. The current value stays listed while they load.
    static func options(available: [Locale.Language], including current: String, excluding excluded: String?) -> [String] {
        let identifiers = available.map(\.minimalIdentifier).filter { $0 != excluded || $0 == current }
        return identifiers.contains(current) ? identifiers : [current] + identifiers
    }
}
