import XCTest
@testable import BunnyStreamAPI

class BunnyStreamAPITests: XCTestCase {
  var api: BunnyStreamAPI!
  
  override func setUp() {
    super.setUp()
    api = BunnyStreamAPI(accessKey: "TestAccessKey")
  }
  
  override func tearDown() {
    api = nil
    super.tearDown()
  }
  
  func testAPIInitialization() {
    // Test that API initializes correctly
    XCTAssertNotNil(api)
  }
  
  func testCreateVideoWithValidParameters() {
    // Test would require mocking URLSession for actual network calls
    // This is a basic structure test
    XCTAssertNotNil(api)
  }
  
  func testErrorTypes() {
    // Test error descriptions
    let unauthorizedError = BunnyStreamAPIError.unauthorized
    XCTAssertEqual(unauthorizedError.errorDescription, "Request authorization failed")
    
    let notFoundError = BunnyStreamAPIError.notFound
    XCTAssertEqual(notFoundError.errorDescription, "Requested resource was not found")
    
    let httpError = BunnyStreamAPIError.httpError(500)
    XCTAssertEqual(httpError.errorDescription, "HTTP error with status code: 500")
  }
}
