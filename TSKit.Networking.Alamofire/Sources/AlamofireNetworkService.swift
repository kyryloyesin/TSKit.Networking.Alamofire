/// - Since: 01/20/2018
/// - Author: Arkadii Hlushchevskyi
/// - Copyright: © 2018. Arkadii Hlushchevskyi.
/// - Seealso: https://github.com/adya/TSKit.Networking.Alamofire/blob/master/LICENSE.md
/// - Requires: iOS 8.0+
/// - Requires: Alamofire
/// - Requires: TSKit.Core
/// - Requires: TSKit.Networking
/// - Requires: TSKit.Injection
/// - Requires: TSKit.Log

import Alamofire
import TSKit_Networking
import TSKit_Injection
import TSKit_Core
import TSKit_Log


/// RequestManager is part of TSNetworking layer. It provides a way to do request calls defined by Request objects.
/// Key features:
/// 1. It is designed to be used directly without any sublasses.
/// 2. Highly configurable via configuration object.
/// 3. Sync multiple requests.
/// 4. Simple and obvious way to create request calls.
public class AlamofireNetworkService: AnyNetworkService {

    private let log = try? Injector.inject(AnyLogger.self, for: AnyNetworkService.self)

    public var backgroundSessionCompletionHandler: (() -> Void)? {
        get {
            return manager.backgroundCompletionHandler
        }
        set {
            manager.backgroundCompletionHandler = newValue
        }
    }
    
    public var interceptors: [AnyNetworkServiceInterceptor]?

    private let manager: Alamofire.SessionManager

    private let configuration: AnyNetworkServiceConfiguration

    /// Flag determining what type of session tasks should be used.
    /// When working in background all requests are handled by `URLSessionDownloadTask`s,
    /// otherwise `URLSessionDataTask` will be used.
    private var isBackground: Bool {
        return manager.session.configuration.networkServiceType == .background
    }

    private var defaultHeaders: [String : String]? {
        return configuration.headers
    }

    public required init(configuration: AnyNetworkServiceConfiguration) {
        manager = Alamofire.SessionManager(configuration: configuration.sessionConfiguration)
        manager.startRequestsImmediately = false
        self.configuration = configuration
    }

    public func builder(for request: AnyRequestable) -> AnyRequestCallBuilder {
        return AlamofireRequestCallBuilder(request: request)
    }

    public func request(_ requestCalls: [AnyRequestCall],
                        option: ExecutionOption,
                        queue: DispatchQueue = .global(),
                        completion: RequestCompletion? = nil) {
        let calls = requestCalls.map(supportedCall)
        var capturedResult: EmptyResponseResult = .success(response: ())
        guard !calls.isEmpty else {
            completion?(capturedResult)
            return
        }
        
        switch option {
        case .executeAsynchronously(let ignoreFailures):
            let group = completion != nil ? DispatchGroup() : nil
            var requests: [RequestWrapper] = []
            requests = calls.map {
                process($0) { result in
                    group?.leave()
                    if !ignoreFailures,
                       case .failure = result,
                       case .success = capturedResult {
                        requests.forEach { $0.request?.cancel() }
                        capturedResult = result
                    }
                }
            }
            requests.forEach {
                group?.enter()
                $0.onReady {
                    $0.resume()
                }.onFail { error in
                    group?.leave()
                    if !ignoreFailures,
                       case .success = capturedResult {
                        requests.forEach { $0.request?.cancel() }
                        capturedResult = .failure(error: error)
                    }
                }
            }
            group?.notify(queue: queue) { completion?(capturedResult) }

        case .executeSynchronously(let ignoreFailures):

            func executeNext(_ call: AlamofireRequestCall, at index: Int) {
                process(call) { result in
                    if !ignoreFailures,
                       case .failure = result,
                       case .success = capturedResult {
                        completion?(result)

                    }

                    let nextIndex = index + 1
                    guard nextIndex < calls.count else {
                        completion?(.success(response: ()))
                        return
                    }

                    executeNext(calls[nextIndex], at: nextIndex)
                }.onReady { $0.resume() }
                 .onFail {
                     if !ignoreFailures,
                        case .success = capturedResult {
                         completion?(.failure(error: $0))
                     }
                 }
            }

            executeNext(calls.first!, at: 0)
        }
    }

    /// Verifies that specified call is the one that is supported by service.
    private func supportedCall(_ call: AnyRequestCall) -> AlamofireRequestCall {
        guard let supportedCall = call as? AlamofireRequestCall else {
            let message = "'\(AlamofireNetworkService.self)' does not support '\(type(of: call))'. You should use '\(AlamofireRequestCall.self)'."
            log?.severe(message)
            preconditionFailure(message)
        }
        return supportedCall
    }
}

// MARK: - Multiple requests.
private extension AlamofireNetworkService {

    /// Constructs appropriate `Alamofire`'s request object for given `call`.
    /// - Note: The request object must be resumed manually.
    /// - Parameter call: A call for which request object will be constructed.
    /// - Parameter completion: A closure to be called upon receiving response.
    /// - Returns: Constructed `Alamofire`'s request object.
    func process(_ call: AlamofireRequestCall,
                 _ completion: @escaping (EmptyResponseResult) -> Void) -> RequestWrapper {

        let method = HTTPMethod(call.request.method)
        let encoding = call.request.encoding.alamofireEncoding
        let headers = constructHeaders(withRequest: call.request)
        let url = constructUrl(withRequest: call.request)

        if let request = call.request as? AnyMultipartRequestable {
            let wrapper = RequestWrapper()
            manager.upload(multipartFormData: { [weak self] formData in
                request.parameters?.forEach {
                    self?.appendParameter($0.1, named: $0.0, to: formData, using: request.parametersDataEncoding)
                }
                request.files?.forEach { file in
                    if let urlFile = file as? MultipartURLFile {
                        formData.append(urlFile.url,
                                        withName: urlFile.name,
                                        fileName: urlFile.fileName,
                                        mimeType: urlFile.mimeType)
                    } else if let dataFile = file as? MultipartDataFile {
                        formData.append(dataFile.data,
                                        withName: dataFile.name,
                                        fileName: dataFile.fileName,
                                        mimeType: dataFile.mimeType)
                    } else if let streamFile = file as? MultipartStreamFile {
                        formData.append(streamFile.stream,
                                        withLength: streamFile.length,
                                        name: streamFile.name,
                                        fileName: streamFile.fileName,
                                        mimeType: streamFile.mimeType)
                    } else {
                        let message = "Unsupported `AnyMultipartFile` type: \(type(of: file))"
                        self?.log?.severe(message)
                        preconditionFailure(message)
                    }
                }
            },
                           to: url,
                           method: method,
                           headers: headers,
                           encodingCompletion: { [weak self] encodingResult in
                               switch encodingResult {
                               case .success(let request, _, _):
                                   self?.appendProgress(request, queue: call.queue) { progress in
                                       call.progress.forEach { $0(progress) }
                                   }.appendResponse(request, call: call) {
                                       switch $0 {
                                       case .success: completion(.success(response: ()))
                                       case .failure(let error): completion(.failure(error: error))
                                       }
                                   }
                                   wrapper.request = request
                               case .failure(let error):
                                   wrapper.error = error
                               }
                           })
            return wrapper
        } else if isBackground {
            let destination: DownloadRequest.DownloadFileDestination = { tempFileURL, _ in
                let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
                let documentsURL = URL(fileURLWithPath: documentsPath, isDirectory: true)
                let fileURL = documentsURL.appendingPathComponent(tempFileURL.lastPathComponent)

                return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
            }
            let request = manager.download(url,
                                           method: method,
                                           parameters: call.request.parameters,
                                           encoding: encoding,
                                           headers: headers,
                                           to: destination)
            appendProgress(request, queue: call.queue) { progress in
                call.progress.forEach { $0(progress) }
            }.appendResponse(request, call: call) {
                switch $0 {
                case .success: completion(.success(response: ()))
                case .failure(let error): completion(.failure(error: error))
                }
            }
            return RequestWrapper(request)
        } else {
            let request = manager.request(url,
                                          method: method,
                                          parameters: call.request.parameters,
                                          encoding: encoding,
                                          headers: headers)
            appendProgress(request, queue: call.queue) { progress in
                call.progress.forEach { $0(progress) }
            }.appendResponse(request, call: call) {
                switch $0 {
                case .success: completion(.success(response: ()))
                case .failure(let error): completion(.failure(error: error))
                }
            }
            return RequestWrapper(request)
        }
    }
}

// MARK: - Constructing request properties.
private extension AlamofireNetworkService {

    func constructUrl(withRequest request: AnyRequestable) -> URL {
        guard let url = URL(string: (request.host ?? configuration.host)) else {
            let message = "Neither default `host` nor request's `host` had been specified."
            log?.severe(message)
            preconditionFailure(message)
        }
        return url.appendingPathComponent(request.path)
    }

    func constructHeaders(withRequest request: AnyRequestable) -> [String : String] {
        return (defaultHeaders ?? [:]) + (request.headers ?? [:])
    }
}

// MARK: - Constructing multipart Alamofire request.
private extension AlamofireNetworkService {

    func createParameterComponent(_ param: Any, named name: String) -> [(String, String)] {
        var comps = [(String, String)]()
        if let array = param as? [Any] {
            array.forEach {
                comps += self.createParameterComponent($0, named: "\(name)[]")
            }
        } else if let dictionary = param as? [String : Any] {
            dictionary.forEach { key, value in
                comps += self.createParameterComponent(value, named: "\(name)[\(key)]")
            }
        } else {
            comps.append((name, "\(param)"))
        }
        return comps
    }

    func encodeURLParameter(_ param: Any, named name: String, intoUrl url: String) -> String {
        let comps = self.createParameterComponent(param, named: name).map { "\($0)=\($1)" }
        return "\(url)?\(comps.joined(separator: "&"))"
    }

    /// Appends param to the form data.
    func appendParameter(_ param: Any,
                         named name: String,
                         to formData: MultipartFormData,
                         using encoding: String.Encoding) {
        let comps = self.createParameterComponent(param, named: name)
        comps.forEach {
            guard let data = $0.1.data(using: encoding) else {
                print("\(type(of: self)): Failed to encode parameter '\($0.0)'")
                return
            }
            formData.append(data, withName: $0.0)
        }
    }
}

// MARK: - Constructing Alamofire response.
private extension AlamofireNetworkService {

    @discardableResult
    func appendProgress(_ aRequest: Alamofire.DownloadRequest,
                        queue: DispatchQueue,
                        progressCompletion: RequestProgressCompletion? = nil) -> Self {
        if let completion = progressCompletion {
            aRequest.downloadProgress(queue: queue) { (progress) in
                completion(progress)
            }
        }
        return self
    }

    @discardableResult
    func appendProgress(_ aRequest: Alamofire.DataRequest,
                        queue: DispatchQueue,
                        progressCompletion: RequestProgressCompletion? = nil) -> Self {
        aRequest.downloadProgress(queue: queue) { (progress) in
            progressCompletion?(progress)
        }
        return self
    }

    @discardableResult
    func appendResponse(_ aRequest: Alamofire.DataRequest,
                        call: AlamofireRequestCall,
                        completion: @escaping AnyResponseResultCompletion) -> Self {
        aRequest.responseData(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: $0.value,
                                 kind: .data,
                                 call: call,
                                 completion: completion)
        }.responseJSON(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: $0.value,
                                 kind: .json,
                                 call: call,
                                 completion: completion)
        }.responseString(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: $0.value,
                                 kind: .string,
                                 call: call,
                                 completion: completion)
        }.response(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: nil,
                                 kind: .empty,
                                 call: call,
                                 completion: completion)
        }
        return self
    }

    @discardableResult
    func appendResponse(_ aRequest: Alamofire.DownloadRequest,
                        call: AlamofireRequestCall,
                        completion: @escaping AnyResponseResultCompletion) -> Self {
        aRequest.responseData(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: $0.value,
                                 kind: .data,
                                 call: call,
                                 completion: completion)
            try? $0.destinationURL ==>? FileManager.default.removeItem(at:)
        }.responseJSON(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: $0.value,
                                 kind: .json,
                                 call: call,
                                 completion: completion)
            try? $0.destinationURL ==>? FileManager.default.removeItem(at:)
        }.responseString(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: $0.value,
                                 kind: .string,
                                 call: call,
                                 completion: completion)
            try? $0.destinationURL ==>? FileManager.default.removeItem(at:)
        }.response(queue: call.queue) { [weak self] in
            self?.handleResponse($0.response,
                                 error: $0.error,
                                 value: nil,
                                 kind: .empty,
                                 call: call,
                                 completion: completion)
            try? $0.destinationURL ==>? FileManager.default.removeItem(at:)
        }
        return self
    }

    private func handleResponse(_ response: HTTPURLResponse?,
                                error: Error?,
                                value: Any?,
                                kind: ResponseKind,
                                call: AlamofireRequestCall,
                                completion: @escaping AnyResponseResultCompletion) {
        guard let httpResponse = response else {
            log?.severe("HTTP Response was not specified. Response will be ignored.")
            let error = AlamofireNetworkServiceError.missingHttpResponse
            completion(.failure(error: error))
            return
        }
        let status = UInt(httpResponse.statusCode)
        
        let validHandlers = call.handlers.filter { $0.statuses.contains(status) && $0.responseType.kind == kind }
        let shouldProcess =  { self.interceptors?.reduce(true) { $0 && $1.intercept(call: call, response: httpResponse, body: value) } ?? true }
        
        guard validHandlers.isEmpty || shouldProcess() else {
            log?.verbose("At least one interceptor has blocked response for \(call.request).")
            let error = NetworkServiceError.skipped
            completion(.failure(error: error))
            validHandlers.forEach { $0.handler(.failure(error: error)) }
            return
        }
        
        validHandlers.forEach {
            if let error = error {
                log?.debug("Request \(call.request) failed with error: \(error).")
                $0.handler(.failure(error: error))
                completion(.failure(error: error))
                return
            }
            guard let response = $0.responseType.init(response: httpResponse, body: value) else {
                log?.error("Failed to construct response of type '\($0.responseType)' using body: \(value ?? "no body").")
                let error = AlamofireNetworkServiceError.invalidResponse
                $0.handler(.failure(error: error))
                completion(.failure(error: error))
                return
            }
            $0.handler(.success(response: response))
        }
    }
}

// MARK: - Mapping abstract enums to Alamofire enums.
private extension Alamofire.HTTPMethod {

    init(_ method: RequestMethod) {
        switch method {
        case .get: self = .get
        case .post: self = .post
        case .patch: self = .patch
        case .delete: self = .delete
        case .put: self = .put
        case .head: self = .head
        }
    }
}

private extension TSKit_Networking.ParameterEncoding {

    var alamofireEncoding: Alamofire.ParameterEncoding {
        switch self {
        case .json: return JSONEncoding.default
        case .url: return URLEncoding.default
        case .formData: return URLEncoding.default
        }
    }
}
