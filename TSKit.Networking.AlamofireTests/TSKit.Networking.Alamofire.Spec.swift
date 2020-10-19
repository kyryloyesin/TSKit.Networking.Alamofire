import Quick
import Nimble
import TSKit_Networking
import TSKit_Core
import TSKit_Injection
import TSKit_Log
import Alamofire

@testable import TSKit_Networking_Alamofire


class InspectableService: AlamofireNetworkService {
    
    var retier: MockedRequestRetrier!
    
    override func makeRetrier(retryLimit: UInt,
                              retryableHTTPMethods: Set<HTTPMethod>,
                              retryableHTTPStatusCodes: Set<Int>,
                              retryableURLErrorCodes: Set<URLError.Code>) -> RequestInterceptor {
        retier = MockedRequestRetrier(retryLimit: retryLimit,
                                      retryableHTTPMethods: retryableHTTPMethods,
                                      retryableHTTPStatusCodes: retryableHTTPStatusCodes,
                                      retryableURLErrorCodes: retryableURLErrorCodes,
                                      log: try! Injector.inject())
        return retier
    }
}


class MockedRequestRetrier: LoggingRetryPolicy {
    
    var retriesCount: UInt = 0
    
    override func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        super.retry(request, for: session, dueTo: error, completion: { result in
            switch result {
                case .retry, .retryWithDelay: self.retriesCount += 1
                default: break
            }
            completion(result)
        })
    }
}

class AlamofireNetworkServiceSpec: QuickSpec {
    
    private func makeCall(for request: AnyMockedRequestable.Type, retries: UInt? = nil, handler: @escaping () -> Void) -> AnyRequestCall {
        let request = transform(request.init()) {
            $0.retryAttempts = retries
        }
        return service.builder(for: request)
                      .dispatch(to: .global())
                      .response(SuccessResponse.self) {
                        print($0)
                        handler()
                        
        }.error {
            print($0)
            handler()
        }
                      .make()!
    }
    
    private func makeStatusCall<T>(for request: T.Type, retries: UInt? = nil, result: @escaping (Bool, Int?) -> Void) -> AnyRequestCall where T: AnyMockedRequestable {
        return service.builder(for: transform(request.init()) {
            $0.retryAttempts = retries
        })
            .dispatch(to: .global())
            .response(SuccessResponse.self, forStatuses: 200) {
                result(true, $0.response.statusCode)
            }.response(FailingResponse.self, forStatuses: 404) {
                result(true, $0.response.statusCode)
            }.error { _ in
                result(false, nil)
            }.make()!
    }
    
    private var service: InspectableService!
    
    override func spec() {
        let criticalTimeout = DispatchTimeInterval.seconds(5)
        describe("Foreground alamofire network service") {
            beforeEach {
                Injector.configure(with: [ InjectionRule(injectable: AnyLogger.self, once: false) {
                    let logger = Logger()
                    logger.writers = [PrintLogEntryWriter()]
                    return logger
                }])
                self.service = .init(configuration: ForegroundConfiguration())
            }
        
            describe("when processing single request") {
                
                context("with single response handler") {
                    it("is able to handle successful response") {
                        waitUntil(timeout: criticalTimeout) { done in
                            self.makeCall(for: SuccessRequest.self, handler: done) ==> { self.service.request($0) }
                        }
                    }
                    
                    it("is able to handle failed response") {
                        waitUntil(timeout: criticalTimeout) { done in
                            self.makeCall(for: FailingRequest.self, handler: done) ==> { self.service.request($0) }
                        }
                    }
                }
                
                context("without response handler") {
                    it("is able to handle successful response through request completion") {
                        waitUntil(timeout: criticalTimeout) { done in
                            self.makeCall(for: SuccessRequest.self, handler: {}) ==> { self.service.request($0) { _ in done() } }
                        }
                    }
                    
                    it("is able to handle failed response through request completion") {
                        waitUntil(timeout: criticalTimeout) { done in
                            self.makeCall(for: FailingRequest.self, handler: {}) ==> { self.service.request($0) { _ in done() } }
                        }
                    }
                }
                
                context("with multiple status-based response handlers") {
                
                    /// Array of received responses
                    var isSuccess: [Bool] = []
                    /// Array of received statuses
                    var receivedStatuses: [Int] = []
                    
                    beforeEach {
                        isSuccess = []
                        receivedStatuses = []
                    }
                  
                    context("and receiving successful response") {
                        it("should handle it with only SuccessResponse") {
                            self.service.request(self.makeStatusCall(for: SuccessRequest.self) {
                                isSuccess.append($0)
                                if let status = $1 {
                                    receivedStatuses.append(status)
                                }
                            })
                            expect(isSuccess).toEventually(equal([true]), timeout: criticalTimeout)
                            expect(receivedStatuses).toEventually(equal([200]), timeout: criticalTimeout)
                        }
                    }
                    
                    context("and receiving failing response") {
                        it("should handle it with only FailingResponse") {
                            self.service.request(self.makeStatusCall(for: FailingRequest.self) {
                                isSuccess.append($0)
                                if let status = $1 {
                                    receivedStatuses.append(status)
                                }
                            })
                            expect(isSuccess).toEventually(equal([true]), timeout: criticalTimeout)
                            expect(receivedStatuses).toEventually(equal([404]), timeout: criticalTimeout)
                        }
                    }
                }
                
                context("and configured retry") {
                    let retries: UInt = 4
                    
                    fit("should try \(retries) times request") {
                        let call = self.makeCall(for: FailingRequest.self, retries: retries) { }
                        self.service.request(call)
                        expect(self.service.retier.retriesCount).toEventually(equal(retries), timeout: criticalTimeout)
                    }
                }
            }
            
            describe("when processing multiple requests") {
                let testingQueue = DispatchQueue(label: "Testing")
                let requests: [(String, AnyMockedRequestable.Type)] = [("Success 1", SuccessRequest.self),
                                                                    ("Fail 1", FailingRequest.self),
                                                                    ("Success 2", SuccessRequest.self),
                                                                    ("Fail 2", FailingRequest.self)]
                let requestLabels = requests.map { $0.0 }
                let failedLabel = "Failed"
                let completionLabel = "Completed"
                var calls: [AnyRequestCall]!
                var steps: [String] = []
                
                beforeEach {
                    steps = []
                    calls = requests.map { pair in
                        return self.makeCall(for: pair.1) {
                            testingQueue.sync { steps.append(pair.0) }
                        }
                    }
                }
                afterEach {
                    calls.removeAll()
                }
                
                describe("synchronously") {
                    context("and ignores failures") {
                        let expectedLabels = requests.map { $0.0 }.appending(completionLabel)
                        it("should be executed in strict order regardless failed reuqests and completed successfuly") {
                            self.service.request(calls, option: .executeSynchronously(ignoreFailures: true)) {
                                switch $0 {
                                case .success: testingQueue.sync { steps.append(completionLabel) }
                                case .failure: testingQueue.sync { steps.append(failedLabel) }
                                }
                            }
                            expect(steps).toEventually(equal(expectedLabels), timeout: criticalTimeout)
                        }
                    }
                    
                    context("and does not ignore failures") {
                        let expectedLabels = Array(requestLabels[0..<2]).appending(failedLabel)
                        it("should be executed in strict order and fail after first failed reuqest") {
                            self.service.request(calls, option: .executeSynchronously(ignoreFailures: false)) {
                                switch $0 {
                                case .success: testingQueue.sync { steps.append(completionLabel) }
                                case .failure: testingQueue.sync { steps.append(failedLabel) }
                                }
                            }
                            expect(steps).toEventually(equal(expectedLabels), timeout: criticalTimeout)
                        }
                    }
                }
                
                describe("asynchronously") {
                    context("and ignores failures") {
                        it("should be executed randomly and completed successfuly regardless failed reuqests") {
                            self.service.request(calls, option: .executeAsynchronously(ignoreFailures: true)) {
                                switch $0 {
                                case .success: testingQueue.sync { steps.append(completionLabel) }
                                case .failure: testingQueue.sync { steps.append(failedLabel) }
                                }
                            }
                            expect(steps).toEventually(contain(completionLabel), timeout: criticalTimeout)
                        }
                    }
                    
                    context("and does not ignore failures") {
                        it("should be executed randomly and fail after first failed reuqest") {
                            self.service.request(calls, option: .executeAsynchronously(ignoreFailures: false)) {
                                switch $0 {
                                case .success: testingQueue.sync { steps.append(completionLabel) }
                                case .failure: testingQueue.sync { steps.append(failedLabel) }
                                }
                            }
                            expect(steps).toEventually(contain(failedLabel), timeout: criticalTimeout)
                        }
                    }
                }
            }
        }
    }
}

private protocol AnyMockedRequestable: AnyRequestable {
    
    var retryAttempts: UInt? { get set }
    
    init()
}

private struct SuccessRequest: AnyMockedRequestable {
    
    let method = RequestMethod.get
    
    let path: String = ""
    
    var retryAttempts: UInt? = nil
}

private struct FailingRequest: AnyMockedRequestable {
  
    let method = RequestMethod.get
    
    let path: String = "not_existed"
        
    var retryAttempts: UInt? = nil
    
    let retriableStatuses: Set<Int>? = [404]
}

private struct FailingResponse: AnyResponse {
    
    static let kind = ResponseKind.string
    
    let response: HTTPURLResponse
    
    init(response: HTTPURLResponse, body: Any?) throws {
        self.response = response
    }
    
}

private struct SuccessResponse: AnyResponse {
    
    static let kind = ResponseKind.string
    
    let response: HTTPURLResponse
    
    init(response: HTTPURLResponse, body: Any?) throws {
        self.response = response
    }
    
}

private struct ForegroundConfiguration: AnyNetworkServiceConfiguration {
   
    
    var sessionTemporaryFilesDirectory: URL? { nil }
    
    let host = "https://google.com"
    
    let sessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        return configuration
    }()
}
