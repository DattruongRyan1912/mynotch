import Foundation

/// Protocol abstracting the fullscreen color picker overlay for dependency injection and testing.
@MainActor
protocol ColorPickerOverlay: AnyObject {
    func run(
        frozen: [FrozenDisplay],
        initialFormat: ColorFormat,
        onFormatChange: @escaping (ColorFormat) -> Void
    ) async -> ColorPickerResult?

    func cancel()
}
