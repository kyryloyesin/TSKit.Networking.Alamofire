import Quick
import Nimble
import TSKit_Networking
@testable import TSKit_Networking_Alamofire

class AlamofireNetworkServiceSepc: QuickSpec {
    
    override func spec() {
        let failingRequest = SimpleRequest(shouldFail: true)
        let successfulRequest = SimpleRequest(shouldFail: false)
        
        expect(failingRequest).to(beAKindOf(SimpleRequest.self))
        describe("Foreground alamofire network service") {
            let service = AlamofireNetworkService(configuration: ForegroundConfiguration())
            var call: AnyRequestCall!
            
            it("Receives response") {
                waitUntil(timeout: 10) { done in
                    call = service.builder(for: successfulRequest)
                        .response(SuccessResponse.self) { res in
                            if case .success = res {
                                expect(true).to(beTrue())
                            } else {
                                fail("Unexpected failure")
                            }
                            done()
                        }
                       .make()!
                    service.request(call)
                }
            }
            
            context("When receiving successful response") {
                it("Should receive SuccessResponse") {
                    waitUntil(timeout: 10) { done in
                        call = service.builder(for: successfulRequest)
                            .response(SuccessResponse.self, forStatuses: 200) { res in
                                if case .success(let response) = res {
                                    expect(response.response.statusCode).to(be(200))
                                } else {
                                    fail("Unexpected failure")
                                }
                                
                                done()
                            }
                            .response(FailingResponse.self, forStatuses: 404) { res in
                                if case .success(let response) = res {
                                    expect(response.response.statusCode).to(be(404))
                                } else {
                                    fail("Unexpected failure")
                                }
                                done()
                            }.make()!
                        service.request(call)
                    }
                    
                    
                }
            }
            
            context("When receiving failing response") {
                it("Should receive FailingResponse") {
                    waitUntil(timeout: 10) { done in
                        call = service.builder(for: failingRequest)
                            .response(SuccessResponse.self, forStatuses: 200) { res in
                                if case .success(let response) = res {
                                    expect(response.response.statusCode).to(be(200))
                                } else {
                                    fail("Unexpected failure")
                                }
                                
                                done()
                            }
                            .response(FailingResponse.self, forStatuses: 404) { res in
                                if case .success(let response) = res {
                                    expect(response.response.statusCode).to(be(404))
                                } else {
                                    fail("Unexpected failure")
                                }
                                done()
                            }.make()!
                        service.request(call)
                    }
                }
            }
            
            
            
        }
    }
}

private struct SimpleRequest: AnyRequest {
    
    let method = RequestMethod.get
    
    let path: String
    
    init(shouldFail: Bool) {
        path = shouldFail ? "api/users/23" : "api/users/2"
    }
    
}

private struct FailingResponse: BaseResponse {
    
    static let kind = ResponseKind.json
    
    let request: AnyRequest
    
    let response: HTTPURLResponse
    
    init?(request: AnyRequest, response: HTTPURLResponse, body: Any?) {
        self.request = request
        self.response = response
    }
    
}

private struct SuccessResponse: BaseResponse {
    
    static let kind = ResponseKind.json
    
    let request: AnyRequest
    
    let response: HTTPURLResponse
    
    init?(request: AnyRequest, response: HTTPURLResponse, body: Any?) {
        self.request = request
        self.response = response
    }
    
}

private struct ForegroundConfiguration: AnyNetworkServiceConfiguration {
    
    let host = "https://reqres.in"
}
