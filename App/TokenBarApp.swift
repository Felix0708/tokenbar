import SwiftUI
import AppKit

@main
struct TokenBarApp: App {
    @StateObject private var model = UsageModel()

    private static let acornIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuAcorn", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = false  // 컬러 도토리 (밝은 모자 + 어두운 몸통)
        img.size = NSSize(width: 22, height: 22)
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            if let icon = Self.acornIcon {
                Image(nsImage: icon)
            } else {
                Text("🌰")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
