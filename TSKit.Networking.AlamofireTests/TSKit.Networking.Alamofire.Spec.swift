import Quick
import Nimble
import TSKit_Networking
import TSKit_Core
import TSKit_Injection
import TSKit_Log

@testable import TSKit_Networking_Alamofire

class AlamofireNetworkServiceSpec: QuickSpec {
    
    private func makeCall(for request: AnyMockedRequestable.Type, handler: @escaping () -> Void) -> AnyRequestCall {
        let request = request.init()
        return service.builder(for: request)
                      .dispatch(to: .global())
                      .response(SuccessResponse.self) {
                        switch $0 {
                        case .success(let response): print(response)
                        case .failure(let error): print(error)
                        }
                        handler()
                        
            }
                      .make()!
    }
    
    private func makeStatusCall<T>(for request: T.Type, result: @escaping (Bool, Int?) -> Void) -> AnyRequestCall where T: AnyMockedRequestable {
        return service.builder(for: request.init())
            .dispatch(to: .global())
            .response(SuccessResponse.self, forStatuses: 200) { res in
                if case .success(let response) = res {
                    result(true, response.response.statusCode)
                } else {
                    result(true, nil)
                }
            }
            .response(FailingResponse.self, forStatuses: 404) { res in
                if case .success(let response) = res {
                    result(false, response.response.statusCode)
                } else {
                    result(false, nil)
                }
            }.make()!
    }
    
    private var service: AlamofireNetworkService!
    
    override func spec() {
        let criticalTimeout: TimeInterval = 5
        describe("Foreground alamofire network service") {
            beforeEach {
                Injector.configure(with: [ InjectionRule(injectable: AnyLogger.self, once: true) {
                    let logger = Logger()
                    logger.addWriter(PrintLogEntryWriter())
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
                            expect(isSuccess).toEventually(equal([false]), timeout: criticalTimeout)
                            expect(receivedStatuses).toEventually(equal([404]), timeout: criticalTimeout)
                        }
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
                
                describe("synchronously") {
                    context("and ignores failures") {
                        let expectedLabels = requestLabels.appending(completionLabel)
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
    init()
}

private struct SuccessRequest: AnyMockedRequestable {
    
    let method = RequestMethod.get
    
    let path: String = ""
}

private struct FailingRequest: AnyMockedRequestable {
  
    let method = RequestMethod.get
    
    let path: String = "not_existed"
}

private struct FailingResponse: AnyResponse {
    
    static let kind = ResponseKind.string
    
    let response: HTTPURLResponse
    
    init?(response: HTTPURLResponse, body: Any?) {
        self.response = response
    }
    
}

private struct SuccessResponse: AnyResponse {
    
    static let kind = ResponseKind.string
    
    let response: HTTPURLResponse
    
    init?(response: HTTPURLResponse, body: Any?) {
        self.response = response
    }
    
}

private struct ForegroundConfiguration: AnyNetworkServiceConfiguration {
    
    let host = "https://google.com"
    
    let sessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        return configuration
    }()
}
