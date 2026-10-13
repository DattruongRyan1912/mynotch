/// Downloads a language pack; faked in tests because it shows a window.
protocol LanguageInstalling: AnyObject {
    /// Shows the installer for `pair`. `onStatusChange` runs whenever the pack may have been installed.
    func install(_ pair: LanguagePair, onStatusChange: @escaping @MainActor () -> Void)
}
