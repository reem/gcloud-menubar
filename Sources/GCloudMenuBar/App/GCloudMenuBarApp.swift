import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct GCloudMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: GCloudStatusStore

    init() {
        _store = StateObject(wrappedValue: GCloudStatusStore(service: GCloudService()))
    }

    var body: some Scene {
        MenuBarExtra {
            GCloudMenuView(store: store)
                .task {
                    await store.refresh()
                }
        } label: {
            Label(store.menuTitle, systemImage: store.menuSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
