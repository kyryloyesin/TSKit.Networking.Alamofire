/**
 RequestCall represents a single request call with configured `Request` object and defined type of expected `Response` object.

 - Requires:    iOS  [2.0; 8.0)
 - Requires:    Swift 2+
 - Version:     3.0
 - Since:       10/30/2016
 - Author:      AdYa
 */

import Dispatch
import TSKit_Networking

class AlamofireRequestCall: AnyRequestCall {

    /// `Request` to be called.
    public let request: AnyRequest

    var token: AnyCancellationToken?

    let queue: DispatchQueue

    let handlers: [ResponseHandler]

    /// - Parameter request: Configured Request object.
    /// - Parameter responseType: Type of expected Response object.
    /// - Parameter completion: Closure to be called upon receiving response.
    init(request: AnyRequest, queue: DispatchQueue = DispatchQueue.global(), handlers: [ResponseHandler]) {
        self.request = request
        self.queue = queue
        self.handlers = handlers
    }

    public func cancel() {
        token?.cancel()
        token = nil
    }
}

struct ResponseHandler {

    let statuses: [UInt]

    let handler: AnyResponseResultCompletion
}
