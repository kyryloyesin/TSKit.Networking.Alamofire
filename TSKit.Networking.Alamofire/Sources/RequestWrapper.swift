import Foundation
import Alamofire

class RequestWrapper {

    var request: Alamofire.Request? {
        didSet {
            notifyIfReady()
        }
    }

    var error: Error? {
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
    func onFail(_ closure: ((Error) -> Void)?) -> Self {
        onFailClosure = closure
        return self
    }

    private var onReadyClosure: ((Alamofire.Request) -> Void)? {
        didSet {
            notifyIfReady()
        }
    }

    private var onFailClosure: ((Error) -> Void)? {
        didSet {
            notifyIfReady()
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
