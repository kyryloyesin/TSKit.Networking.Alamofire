import Foundation
import TSKit_Networking

public class AlamofireRequestCallBuilder: AnyRequestCallBuilder {

    private let request: AnyRequest

    private var queue: DispatchQueue = DispatchQueue.global()

    private var handlers: [ResponseHandler] = []

    private var progressClosures: [(Progress) -> Void] = []

    public required init(request: AnyRequest) {
        self.request = request
    }

    public func dispatch(to queue: DispatchQueue) -> Self {
        self.queue = queue
        return self
    }

    public func response<ResponseType, StatusSequenceType>(_ response: ResponseType.Type,
                                                           forStatuses statuses: StatusSequenceType,
                                                           handler: @escaping ResponseResultCompletion<ResponseType>) -> Self where ResponseType: BaseResponse, StatusSequenceType: Sequence, StatusSequenceType.Element == UInt {
        addResponse(response, forStatuses: Array(statuses), handler: handler)
        return self
    }

    public func response<ResponseType>(_ response: ResponseType.Type,
                                       forStatuses statuses: UInt...,
                                       handler: @escaping ResponseResultCompletion<ResponseType>) -> Self where ResponseType: BaseResponse {
        addResponse(response, forStatuses: statuses, handler: handler)
        return self
    }

    /// Attaches handler for any response
    public func response<ResponseType>(_ response: ResponseType.Type,
                                       handler: @escaping ResponseResultCompletion<ResponseType>) -> Self where ResponseType: BaseResponse {
        return self.response(response, forStatuses: 100..<600, handler: handler)
    }

    public func progress(_ closure: @escaping (Progress) -> Void) -> Self {
        self.progressClosures.append(closure)
        return self
    }

    public func make() -> AnyRequestCall? {
        return AlamofireRequestCall(request: request,
                                    queue: queue,
                                    handlers: handlers,
                                    progressClosures: progressClosures)
    }

    private func addResponse<ResponseType>(_ response: ResponseType.Type,
                                           forStatuses statuses: [UInt],
                                           handler: @escaping ResponseResultCompletion<ResponseType>) where ResponseType: BaseResponse {
        handlers.append(ResponseHandler(statuses: Set(statuses), responseType: response, handler: { res in
            switch res {
            case .success(let response): handler(.success(response: response as! ResponseType))
            case .failure(let error): handler(.failure(error: error))
            }
        }))
    }
}
