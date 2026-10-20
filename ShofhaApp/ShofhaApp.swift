import SwiftUI

@main
struct ShofhaApp: App {
    init() {
        // Big persistent cache: posters and pages the user already opened
        // come back instantly instead of downloading again.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 300 * 1024 * 1024,
                                   directory: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .background(Color(red: 0.043, green: 0.043, blue: 0.078))
        }
    }
}
