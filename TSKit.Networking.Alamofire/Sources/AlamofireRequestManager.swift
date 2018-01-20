import Alamofire
import TSKit
/**
 RequestManager is part of TSNetworking layer. It provides a way to do request calls defined by Request objects.
 Key features:
 1. It is designed to be used directly without any sublasses.
 2. Highly configurable via configuration object.
 3. Sync multiple requests.
 4. Simple and obvious way to create request calls.
 
 - Requires:   iOS  [2.0; 8.0)
 - Requires:   
 * TSNetworking framework
 * TSUtils
 
 - Version:    2.0
 - Since:      10/26/2016
 - Author:     AdYa
 */
public class AlamofireRequestManager : RequestManager {
    
    private let manager : Alamofire.Manager
    private var baseUrl : String?
    private var defaultHeaders : [String : String]?
    
    public func request(requestCall : AnyRequestCall, completion : RequestCompletion? = nil) {
        let request = requestCall.request
        let compoundCompletion : AnyResponseResultCompletion = {
            requestCall.completion?($0)
            completion?(TSKit.Result(responseResult: $0))
        }
        let type = requestCall.responseType
        var aRequest : Alamofire.Request?
        if let multipartRequest = request as? MultipartRequest {
            self.createMultipartRequest(multipartRequest, responseType: type, completion: compoundCompletion) {
                aRequest = $0//.validate()
                self.executeRequest(aRequest, withRequest: request, type: type, completion: compoundCompletion)
            }
        } else {
            aRequest = self.createRegularRequest(request, responseType : type, completion: compoundCompletion)//?.validate()
            self.executeRequest(aRequest, withRequest: request, type: type, completion: compoundCompletion)
        }
        
    }
    
    public func request(requestCalls : [AnyRequestCall], option : ExecutionOption, completion : ((TSKit.Result) -> Void)? = nil) {
        switch option {
        case .ExecuteAsynchronously:
            self.asyncRequest(requestCalls, completion: completion)
        case .ExecuteSynchronously(let ignoreFailures):
            self.syncRequest(requestCalls, ignoreFailures: ignoreFailures, completion: completion)
        }
    }
    
    private func executeRequest(aRequest : Alamofire.Request?, withRequest request: TSKit.Request, type : AnyResponse.Type, completion: AnyResponseResultCompletion) {
        guard let aRequest = aRequest else {
            print("\(self.dynamicType): Failed to execute request: \(request)")
            completion(.Failure(error: .InvalidRequest))
            return
        }
        print("\(self.dynamicType): Executing request: \(request)")
        self.appendResponse(aRequest, request: request, type: type, completion: completion)
    }
    
    public required init(configuration: RequestManagerConfiguration) {
        let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
        sessionConfiguration.timeoutIntervalForRequest = Double(configuration.timeout)
        self.manager = Alamofire.Manager(configuration: sessionConfiguration)
        self.baseUrl = configuration.baseUrl
        self.defaultHeaders = configuration.headers
    }
    
    private var isReady : Bool {
        return self.baseUrl != nil
    }
    
    
    
}

// MARK: - Multiple requests.
private extension AlamofireRequestManager {
    func syncRequest(requestCalls : [AnyRequestCall], ignoreFailures : Bool, lastResult : TSKit.Result? = nil, completion : ((TSKit.Result) -> Void)?) {
        var calls = requestCalls
        guard let call = calls.first else {
            guard let result = lastResult else {
                completion?(.Failure(error: .InvalidRequest))
                return
            }
            completion?(result)
            return
        }
        self.request(call) { result in
            if ignoreFailures {
                calls.removeFirst()
                self.syncRequest(calls, ignoreFailures: ignoreFailures, lastResult: nil, completion: completion)
                
            } else if case .Success = result {
                calls.removeFirst()
                self.syncRequest(calls, ignoreFailures: ignoreFailures, lastResult: .Success, completion: completion)
            } else if case .Failure(let error) = result{
                completion?(.Failure(error: error))
            }
        }
    }
    
    func asyncRequest(requestCalls : [AnyRequestCall], completion : ((TSKit.Result) -> Void)?) {
        let group = dispatch_group_create()
        var response : TSKit.Result? = nil
        requestCalls.forEach {
            dispatch_group_enter(group)
            self.request($0) { res in
                switch res {
                case .Success: response = .Success
                case .Failure(let error): response = .Failure(error: error)
                }
                dispatch_group_leave(group)
            }
        }
        dispatch_group_notify(group, dispatch_get_main_queue()) {
            if let response = response {
                completion?(response)
            } else {
                completion?(.Failure(error: .FailedRequest))
            }
        }
    }
}

// MARK: - Constructing request properties.
private extension AlamofireRequestManager {
    
    func constructUrl(withRequest request: TSKit.Request) -> String? {
        guard let baseUrl = (request.baseUrl ?? self.baseUrl) else {
            print("\(self.dynamicType): Neither default baseUrl nor request's baseUrl had been specified.")
            return nil
        }
        return "\(baseUrl)/\(request.url)"
    }
    
    func constructHeaders(withRequest request : TSKit.Request) -> [String : String]? {
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
    func createRegularRequest(request : TSKit.Request, responseType type: AnyResponse.Type, completion : AnyResponseResultCompletion) -> Alamofire.Request? {
        guard let url = self.constructUrl(withRequest: request) else {
            completion(.Failure(error:.InvalidRequest))
            return nil
        }
        let method = Method(method: request.method)
        let encoding = Alamofire.ParameterEncoding(encoding: request.encoding)
        let headers = self.constructHeaders(withRequest: request)
        return self.manager.request(method, url, parameters: request.parameters, encoding: encoding, headers: headers)
    }
}

// MARK: - Constructing multipart Alamofire request.
private extension AlamofireRequestManager {
    
    func createMultipartRequest(request : MultipartRequest, responseType type: AnyResponse.Type, completion : AnyResponseResultCompletion, creationCompletion : (createdRequest : Alamofire.Request) -> Void) {
        guard var url = self.constructUrl(withRequest: request) else {
            completion(.Failure(error:.InvalidRequest))
            return
        }
        let method = Method(method: request.method)
        let headers = self.constructHeaders(withRequest: request)
        var urlParams : [String : AnyObject]?
        var dataParams : [String : AnyObject]? = request.parameters // by default all parameters are dataParams
        if let params = request.parameters {
            urlParams = params.filter {
                if let customEncoding = request.parametersEncodings?[$0.0] where customEncoding == RequestEncoding.URL {
                    return true
                }
                return false
            }
            if let urlParams = urlParams {
                urlParams.forEach{
                    url = self.encodeURLParam($0.1, withName: $0.0, inURL: url)
                }
                dataParams = params.filter { name, _ in
                    return !urlParams.contains { name == $0.0 }
                }
            }            
            print("\(self.dynamicType): Encoded params into url: \(url)\n")
        }
        print("\(self.dynamicType): Encoding data for multipart...")
        self.manager.upload(method, url, headers: headers, multipartFormData: { formData in
            if let files = request.files where !files.isEmpty {
                print("\(self.dynamicType): Appending \(files.count) in-memory files...\n")
                files.forEach {
                    print("\(self.dynamicType): Appending file \($0)...\n")
                    
                    formData.appendBodyPart(data: $0.value, name: $0.name, fileName: $0.fileName, mimeType: $0.mimeType)
                }
                
            }
            if let files = request.filePaths where !files.isEmpty {
                print("\(self.dynamicType): Appending \(files.count) files from storage...\n")
                files.forEach{
                    print("\(self.dynamicType): Appending file \($0)...\n")
                    formData.appendBodyPart(fileURL: $0.value, name: $0.name)
                }
                
            }
            
            if let dataParams = dataParams {
                dataParams.forEach {
                    print("\(self.dynamicType): Encoding parameter '\($0.0)'...")
                    self.appendParam($0.1, withName: $0.0, toFormData: formData, usingEncoding: request.parametersEncoding)
                }
            }
            }
            , encodingCompletion: { encodingResult in
                switch encodingResult {
                case let .Success(aRequest, _, _):
                    creationCompletion(createdRequest: aRequest)
                case .Failure(let error):
                    print("\(self.dynamicType): Failed to encode data with error: \(error).")
                    completion(.Failure(error: RequestError.InvalidRequest))
                }
        })
        
    }
    
    func createParameterComponent(param : AnyObject, withName name : String) -> [(String, String)] {
        var comps = [(String, String)]()
        if let array = param as? [AnyObject] {
            array.forEach {
                comps += self.createParameterComponent($0, withName: "\(name)[]")
            }
        } else if let dictionary = param as? [String : AnyObject] {
            dictionary.forEach { key, value in
                comps += self.createParameterComponent(value, withName: "\(name)[\(key)]")
            }
        } else {
            comps.append((name, "\(param)"))
        }
        return comps
    }
    
    
    func encodeURLParam(param : AnyObject, withName name : String, inURL url: String) -> String {
        let comps = self.createParameterComponent(param, withName: name).map {"\($0)=\($1)"}
        return "\(url)?\(comps.joinWithSeparator("&"))"
    }
    
    /// Appends param to the form data.
    func appendParam(param : AnyObject, withName name : String, toFormData formData : MultipartFormData, usingEncoding encoding: UInt) {
        let comps = self.createParameterComponent(param, withName: name)
        comps.forEach {
            guard let data = $0.1.dataUsingEncoding(encoding) else {
                print("\(self.dynamicType): Failed to encode parameter '\($0.0)'")
                return
            }
            formData.appendBodyPart(data: data, name: $0.0)
        }
    }
}

// MARK: - Constructing Alamofire response.
private extension AlamofireRequestManager {
    
    func appendResponse(aRequest : Alamofire.Request, request : TSKit.Request, type : AnyResponse.Type, completion: AnyResponseResultCompletion) -> Alamofire.Request {
        switch type.kind {
        case .JSON: return aRequest.responseJSON { res in
            if let error = res.result.error {
                print("\(self.dynamicType): Internal error while sending request:\n\(error)")
                completion(.Failure(error:.NetworkError))
            } else if let json = res.result.value {
                print("\(self.dynamicType): Received JSON:\n\(json).")
                if let response = type.init(request: request, body: json) {
                    completion(ResponseResult.Success(response: response))
                }
                else {
                    print("\(self.dynamicType): Specified response type couldn't handle '\(type.kind)'. Response '\(type)' has '\(type.kind)'.")
                    completion(.Failure(error:.InvalidResponseKind))
                }
            } else {
                print("\(self.dynamicType): Couldn't get any response.")
                completion(.Failure(error: .FailedRequest))
            }
            }
        case .Data: return aRequest.responseData {res in
            if let error = res.result.error {
                print("\(self.dynamicType): Internal error while sending request:\n\(error)")
                completion(.Failure(error:.NetworkError))
            } else if let data = res.result.value {
                print("\(self.dynamicType): Received \(data.dataSize) of data.")
                if let response = type.init(request: request, body: data) {
                    completion(ResponseResult.Success(response: response))
                }
                else {
                    print("\(self.dynamicType): Specified response type couldn't handle '\(type.kind)' response '\(type)' has '\(type.kind)'.")
                    completion(.Failure(error:.InvalidResponseKind))
                }
            } else {
                print("\(self.dynamicType): Couldn't get any response.")
                completion(.Failure(error: .FailedRequest))
            }
            }
        case .String: return aRequest.responseString {res in
            if let error = res.result.error {
                print("\(self.dynamicType): Internal error while sending request:\n\(error)")
                completion(.Failure(error:.NetworkError))
            } else if let string = res.result.value {
                print("\(self.dynamicType): Received string : \(string).")
                if let response = type.init(request: request, body: string) {
                    completion(ResponseResult.Success(response: response))
                }
                else {
                   print("\(self.dynamicType): Specified response type couldn't handle '\(type.kind)' response '\(type)' has '\(type.kind)'.")
                    completion(.Failure(error:.InvalidResponseKind))
                }
            } else {
                print("\(self.dynamicType): Couldn't get any response.")
                completion(.Failure(error: .FailedRequest))
            }
            }
        }
    }
}

// MARK: - Mapping abstract enums to Alamofire enums.

private extension Alamofire.Method {
    init(method : RequestMethod) {
        switch method {
        case .GET: self = .GET
        case .POST: self = .POST
        case .PATCH: self = .PATCH
        case .DELETE: self = .DELETE
        case .PUT: self = .PUT
        }
    }
}

private extension Alamofire.ParameterEncoding {
    init(encoding : RequestEncoding) {
        switch encoding {
        case .JSON: self = .JSON
        case .URL: self = .URL
        case .FormData: self = .URL
        }
    }
}