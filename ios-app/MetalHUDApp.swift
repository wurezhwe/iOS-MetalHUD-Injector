import SwiftUI

@main
struct MetalHUDApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var languages = LanguageStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(languages)
                // No forced colour scheme: the palette in Theme.swift adapts to
                // the system appearance, so Light and Dark both work.
                .environment(\.locale, languages.language.locale)
        }
    }
}
