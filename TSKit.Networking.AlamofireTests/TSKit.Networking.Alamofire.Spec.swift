import Quick
import Nimble
import TSKit_Networking
import TSKit_Core

@testable import TSKit_Networking_Alamofire

class AlamofireNetworkServiceSpec: QuickSpec {
    
    private func makeCall<T>(for request: T.Type, handler: @escaping () -> Void) -> AnyRequestCall where T: AnyMockedRequestable {
        return service.builder(for: request.init())
                      .dispatch(to: .global())
                      .response(SuccessResponse.self) { _ in handler() }
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
                
                    var isSuccess: Bool?
                    var receivedStatus: Int?
                    
                    beforeEach {
                        isSuccess = nil
                        receivedStatus = nil
                    }
                  
                    context("and receiving successful response") {
                        it("should handle it with only SuccessResponse") {
                            self.service.request(self.makeStatusCall(for: SuccessRequest.self) {
                                isSuccess = $0
                                receivedStatus = $1
                            })
                            expect(isSuccess).toEventually(beTrue(), timeout: criticalTimeout)
                            expect(receivedStatus).toEventually(equal(200), timeout: criticalTimeout)
                        }
                    }
                    
                    context("and receiving failing response") {
                        it("should handle it with only FailingResponse") {
                            self.service.request(self.makeStatusCall(for: FailingRequest.self) {
                                isSuccess = $0
                                receivedStatus = $1
                            })
                            expect(isSuccess).toEventually(beFalse(), timeout: criticalTimeout)
                            expect(receivedStatus).toEventually(equal(404), timeout: criticalTimeout)
                        }
                    }
                }
            }
            
            describe("synchronous processing") {
                let testingQueue = DispatchQueue(label: "Testing")
                var steps: [String] = []
                let expectedLabels = ["Step 1", "Step 2", "Finish"]
                var calls: [AnyRequestCall]!
                
                beforeEach {
                    calls = (0..<2).map { index in
                        self.makeCall(for: SuccessRequest.self) {
                            testingQueue.sync { steps.append("\(expectedLabels[index])") }
                        }
                    }
                }
                
                it("Should be executed in strict order") {
                    self.service.request(calls, option: .executeSynchronously(ignoreFailures: true)) { _ in
                        testingQueue.sync { steps.append(expectedLabels[2]) }
                    }
                    expect(steps).toEventually(equal(expectedLabels), timeout: criticalTimeout)
                }
            }
            
            describe("asynchronous processing") {
                let testingQueue = DispatchQueue(label: "Testing")
                var steps: [String] = []
                let expectedLabels = ["Step 1", "Step 2", "Finish"]
                var calls: [AnyRequestCall]!
                
                beforeEach {
                    calls = (0..<2).map { index in
                        self.makeCall(for: SuccessRequest.self) {
                            testingQueue.sync { steps.append("\(expectedLabels[index])") }
                        }
                    }
                }
                
                context("when ignoring failures") {
                    it("should eventually be completed regardless failed requets") {
                        self.service.request(calls, option: .executeAsynchronously(ignoreFailures: true)) { _ in
                            testingQueue.sync { steps.append(expectedLabels[2]) }
                        }
                        expect(Set(steps)).toEventually(equal(Set(expectedLabels)), timeout: criticalTimeout)
                    }
                }
                
                context("when ") {
                    
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
}
