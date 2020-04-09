// - Since: 10/30/2016
// - Author: Arkadii Hlushchevskyi
// - Copyright: © 2020. Arkadii Hlushchevskyi.
// - Seealso: https://github.com/adya/TSKit.Networking.Alamofire/blob/master/LICENSE.md

import Dispatch
import TSKit_Networking
import Alamofire

/// RequestCall represents a single request call with configured `Request` object and defined type of expected
/// `Response` object.
class AlamofireRequestCall: AnyRequestCall, CustomStringConvertible, CustomDebugStringConvertible {

    /// `Request` to be called.
    public let request: AnyRequestable

    var token: Alamofire.Request?

    let queue: DispatchQueue

    let handlers: [ResponseHandler]

    let progress: [ProgressClosure]

    /// - Parameter request: Configured Request object.
    /// - Parameter responseType: Type of expected Response object.
    /// - Parameter completion: Closure to be called upon receiving response.
    init(request: AnyRequestable,
         queue: DispatchQueue,
         handlers: [ResponseHandler],
         progressClosures: [ProgressClosure]) {
        self.request = request
        self.queue = queue
        self.handlers = handlers
        self.progress = progressClosures
    }

    public func cancel() {
        token?.cancel()
        token = nil
    }
    
    public var description: String {
        return token?.description ?? request.description
    }
    
    public var debugDescription: String {
        return token?.debugDescription ?? request.description
    }
}

struct ResponseHandler {

    let statuses: Set<Int>

    let responseType: AnyResponse.Type

    let handler: AnyResponseResultCompletion
}

typealias ProgressClosure = (Progress) -> Void
