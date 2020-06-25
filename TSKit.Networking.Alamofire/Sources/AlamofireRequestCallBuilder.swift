// - Since: 01/20/2018
// - Author: Arkadii Hlushchevskyi
// - Copyright: © 2020. Arkadii Hlushchevskyi.
// - Seealso: https://github.com/adya/TSKit.Networking.Alamofire/blob/master/LICENSE.md

import Foundation
import TSKit_Networking

public class AlamofireRequestCallBuilder: AnyRequestCallBuilder {

    private let request: AnyRequestable

    private var queue: DispatchQueue = defaultQueue

    private var handlers: [ResponseHandler] = []
    
    private var errorHandler: ErrorHandler?

    private var progressClosures: [(Progress) -> Void] = []

    private static var defaultQueue: DispatchQueue {
        .global()
    }
    
    public required init(request: AnyRequestable) {
        self.request = request
    }

    public func dispatch(to queue: DispatchQueue) -> Self {
        self.queue = queue
        return self
    }

    public func response<ResponseType, StatusSequenceType>(_ response: ResponseType.Type,
                                                           forStatuses statuses: StatusSequenceType,
                                                           handler: @escaping ResponseCompletion<ResponseType>) -> Self where ResponseType: AnyResponse, StatusSequenceType: Sequence, StatusSequenceType.Element == Int {
        addResponse(response, forStatuses: Array(statuses), handler: handler)
        return self
    }

    public func response<ResponseType>(_ response: ResponseType.Type,
                                       forStatuses statuses: Int...,
                                       handler: @escaping ResponseCompletion<ResponseType>) -> Self where ResponseType: AnyResponse {
        addResponse(response, forStatuses: statuses, handler: handler)
        return self
    }

    /// Attaches handler for any response
    public func response<ResponseType>(_ response: ResponseType.Type,
                                       handler: @escaping ResponseCompletion<ResponseType>) -> Self where ResponseType: AnyResponse {
        return self.response(response, forStatuses: request.statusCodes, handler: handler)
    }
    
    public func error<ErrorType>(_ error: ErrorType.Type, handler: @escaping ErrorCompletion<ErrorType>) -> Self where ErrorType : AnyNetworkServiceBodyError {
        errorHandler = .init(errorType: error, handler: { error in
            handler(error as! ErrorType)
        })
        return self
    }

    public func progress(_ closure: @escaping (Progress) -> Void) -> Self {
        self.progressClosures.append(closure)
        return self
    }

    public func make() -> AnyRequestCall? {
        defer {
            handlers.removeAll()
            queue = AlamofireRequestCallBuilder.defaultQueue
        }
        return AlamofireRequestCall(request: request,
                                    queue: queue,
                                    handlers: handlers,
                                    errorHandler: errorHandler,
                                    progressClosures: progressClosures)
    }

    private func addResponse<ResponseType>(_ response: ResponseType.Type,
                                           forStatuses statuses: [Int],
                                           handler: @escaping ResponseCompletion<ResponseType>) where ResponseType: AnyResponse {
        handlers.append(ResponseHandler(statuses: Set(statuses), responseType: response, handler: { response in
            handler(response as! ResponseType)
        }))
    }
}
