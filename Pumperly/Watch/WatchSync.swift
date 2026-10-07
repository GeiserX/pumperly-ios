import Foundation
import WatchConnectivity
#if os(watchOS)
import WidgetKit
#endif

/// Keeps the watch's fuel in step with the iPhone's widget fuel, over WatchConnectivity.
///
/// The iPhone sends `{"fuel": raw}` as its application context whenever its fuel changes. The
/// watch stores it in its own App Group container. A fuel picked on the watch afterwards stays
/// until the iPhone's fuel changes again: a repeated delivery of the same context is ignored.
///
/// Compiled into the iPhone app and the watch app.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    static let fuelKey = "fuel"
    /// Watch only: the last fuel received from the iPhone.
    static let lastReceivedKey = "watch.lastPhoneFuel"

    static func context(for fuel: FuelType) -> [String: Any] {
        [fuelKey: fuel.rawValue]
    }

    static func fuel(from context: [String: Any]) -> FuelType? {
        (context[fuelKey] as? String).flatMap(FuelType.init(rawValue:))
    }

    /// The fuel the watch switches to for a received context, or nil to keep its own choice.
    static func fuelToApply(context: [String: Any], lastReceived: String?) -> FuelType? {
        guard let fuel = fuel(from: context), fuel.rawValue != lastReceived else { return nil }
        return fuel
    }

    /// Watch: called on the main queue after a fuel from the iPhone is stored.
    var onFuelReceived: ((FuelType) -> Void)?

    /// Starts the session once. Safe to call repeatedly.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self { session.delegate = self }
        if session.activationState == .notActivated { session.activate() }
    }

    /// Stores a context received from the iPhone, unless it repeats the last one. Returns the
    /// fuel it switched to.
    @discardableResult
    func apply(_ context: [String: Any], settings: SharedSettings = SharedSettings()) -> FuelType? {
        let lastReceived = settings.defaults.string(forKey: Self.lastReceivedKey)
        guard let fuel = Self.fuelToApply(context: context, lastReceived: lastReceived) else { return nil }
        settings.defaults.set(fuel.rawValue, forKey: Self.lastReceivedKey)
        settings.fuel = fuel
        #if os(watchOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        onFuelReceived?(fuel)
        return fuel
    }

    // MARK: iPhone side

    #if os(iOS)
    /// Read and written on the main queue only.
    private var pendingFuel: FuelType?

    /// Sends the fuel to the watch app, now or as soon as the session and the watch allow.
    func send(fuel: FuelType) {
        guard WCSession.isSupported() else { return }
        pendingFuel = fuel
        activate()
        flush()
    }

    private func flush() {
        let session = WCSession.default
        guard let fuel = pendingFuel, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(Self.context(for: fuel))
            pendingFuel = nil
        } catch {
            // Kept pending; the next activation or watch state change tries again.
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch: start a session for it.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app was installed or the paired watch changed: send the current fuel.
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            if self.pendingFuel == nil { self.pendingFuel = SharedSettings().fuel }
            self.flush()
        }
    }
    #endif

    // MARK: Both sides

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            #if os(iOS)
            self.flush()
            #else
            // A context that arrived while the watch app was not running.
            self.apply(session.receivedApplicationContext)
            #endif
        }
    }

    #if os(watchOS)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.apply(applicationContext) }
    }
    #endif
}
