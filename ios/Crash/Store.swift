import SwiftUI
import Security
import UserNotifications
import BackgroundTasks

struct APIProblem: LocalizedError { let message: String; var errorDescription: String? { message } }
enum Keychain {
    static let service = "uk.co.leobrown.crash"
    static func read(_ key: String) -> String? {
        let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key,kSecReturnData as String:true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    @discardableResult static func save(_ key: String, _ value: String?) -> OSStatus {
        let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key]
        SecItemDelete(q as CFDictionary)
        if let value {
            var a = q; a[kSecValueData as String] = Data(value.utf8)
            a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(a as CFDictionary,nil)
        }
        return errSecSuccess
    }
}

@MainActor final class Store: ObservableObject {
    static let shared = Store()
    static let endpoint: URL = {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["ROOMS_API_BASE"], let url = URL(string:value), url.host == "localhost" { return url }
        #endif
        return URL(string:"https://rooms.leobrown.co.uk/api/")!
    }()
    @Published var snapshot: Snapshot?
    @Published var signedIn = Keychain.read("token") != nil
    @Published var error: String?
    @Published var working = false
    @Published var needsRecoverySave = false
    @Published var recoveryKey: String? = Keychain.read("recovery")
    @Published var selectedNetwork = ""
    @Published var events: [RoomEvent] = []
    @Published var notifications = UserDefaults.standard.bool(forKey:"notifications")
    private var sessionToken = Keychain.read("token")
    private var polling = false
    var userId: String { snapshot?.user.id ?? Keychain.read("user") ?? "" }
    var network: Network? { snapshot?.networks.first { $0.id == selectedNetwork } }
    var cursorKey: String { "events.\(userId)" }
    let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()

    func call(_ path: String, method: String = "GET", body: [String:Any]? = nil, authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent(path.components(separatedBy:"?")[0]))
        if let query = path.split(separator:"?", maxSplits:1).last, path.contains("?") {
            var components = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
            components.percentEncodedQuery = String(query); request.url = components.url!
        }
        request.httpMethod = method; request.timeoutInterval = 25
        if authenticated, let token = sessionToken { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject:body); request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let response = response as? HTTPURLResponse else { throw APIProblem(message:"Could not reach the server.") }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with:data) as? [String:Any])?["error"] as? String ?? "Request failed. Try again."
            if response.statusCode == 401 && authenticated { clearSession() }
            throw APIProblem(message:message)
        }
        return data
    }
    func authenticate(_ mode: String, name: String, email: String, password: String, recovery: String) async {
        await run(refresh:false) {
            let data = try await self.call(mode,method:"POST",body:["name":name,"email":email,"password":password,"recovery_key":recovery],authenticated:false)
            let auth = try self.decoder.decode(AuthResponse.self,from:data)
            let saved = Keychain.save("token",auth.token)
            #if !targetEnvironment(simulator)
            guard saved == errSecSuccess else { throw APIProblem(message:"Could not securely save your login. Unlock your iPhone and try again.") }
            #else
            // Unsigned simulator builds can lack Keychain entitlements. Keep this
            // session in memory only; physical devices always require secure storage.
            _ = saved
            #endif
            self.sessionToken = auth.token
            Keychain.save("user",auth.user.id)
            if let key = auth.recoveryKey { Keychain.save("recovery",key); self.recoveryKey = key }
            self.signedIn = true
            try await self.load()
            if auth.recoveryKey != nil { self.needsRecoverySave = true }
        }
    }
    func load() async throws {
        let data = try await call("snapshot")
        let state = try decoder.decode(Snapshot.self,from:data)
        snapshot = state
        if !state.networks.contains(where: { $0.id == selectedNetwork }) { selectedNetwork = state.networks.first?.id ?? "" }
        if UserDefaults.standard.object(forKey:cursorKey) == nil { UserDefaults.standard.set(state.cursor,forKey:cursorKey) }
    }
    func run(refresh: Bool = true, _ action: () async throws -> Void) async {
        guard !working else { return }
        working = true
        defer { working = false }
        do { try await action(); if refresh && signedIn { try await load() } }
        catch { self.error = error.localizedDescription }
    }
    func mutate(_ path: String, method: String = "POST", _ body: [String:Any] = [:]) async throws {
        _ = try await call(path,method:method,body:body)
    }
    func refresh() async { await run { } }
    func clearSession() {
        Keychain.save("token",nil); Keychain.save("user",nil); Keychain.save("recovery",nil)
        sessionToken = nil; needsRecoverySave = false
        snapshot = nil; signedIn = false; recoveryKey = nil; selectedNetwork = ""; events = []
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:AppDelegate.refreshId)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    func logout() async { await run(refresh:false) { try await self.mutate("logout"); self.clearSession() } }
    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])
            notifications = allowed; UserDefaults.standard.set(allowed,forKey:"notifications")
            if allowed { AppDelegate.schedule() }
            else { error = "Notifications are disabled. You can enable them in iPhone Settings → Notifications → Crash." }
        } catch { self.error = error.localizedDescription }
    }
    func disableNotifications() {
        notifications = false; UserDefaults.standard.set(false,forKey:"notifications")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:AppDelegate.refreshId)
    }
    func pollEvents() async -> Bool {
        guard signedIn, !polling else { return true }
        polling = true; defer { polling = false }
        do {
            // Establish a baseline before the first fetch on this account/device.
            if UserDefaults.standard.object(forKey:cursorKey) == nil { try await load() }
            for _ in 0..<10 {
                try Task.checkCancellation()
                let after = UserDefaults.standard.integer(forKey:cursorKey)
                let page = try decoder.decode(EventPage.self,from:try await call("events?after=\(after)"))
                for event in page.events {
                    if !events.contains(where: { $0.id == event.id }) { events.insert(event,at:0) }
                    if notifications {
                        let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.body; content.sound = .default
                        content.userInfo = ["network_id":event.networkId]
                        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"event-\(event.id)",content:content,trigger:nil))
                    }
                }
                events = Array(events.prefix(100))
                UserDefaults.standard.set(page.cursor,forKey:cursorKey)
                if page.events.count < 100 { break }
            }
            return true
        } catch { return false }
    }
}

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let refreshId = "uk.co.leobrown.crash.refresh"
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier:Self.refreshId,using:nil) { task in
            Task { @MainActor in
                Self.schedule()
                let work = Task { @MainActor in await Store.shared.pollEvents() }
                task.expirationHandler = { work.cancel() }
                let success = await work.value
                task.setTaskCompleted(success:success)
            }
        }
        return true
    }
    static func schedule() {
        guard Store.shared.signedIn, Store.shared.notifications else { return }
        let request = BGAppRefreshTaskRequest(identifier:refreshId)
        request.earliestBeginDate = Date(timeIntervalSinceNow:15*60)
        try? BGTaskScheduler.shared.submit(request)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner,.sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let network = response.notification.request.content.userInfo["network_id"] as? String
        await MainActor.run { if let network { Store.shared.selectedNetwork = network } }
    }
}
