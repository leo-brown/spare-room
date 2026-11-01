import SwiftUI

@main struct SpareRoomApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Color(red:0.14,green:0.38,blue:0.31))
                .alert("Something needs attention",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("OK") {store.error=nil} } message: { Text(store.error ?? "") }
                .onChange(of:phase) { _, value in
                    if value == .background { AppDelegate.schedule() }
                    if value == .active && store.signedIn { Task { _ = await store.pollEvents(); await store.refresh() } }
                }
                .task(id:store.signedIn) {
                    guard store.signedIn else { return }
                    await store.refresh()
                    while !Task.isCancelled {
                        _ = await store.pollEvents()
                        try? await Task.sleep(for:.seconds(45))
                        if !Task.isCancelled && phase == .active { await store.refresh() }
                    }
                }
        }
    }
}
