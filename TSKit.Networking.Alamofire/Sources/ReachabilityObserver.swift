import Foundation
import Alamofire
import TSKit_Log
import TSKit_Injection

// TODO: Integrate into TSNetworking+Alamofire
/// An object that observes any changes in network reachability and notifies about it occurrences.
/// - Note: Used via `shared`.
class ReachabilityObserver {

    /// Notifications posted by `ReachabilityObserver`.
    enum Notification: String {

        /// Notification posted when reachability status has changed.
        /// - Parameter isReachable: A `Bool` flag indicating current reachability state.
        case didChange = "ReachabilityObserver.DidChange"

        var name: Foundation.Notification.Name {
            return Foundation.Notification.Name(rawValue: rawValue)
        }

        enum UserInfoKey: String, Hashable {

            case isReachableKey = "isReachable"

            var hashValue: Int {
                return rawValue.hashValue
            }
        }
    }
    
    private let log = try? Injector.inject(AnyLogger.self)

    /// `ReachabilityObserver` observes any changes in network reachability and notifies about it occurrences.
    static let shared = ReachabilityObserver()

    /// Underlying manager, providing reachability information.
    private let manager = NetworkReachabilityManager()

    private init() {
        manager?.listenerQueue = .global()
    }

    /// Flag indicating whether or not network is currently reachable.
    private(set) var isReachable: Bool = false

    /// Starts observation of reachability status.
    func startObserving() {
        guard let manager = manager else {
            log?.severe("Failed to setup system observation.")
            return
        }

        guard manager.listener == nil else {
            log?.warning("Attempt to start another network reachability observation.")
            return
        }

        manager.listener = { [weak self] status in
            switch status {
            case .notReachable, .unknown: self?.isReachable = false
            case .reachable: self?.isReachable = true
            }
            self?.notify()
        }

        if !manager.startListening() {
            log?.warning("Failed to start network reachability observation.")
        }
    }

    /// Stops observation of reachability status.
    func stopObserving() {
        manager?.stopListening()
        manager?.listener = nil
    }

    private func notify() {
        NotificationCenter.default.post(name: Notification.didChange.name,
                                        object: self,
                                        userInfo: [Notification.UserInfoKey.isReachableKey : isReachable])
    }
}
