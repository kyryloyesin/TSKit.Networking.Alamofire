import Foundation
import TSKit_Networking

open class AlamofireRequestCallBuilder: AnyRequestCallBuilder {

    private let request: AnyRequest

    private var queue: DispatchQueue = DispatchQueue.global()

    private var handlers: [ResponseHandler] = []

    public required init(request: AnyRequest) {
        self.request = request
    }

    open func dispatch(to queue: DispatchQueue) -> Self {
        self.queue = queue
        return self
    }

    open func response<ResponseType, StatusSequenceType>(_ response: ResponseType.Type,
                                                         forStatuses statuses: StatusSequenceType,
                                                         handler: @escaping ResponseResultCompletion<ResponseType>) -> Self where ResponseType: AnyResponse, StatusSequenceType: Sequence, StatusSequenceType.Element == UInt {
        addResponse(response, forStatuses: Array(statuses), handler: handler)
        return self
    }

    open func response<ResponseType>(_ response: ResponseType.Type,
                                     forStatuses statuses: UInt...,
                                     handler: @escaping ResponseResultCompletion<ResponseType>) -> Self where ResponseType: AnyResponse {
        addResponse(response, forStatuses: statuses, handler: handler)
        return self
    }

    /// Attaches handler for any response
    open func response<ResponseType>(_ response: ResponseType.Type,
                                     handler: @escaping ResponseResultCompletion<ResponseType>) -> Self where ResponseType: AnyResponse {
        return self.response(response, forStatuses: 100..<600, handler: handler)
    }

    open func make() -> AnyRequestCall {
        return AlamofireRequestCall(request: request,
                                    queue: queue,
                                    handlers: handlers)
    }

    private func addResponse<ResponseType>(_ response: ResponseType.Type,
                                           forStatuses statuses: [UInt],
                                           handler: @escaping ResponseResultCompletion<ResponseType>) where ResponseType: AnyResponse {
        handlers.append(ResponseHandler(statuses: statuses, handler: { res in
            switch res {
            case .success(let response): handler(.success(response: response as! ResponseType))
            case .failure(let error): handler(.failure(error: error))
            }
        }))
    }
}
