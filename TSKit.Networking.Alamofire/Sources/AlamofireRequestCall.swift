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

    static func identifier(from request: Alamofire.Request) -> Int? {
        request.task?.taskIdentifier
    }
    
    
    /// `Request` to be called.
    public let request: AnyRequestable

    /// Identifier that uniquely identifies given call after it's been started.
    private(set) var identifier: Int?
    
    var token: Alamofire.Request? {
        didSet {
            if let id = token.flatMap(AlamofireRequestCall.identifier(from:)) {
                identifier = id
            }
        }
    }

    let queue: DispatchQueue

    let handlers: [ResponseHandler]
    
    var errorHandler: ErrorHandler?

    let progress: [ProgressClosure]

    /// - Parameter request: Configured Request object.
    /// - Parameter responseType: Type of expected Response object.
    /// - Parameter completion: Closure to be called upon receiving response.
    init(request: AnyRequestable,
         queue: DispatchQueue,
         handlers: [ResponseHandler],
         errorHandler: ErrorHandler?,
         progressClosures: [ProgressClosure]) {
        self.request = request
        self.queue = queue
        self.handlers = handlers
        self.errorHandler = errorHandler
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

    let handler: AnyResponseCompletion
}

struct ErrorHandler {
    
    let errorType: AnyNetworkServiceError.Type

    var handler: AnyErrorCompletion?
    
    mutating func handle(request: AnyRequestable,
                         response: HTTPURLResponse?,
                         error: Error?,
                         sessionError: Error?,
                         reason: NetworkServiceErrorReason,
                         body: Any?) {
        
        let handler = self.handler
        self.handler = nil
        handler?(errorType.init(request: request,
                                response: response,
                                error: error,
                                sessionError: sessionError,
                                reason: reason,
                                body: body))
    }
}

typealias ProgressClosure = (Progress) -> Void
