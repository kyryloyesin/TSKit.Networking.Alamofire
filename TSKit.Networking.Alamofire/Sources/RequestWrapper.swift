// - Since: 01/20/2018
// - Author: Arkadii Hlushchevskyi
// - Copyright: © 2020. Arkadii Hlushchevskyi.
// - Seealso: https://github.com/adya/TSKit.Networking.Alamofire/blob/master/LICENSE.md

import Foundation
import Alamofire
import TSKit_Networking

class RequestWrapper {

    var request: Alamofire.Request? {
        didSet {
            notifyIfReady()
        }
    }

    var error: NetworkServiceError? {
        didSet {
            notifyIfFail()
        }
    }

    @discardableResult
    func onReady(_ closure: ((Alamofire.Request) -> Void)?) -> Self {
        onReadyClosure = closure
        return self
    }

    @discardableResult
    func onFail(_ closure: ((NetworkServiceError) -> Void)?) -> Self {
        onFailClosure = closure
        return self
    }

    private var onReadyClosure: ((Alamofire.Request) -> Void)? {
        didSet {
            notifyIfReady()
        }
    }

    private var onFailClosure: ((NetworkServiceError) -> Void)? {
        didSet {
            notifyIfFail()
        }
    }

    private func notifyIfReady() {
        if let request = request {
            onReadyClosure?(request)
        }
    }

    private func notifyIfFail() {
        if let error = error {
            onFailClosure?(error)
        }
    }

    init(_ request: Alamofire.Request? = nil) {
        self.request = request
    }
}
