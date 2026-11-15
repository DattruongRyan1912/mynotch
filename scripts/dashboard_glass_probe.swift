import AppKit
import CoreGraphics
import Foundation

// MARK: - Color & Math Helpers

func sRGBToLinear(_ c: Double) -> Double {
    let v = c / 255.0
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    let lr = sRGBToLinear(r)
    let lg = sRGBToLinear(g)
    let lb = sRGBToLinear(b)
    return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
}

func wcagContrast(lum1: Double, lum2: Double) -> Double {
    let lighter = max(lum1, lum2)
    let darker = min(lum1, lum2)
    return (lighter + 0.05) / (darker + 0.05)
}

func rec709Luma(r: Double, g: Double, b: Double) -> Double {
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

func loadCGImage(from path: String) -> CGImage? {
    guard let nsImage = NSImage(contentsOfFile: path) else { return nil }
    var rect = NSRect(origin: .zero, size: nsImage.size)
    return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

// MARK: - Subcommand Handlers

func handleWindowID() {
    guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        print("ERROR: Cannot query window list")
        exit(1)
    }

    for info in infoList {
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let name = info[kCGWindowName as String] as? String ?? ""
        let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? CGFloat ?? 0
        let height = bounds["Height"] as? CGFloat ?? 0
        let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0

        if owner.contains("MyNotch") && (name.contains("Bảng điều khiển") || (width >= 1000 && height >= 650)) {
            print(windowID)
            return
        }
    }

    print("0")
}

func handleBackdrop(args: [String]) {
    var seconds = 5.0
    var colorName = "black"

    var i = 0
    while i < args.count {
        if args[i] == "--color" && i + 1 < args.count {
            colorName = args[i + 1]
            i += 2
        } else if args[i] == "--seconds" && i + 1 < args.count {
            seconds = Double(args[i + 1]) ?? 5.0
            i += 2
        } else {
            i += 1
        }
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let window = NSWindow(contentRect: screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = (colorName == "white") ? .white : .black
    window.isOpaque = true
    window.level = .floating - 1
    window.orderFrontRegardless()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))

    print("Backdrop (\(colorName)) displayed for \(seconds)s...")
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    window.orderOut(nil)
    print("Backdrop finished.")
}

func parseRect(_ str: String) -> (x: Int, y: Int, w: Int, h: Int)? {
    let parts = str.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4 else { return nil }
    return (parts[0], parts[1], parts[2], parts[3])
}

func handleSample(args: [String]) {
    var pngPath = ""
    var scale = 2.0
    var patchStr = ""
    var minLuma: Double? = nil

    var i = 0
    while i < args.count {
        if args[i] == "--png" && i + 1 < args.count {
            pngPath = args[i + 1]
            i += 2
        } else if args[i] == "--scale" && i + 1 < args.count {
            scale = Double(args[i + 1]) ?? 2.0
            i += 2
        } else if args[i] == "--patch" && i + 1 < args.count {
            patchStr = args[i + 1]
            i += 2
        } else if args[i] == "--min-luma" && i + 1 < args.count {
            minLuma = Double(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }

    guard let cgImage = loadCGImage(from: pngPath) else {
        print("ERROR: Cannot load image at \(pngPath)")
        exit(1)
    }

    guard let rect = parseRect(patchStr) else {
        print("ERROR: Invalid patch string \(patchStr), expected x,y,w,h")
        exit(1)
    }

    let px = Int(Double(rect.x) * scale)
    let py = Int(Double(rect.y) * scale)
    let pw = Int(Double(rect.w) * scale)
    let ph = Int(Double(rect.h) * scale)

    let cropRect = CGRect(x: px, y: py, width: pw, height: ph)
    guard let cropped = cgImage.cropping(to: cropRect) else {
        print("ERROR: Failed to crop image to \(cropRect)")
        exit(1)
    }

    let w = cropped.width
    let h = cropped.height
    guard let dataProvider = cropped.dataProvider, let data = dataProvider.data, let bytes = CFDataGetBytePtr(data) else {
        print("ERROR: Cannot get bitmap data")
        exit(1)
    }

    let bpp = cropped.bitsPerPixel / 8
    let bpr = cropped.bytesPerRow

    var totalR = 0.0, totalG = 0.0, totalB = 0.0, count = 0.0
    for row in 0..<h {
        let rowPtr = bytes + row * bpr
        for col in 0..<w {
            let pixelPtr = rowPtr + col * bpp
            let r = Double(pixelPtr[0])
            let g = Double(pixelPtr[1])
            let b = Double(pixelPtr[2])
            totalR += r
            totalG += g
            totalB += b
            count += 1.0
        }
    }

    let mr = totalR / count
    let mg = totalG / count
    let mb = totalB / count
    let luma = rec709Luma(r: mr, g: mg, b: mb)

    print(String(format: "Patch (%d,%d,%d,%d) | Mean RGB: (%.1f, %.1f, %.1f) | Luma: %.2f/255", rect.x, rect.y, rect.w, rect.h, mr, mg, mb, luma))

    if let minL = minLuma {
        if luma < minL {
            print(String(format: "❌ ASSERTION FAILED: Luma %.2f < min-luma %.2f", luma, minL))
            exit(1)
        } else {
            print(String(format: "✅ Luma %.2f >= min-luma %.2f", luma, minL))
        }
    }
}

func handleInk(args: [String]) {
    var pngPath = ""
    var scale = 2.0
    var regionStr = ""
    var minContrast: Double? = nil

    var i = 0
    while i < args.count {
        if args[i] == "--png" && i + 1 < args.count {
            pngPath = args[i + 1]
            i += 2
        } else if args[i] == "--scale" && i + 1 < args.count {
            scale = Double(args[i + 1]) ?? 2.0
            i += 2
        } else if args[i] == "--region" && i + 1 < args.count {
            regionStr = args[i + 1]
            i += 2
        } else if args[i] == "--min-contrast" && i + 1 < args.count {
            minContrast = Double(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }

    guard let cgImage = loadCGImage(from: pngPath) else {
        print("ERROR: Cannot load image at \(pngPath)")
        exit(1)
    }

    guard let rect = parseRect(regionStr) else {
        print("ERROR: Invalid region string \(regionStr)")
        exit(1)
    }

    let px = Int(Double(rect.x) * scale)
    let py = Int(Double(rect.y) * scale)
    let pw = Int(Double(rect.w) * scale)
    let ph = Int(Double(rect.h) * scale)

    guard let cropped = cgImage.cropping(to: CGRect(x: px, y: py, width: pw, height: ph)) else {
        print("ERROR: Failed to crop region")
        exit(1)
    }

    let w = cropped.width
    let h = cropped.height
    guard let dataProvider = cropped.dataProvider, let data = dataProvider.data, let bytes = CFDataGetBytePtr(data) else {
        print("ERROR: Cannot get bitmap data")
        exit(1)
    }

    let bpp = cropped.bitsPerPixel / 8
    let bpr = cropped.bytesPerRow

    var lums: [Double] = []
    for row in 0..<h {
        let rowPtr = bytes + row * bpr
        for col in 0..<w {
            let pixelPtr = rowPtr + col * bpp
            let r = Double(pixelPtr[0])
            let g = Double(pixelPtr[1])
            let b = Double(pixelPtr[2])
            lums.append(relativeLuminance(r: r, g: g, b: b))
        }
    }

    lums.sort()
    guard !lums.isEmpty else {
        print("ERROR: Empty region")
        exit(1)
    }

    // 1st percentile (darkest ink glyph core) vs 95th percentile (brightest background)
    let inkIndex = max(0, Int(Double(lums.count) * 0.01))
    let bgIndex = Int(Double(lums.count) * 0.95)
    let inkLum = lums[min(max(0, inkIndex), lums.count - 1)]
    let bgLum = lums[min(max(0, bgIndex), lums.count - 1)]

    let contrast = wcagContrast(lum1: bgLum, lum2: inkLum)
    print(String(format: "Region (%d,%d,%d,%d) | BG Lum: %.4f | Ink Lum: %.4f | Contrast: %.2f:1", rect.x, rect.y, rect.w, rect.h, bgLum, inkLum, contrast))

    if let minC = minContrast {
        if contrast < minC {
            print(String(format: "❌ ASSERTION FAILED: Contrast %.2f:1 < min-contrast %.2f:1", contrast, minC))
            exit(1)
        } else {
            print(String(format: "✅ Contrast %.2f:1 >= min-contrast %.2f:1", contrast, minC))
        }
    }
}

func handleDiff(args: [String]) {
    var pathA = ""
    var pathB = ""
    var regionStr: String? = nil
    var maxMad: Double? = nil
    var scale = 2.0

    var i = 0
    while i < args.count {
        if args[i] == "--a" && i + 1 < args.count {
            pathA = args[i + 1]
            i += 2
        } else if args[i] == "--b" && i + 1 < args.count {
            pathB = args[i + 1]
            i += 2
        } else if args[i] == "--region" && i + 1 < args.count {
            regionStr = args[i + 1]
            i += 2
        } else if args[i] == "--max-mad" && i + 1 < args.count {
            maxMad = Double(args[i + 1])
            i += 2
        } else if args[i] == "--scale" && i + 1 < args.count {
            scale = Double(args[i + 1]) ?? 2.0
            i += 2
        } else {
            i += 1
        }
    }

    guard let imgA = loadCGImage(from: pathA), let imgB = loadCGImage(from: pathB) else {
        print("ERROR: Cannot load images for diff")
        exit(1)
    }

    var cropA = imgA
    var cropB = imgB
    if let rStr = regionStr, let r = parseRect(rStr) {
        let rect = CGRect(x: Double(r.x) * scale, y: Double(r.y) * scale, width: Double(r.w) * scale, height: Double(r.h) * scale)
        if let ca = imgA.cropping(to: rect), let cb = imgB.cropping(to: rect) {
            cropA = ca
            cropB = cb
        }
    }

    let w = min(cropA.width, cropB.width)
    let h = min(cropA.height, cropB.height)

    guard let dataA = cropA.dataProvider?.data, let dataB = cropB.dataProvider?.data,
          let bytesA = CFDataGetBytePtr(dataA), let bytesB = CFDataGetBytePtr(dataB) else {
        print("ERROR: Cannot get bitmap bytes for diff")
        exit(1)
    }

    let bppA = cropA.bitsPerPixel / 8
    let bprA = cropA.bytesPerRow
    let bppB = cropB.bitsPerPixel / 8
    let bprB = cropB.bytesPerRow

    var totalDiff = 0.0
    var count = 0.0
    for row in 0..<h {
        let rA = bytesA + row * bprA
        let rB = bytesB + row * bprB
        for col in 0..<w {
            let pA = rA + col * bppA
            let pB = rB + col * bppB
            let diffR = abs(Double(pA[0]) - Double(pB[0]))
            let diffG = abs(Double(pA[1]) - Double(pB[1]))
            let diffB = abs(Double(pA[2]) - Double(pB[2]))
            totalDiff += (diffR + diffG + diffB) / 3.0
            count += 1.0
        }
    }

    let mad = totalDiff / count
    print(String(format: "Mean Absolute Difference (MAD): %.2f/255 across %d pixels", mad, Int(count)))

    if let maxM = maxMad {
        if mad > maxM {
            print(String(format: "❌ ASSERTION FAILED: MAD %.2f > max-mad %.2f", mad, maxM))
            exit(1)
        } else {
            print(String(format: "✅ MAD %.2f <= max-mad %.2f", mad, maxM))
        }
    }
}

func handleSwitchTab(args: [String]) {
    guard let tab = args.first else {
        print("Usage: dashboard_glass_probe.swift switch-tab <overview|battery|todo|hardware|productivity|workspace|modules>")
        exit(1)
    }
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("io.lucasvu.mynotch.switchTab"),
        object: nil,
        userInfo: ["tab": tab],
        deliverImmediately: true
    )
    print("Sent switchTab notification with tab=\(tab)")
}

func handleSwitchTheme(args: [String]) {
    guard let theme = args.first else {
        print("Usage: dashboard_glass_probe.swift switch-theme <softUI|liquidGlass|stripeLight>")
        exit(1)
    }
    UserDefaults(suiteName: "io.lucasvu.mynotch")?.set(theme, forKey: "io.lucasvu.mynotch.dashboardThemeStyle")
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("io.lucasvu.mynotch.switchTheme"),
        object: nil,
        userInfo: ["theme": theme],
        deliverImmediately: true
    )
    print("Sent switchTheme notification with theme=\(theme)")
}

// MARK: - Main Dispatch

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("Usage: dashboard_glass_probe.swift <window-id|backdrop|sample|ink|diff|switch-tab|switch-theme> [options]")
    exit(1)
}

let remainingArgs = Array(args.dropFirst())
switch command {
case "window-id":
    handleWindowID()
case "backdrop":
    handleBackdrop(args: remainingArgs)
case "sample":
    handleSample(args: remainingArgs)
case "ink":
    handleInk(args: remainingArgs)
case "diff":
    handleDiff(args: remainingArgs)
case "switch-tab":
    handleSwitchTab(args: remainingArgs)
case "switch-theme":
    handleSwitchTheme(args: remainingArgs)
default:
    print("Unknown command \(command)")
    exit(1)
}
