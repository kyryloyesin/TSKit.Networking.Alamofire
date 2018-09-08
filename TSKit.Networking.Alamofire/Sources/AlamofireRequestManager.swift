import Alamofire
import TSKit_Networking
import TSKit_Core

/**
 RequestManager is part of TSNetworking layer. It provides a way to do request calls defined by Request objects.
 Key features:
 1. It is designed to be used directly without any sublasses.
 2. Highly configurable via configuration object.
 3. Sync multiple requests.
 4. Simple and obvious way to create request calls.
 
 - Requires:   iOS  [2.0; 8.0)
 - Requires:
 * Alamofire framework
 * TSKit framework
 
 - Version:    2.0
 - Since:      10/26/2016
 - Author:     AdYa
 */
public class AlamofireRequestManager: AnyRequestManager {
    
    public var errorHandlers: [RequestError : () -> Void] = [:]
    
    fileprivate let manager: Alamofire.SessionManager
    
    fileprivate let configuration: RequestManagerConfiguration
    
    fileprivate var baseUrl: String? {
        return configuration.baseUrl
    }
    
    fileprivate var defaultHeaders: [String : String]? {
        return configuration.headers
    }
    
    public func request(_ requestCall: AnyRequestCall,
                        progressCompletion: RequestProgressCompletion? = nil,
                        completion: RequestCompletion? = nil) {
        let request = requestCall.request
        let compoundCompletion: AnyResponseResultCompletion = {
            requestCall.completion?($0)
            completion?(EmptyResult(responseResult: $0))
        }
        let type = requestCall.responseType
        var aRequest: Alamofire.DataRequest?
        if let multipartRequest = request as? MultipartRequest {
            self.createMultipartRequest(multipartRequest, responseType: type, completion: compoundCompletion) {
                aRequest = $0.validate(statusCode: request.statusCodes)
                if let aRequest = aRequest {
                    requestCall.token = AlamofireRequestToken(request: aRequest)
                }
                self.executeRequest(aRequest, withRequest: request, responseType: type, queue: requestCall.queue, completion: compoundCompletion)
            }
        } else {
            aRequest = self.createRegularRequest(request, responseType: type, completion: compoundCompletion)?
                .validate(statusCode: request.statusCodes)
            if let aRequest = aRequest {
                requestCall.token = AlamofireRequestToken(request: aRequest)
            }
            self.executeRequest(aRequest,
                                withRequest: request,
                                responseType: type,
                                queue: requestCall.queue,
                                progressCompletion: progressCompletion,
                                completion: compoundCompletion)
        }
        
    }
    
    public func request(_ requestCalls: [AnyRequestCall],
                        option: ExecutionOption,
                        completion: ((EmptyResult) -> Void)? = nil) {
        switch option {
        case .executeAsynchronously:
            self.asyncRequest(requestCalls, completion: completion)
        case .executeSynchronously(let ignoreFailures):
            self.syncRequest(requestCalls, ignoreFailures: ignoreFailures, completion: completion)
        }
    }
    
    private func executeRequest(_ aRequest: Alamofire.DataRequest?,
                                withRequest request: TSKit_Networking.Request,
                                responseType: AnyResponse.Type,
                                queue: DispatchQueue,
                                progressCompletion: RequestProgressCompletion? = nil,
                                completion: @escaping AnyResponseResultCompletion) {
        guard let aRequest = aRequest else {
            print("\(type(of: self)): Failed to execute request: \(request)")
            queue.async {
                completion(.failure(error: .invalidRequest))
            }
            return
        }
        if let baseUrl = request.baseUrl ?? self.baseUrl {
            print("\(type(of: self)): Request resolved to: \(baseUrl)")
        } else {
            print("\(type(of: self)): Warning: base URL wasn't defined for request\n\(request.description)")
            
        }
        let headers = self.constructHeaders(withRequest: request)
        print("\(type(of: self)): Executing request: \(request)")
        print("\(type(of: self)): Headers request: \(headers)")
        let _ = self.appendResponse(aRequest,
                                    request: request,
                                    responseType: responseType,
                                    queue: queue,
                                    progressCompletion: progressCompletion,
                                    completion: completion)
    }
    
    public required init(configuration: RequestManagerConfiguration) {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = Double(configuration.timeout)
        self.manager = Alamofire.SessionManager(configuration: sessionConfiguration)
        self.configuration = configuration
    }
    
    private var isReady: Bool {
        return self.baseUrl != nil
    }
    
}

// MARK: - Multiple requests.
private extension AlamofireRequestManager {
    func syncRequest(_ requestCalls: [AnyRequestCall],
                     ignoreFailures: Bool,
                     lastResult: EmptyResult? = nil,
                     completion: ((EmptyResult) -> Void)?) {
        var calls = requestCalls
        guard let call = calls.first else {
            guard let result = lastResult else {
                completion?(.failure(error: .invalidRequest))
                return
            }
            completion?(result)
            return
        }
        self.request(call) { result in
            if ignoreFailures {
                calls.removeFirst()
                self.syncRequest(calls, ignoreFailures: ignoreFailures, lastResult: nil, completion: completion)
                
            } else if case .success = result {
                calls.removeFirst()
                guard call.token != nil else { return }
                
                self.syncRequest(calls, ignoreFailures: ignoreFailures, lastResult: .success, completion: completion)
                
            } else if case let .failure(error) = result {
                completion?(.failure(error: error))
            }
        }
    }
    
    func asyncRequest(_ requestCalls: [AnyRequestCall], completion: ((EmptyResult) -> Void)?) {
        let group = DispatchGroup()
        var response: EmptyResult? = nil
        requestCalls.forEach {
            group.enter()
            self.request($0) { res in
                switch res {
                case .success: response = .success
                case let .failure(error): response = .failure(error: error)
                }
                group.leave()
            }
        }
        group.notify(queue: DispatchQueue.main) {
            if let response = response {
                completion?(response)
            } else {
                completion?(.failure(error: .failedRequest))
            }
        }
    }
}

// MARK: - Constructing request properties.
private extension AlamofireRequestManager {
    
    private enum ApplicationLayerProtocol: String {
        case http = "http://"
        case https = "https://"
    }
    
    func constructUrl(withRequest request: TSKit_Networking.Request) -> String? {
        guard !request.url.contains(ApplicationLayerProtocol.http.rawValue) &&
            !request.url.contains(ApplicationLayerProtocol.https.rawValue) else {
                return request.url
        }
        
        guard let baseUrl = (request.baseUrl ?? self.baseUrl) else {
            print("\(type(of: self)): Neither default baseUrl nor request's baseUrl had been specified.")
            return nil
        }
        
        let url = request.url.hasPrefix("/") ? request.url : "/\(request.url)"
        return "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(url)"
    }
    
    func constructHeaders(withRequest request: TSKit_Networking.Request) -> [String : String]? {
        var headers = self.defaultHeaders
        if let customHeaders = request.headers {
            if headers == nil {
                headers = customHeaders
            } else if headers != nil {
                headers! += customHeaders
            }
        }
        return headers
    }
    
}

// MARK: - Constructing regular Alamofire request
private extension AlamofireRequestManager {
    func createRegularRequest(_ request: TSKit_Networking.Request,
                              responseType type: AnyResponse.Type,
                              completion: AnyResponseResultCompletion) -> Alamofire.DataRequest? {
        guard let url = self.constructUrl(withRequest: request) else {
            completion(.failure(error: .invalidRequest))
            return nil
        }
        let method = HTTPMethod(method: request.method)
        let encoding = from(encoding: request.encoding)
        let headers = self.constructHeaders(withRequest: request)
        return self.manager.request(url, method: method, parameters: request.parameters, encoding: encoding,
                                    headers: headers)
    }
    
    private func from(encoding: RequestEncoding) -> Alamofire.ParameterEncoding {
        switch encoding {
        case .json: return JSONEncoding.default
        case .url: return URLEncoding.default
        case .formData: return URLEncoding.default
        }
    }
    
}

// MARK: - Constructing multipart Alamofire request.
private extension AlamofireRequestManager {
    
    func createMultipartRequest(_ request: MultipartRequest,
                                responseType: AnyResponse.Type,
                                completion: @escaping AnyResponseResultCompletion,
                                creationCompletion: @escaping (_ createdRequest: Alamofire.DataRequest) -> Void) {
        guard var url = self.constructUrl(withRequest: request) else {
            completion(.failure(error: .invalidRequest))
            return
        }
        let method = HTTPMethod(method: request.method)
        let headers = self.constructHeaders(withRequest: request)
        var urlParams: [String : Any]?
        var dataParams: [String : Any]? = request.parameters // by default all parameters are dataParams
        if let params = request.parameters {
            urlParams = params.filtered {
                if let customEncoding = request.parametersEncodings?[$0.0], customEncoding == RequestEncoding.url {
                    return true
                }
                return false
            }
            if let urlParams = urlParams {
                urlParams.forEach {
                    url = self.encodeURLParam($0.1, withName: $0.0, inURL: url)
                }
                dataParams = params.filtered { name, _ in
                    return !urlParams.contains { name == $0.0 }
                }
            }
            print("\(type(of: self)): Encoded params into url: \(url)\n")
        }
        print("\(type(of: self)): Encoding data for multipart...")
        self.manager.upload(multipartFormData: { formData in
            if let files = request.files, !files.isEmpty {
                print("\(type(of: self)): Appending \(files.count) in-memory files...\n")
                files.forEach {
                    print("\(type(of: self)): Appending file \($0)...\n")
                    
                    formData.append($0.value, withName: $0.name, fileName: $0.fileName, mimeType: $0.mimeType)
                }
                
            }
            if let files = request.filePaths, !files.isEmpty {
                print("\(type(of: self)): Appending \(files.count) files from storage...\n")
                files.forEach {
                    print("\(type(of: self)): Appending file \($0)...\n")
                    formData.append($0.value,
                                    withName: $0.name,
                                    fileName: ($0.value.lastPathComponent as NSString).deletingPathExtension,
                                    mimeType: "application/octet-stream")
                }
                
            }
            
            if let dataParams = dataParams {
                dataParams.forEach {
                    print("\(type(of: self)): Encoding parameter '\($0.0)'...")
                    self.appendParam($0.1, withName: $0.0, toFormData: formData,
                                     usingEncoding: request.parametersEncoding)
                }
            }
        }, to: url, method: method, headers: headers
            , encodingCompletion: { encodingResult in
                switch encodingResult {
                case let .success(aRequest, _, _):
                    creationCompletion(aRequest)
                case .failure(let error):
                    print("\(type(of: self)): Failed to encode data with error: \(error).")
                    completion(.failure(error: .invalidRequest))
                }
        })
        
    }
    
    func createParameterComponent(_ param: Any, withName name: String) -> [(String, String)] {
        var comps = [(String, String)]()
        if let array = param as? [Any] {
            array.forEach {
                comps += self.createParameterComponent($0, withName: "\(name)[]")
            }
        } else if let dictionary = param as? [String : Any] {
            dictionary.forEach { key, value in
                comps += self.createParameterComponent(value, withName: "\(name)[\(key)]")
            }
        } else {
            comps.append((name, "\(param)"))
        }
        return comps
    }
    
    func encodeURLParam(_ param: Any, withName name: String, inURL url: String) -> String {
        let comps = self.createParameterComponent(param, withName: name).map { "\($0)=\($1)" }
        return "\(url)?\(comps.joined(separator: "&"))"
    }
    
    /// Appends param to the form data.
    func appendParam(_ param: Any,
                     withName name: String,
                     toFormData formData: MultipartFormData,
                     usingEncoding encoding: UInt) {
        let comps = self.createParameterComponent(param, withName: name)
        comps.forEach {
            guard let data = $0.1.data(using: String.Encoding(rawValue: encoding)) else {
                print("\(type(of: self)): Failed to encode parameter '\($0.0)'")
                return
            }
            formData.append(data, withName: $0.0)
        }
    }
}

// MARK: - Constructing Alamofire response.
private extension AlamofireRequestManager {
    
    func appendResponse(_ aRequest: Alamofire.DataRequest,
                        request: TSKit_Networking.Request,
                        responseType: AnyResponse.Type,
                        queue: DispatchQueue,
                        progressCompletion: RequestProgressCompletion? = nil,
                        completion: @escaping AnyResponseResultCompletion) -> Alamofire.DataRequest {
        switch responseType.kind {
        case .json: return aRequest.downloadProgress(closure: { (progress) in
            progressCompletion?(Float(progress.fractionCompleted))
        }).responseJSON(queue: queue) { res in
            if let error = res.result.error {
                print("\(type(of: self)): Internal error while sending request:\n\(error)")
                if let response = res.response {
                    if response.statusCode == RequestError.unauthorized.code {
                        completion(.failure(error: .unauthorized))
                        self.errorHandlers[RequestError.unauthorized]?()
                    } else {
                        completion(.failure(error: .validationError(ErrorResponse(response: response, data: res.data))))
                    }
                } else {
                    completion(.failure(error: .invalidRequest))
                }
            } else if let json = res.result.value,
                let status = res.response?.statusCode {
                print("\(type(of: self)): Received JSON:\n\(json).")
                if let response = responseType.init(request: request, status: status, body: json) {
                    completion(.success(response: response))
                } else {
                    print("\(type(of: self)): Specified response type couldn't handle '\(responseType.kind)'. Response '\(responseType)' has '\(responseType.kind)'.")
                    completion(.failure(error: .invalidResponseKind))
                }
            } else {
                print("\(type(of: self)): Couldn't get any response.")
                completion(.failure(error: .failedRequest))
            }
            }
        case .data: return aRequest.downloadProgress(closure: { (progress) in
            progressCompletion?(Float(progress.fractionCompleted))
        }).responseData(queue: queue) { res in
            if let error = res.result.error {
                print("\(type(of: self)): Internal error while sending request:\n\(error)")
                if let response = res.response {
                    if response.statusCode == RequestError.unauthorized.code {
                        completion(.failure(error: .unauthorized))
                        self.errorHandlers[RequestError.unauthorized]?()
                    } else {
                        completion(.failure(error: .validationError(ErrorResponse(response: response, data: res.data))))
                    }
                } else {
                    completion(.failure(error: .invalidRequest))
                }
            } else if let data = res.result.value,
                let status = res.response?.statusCode {
                print("\(type(of: self)): Received \(data.size) of data.")
                if let response = responseType.init(request: request, status: status, body: data) {
                    completion(.success(response: response))
                } else {
                    print("\(type(of: self)): Specified response type couldn't handle '\(responseType.kind)' response '\(responseType)' has '\(responseType.kind)'.")
                    completion(.failure(error: .invalidResponseKind))
                }
            } else {
                print("\(type(of: self)): Couldn't get any response.")
                completion(.failure(error: .failedRequest))
            }
            }
        case .string: return aRequest.downloadProgress(closure: { (progress) in
            progressCompletion?(Float(progress.fractionCompleted))
        }).responseString(queue: queue) { res in
            if let error = res.result.error {
                print("\(type(of: self)): Internal error while sending request:\n\(error)")
                if let response = res.response {
                    if response.statusCode == RequestError.unauthorized.code {
                        completion(.failure(error: .unauthorized))
                        self.errorHandlers[RequestError.unauthorized]?()
                    } else {
                        completion(.failure(error: .validationError(ErrorResponse(response: response, data: res.data))))
                    }
                } else {
                    completion(.failure(error: .invalidRequest))
                }
            } else if let string = res.result.value,
                let status = res.response?.statusCode {
                print("\(type(of: self)): Received string : \(string).")
                if let response = responseType.init(request: request, status: status, body: string) {
                    completion(.success(response: response))
                } else {
                    print("\(type(of: self)): Specified response type couldn't handle '\(responseType.kind)' response '\(responseType)' has '\(responseType.kind)'.")
                    completion(.failure(error: .invalidResponseKind))
                }
            } else {
                print("\(type(of: self)): Couldn't get any response.")
                completion(.failure(error: .failedRequest))
            }
            }
        case .empty: return aRequest.downloadProgress(closure: { (progress) in
            progressCompletion?(Float(progress.fractionCompleted))
        }).response(queue: queue) { res in
            if let error = res.error {
                print("\(type(of: self)): Internal error while sending request:\n\(error).")
                if let response = res.response {
                    if response.statusCode == RequestError.unauthorized.code {
                        completion(.failure(error: .unauthorized))
                        self.errorHandlers[RequestError.unauthorized]?()
                    } else {
                        completion(.failure(error: .validationError(ErrorResponse(response: response, data: res.data))))
                    }
                } else {
                    completion(.failure(error: .invalidRequest))
                }
            } else if let status = res.response?.statusCode,
                let response = responseType.init(request: request, status: status, body: [:]) {
                // FIXME: Empty dictionary as a workaround.
                completion(.success(response: response))
            } else {
                print("\(type(of: self)): Specified response type couldn't handle '\(responseType.kind)' response '\(responseType)' has '\(responseType.kind)'.")
                completion(.failure(error: .invalidResponseKind))
            }
            }
        }
    }
}

// MARK: - Mapping abstract enums to Alamofire enums.
private extension Alamofire.HTTPMethod {
    init(method: RequestMethod) {
        switch method {
        case .get: self = .get
        case .post: self = .post
        case .patch: self = .patch
        case .delete: self = .delete
        case .put: self = .put
        }
    }
}

private class AlamofireRequestToken: AnyCancellationToken {
    
    private weak var request: Alamofire.Request?
    
    init(request: Alamofire.Request) {
        self.request = request
    }
    
    func cancel() {
        request?.cancel()
    }
}
