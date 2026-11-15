import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - FEShortsClientRegressionTests
//
// Regression tests for task #96: a device-code OAuth token is bound to TVHTML5.
// Sending it with a WEB client body makes YouTube return HTTP 400, so any WEB
// request must stay unauthenticated; continuation tokens must be replayed with
// the client that issued them.
//
// History: fetchShorts used to fetch the FEshorts browse with the TVHTML5 client.
// YouTube deprecated FEshorts, so it now searches "#shorts" through the
// unauthenticated WEB path. The first test below covers that current shape (WEB
// body, no Authorization header); the second still covers the TV continuation path.
//
// These tests intercept the outgoing URLRequest via URLProtocol and inspect the
// captured JSON body and Authorization header.

// MARK: - URLProtocol helper

/// Intercepts the first outgoing POST request and captures its JSON body.
/// Returns HTTP 400 so the caller's network path fails fast.
private final class BodyCapturingURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var capturedBody: Data?
    nonisolated(unsafe) static var capturedAuthorizationHeader: String?

    override class func canInit(with request: URLRequest) -> Bool {
        request.httpMethod == "POST"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession converts httpBody to httpBodyStream before handing the request
        // to URLProtocol; httpBody is always nil here.
        // Only capture the FIRST request — legacy fetchShortsMore tokens retry
        // across several clients, and the first request already establishes the
        // shape each test guards.
        if BodyCapturingURLProtocol.capturedAuthorizationHeader == nil {
            BodyCapturingURLProtocol.capturedAuthorizationHeader =
                request.value(forHTTPHeaderField: "Authorization")
        }
        if BodyCapturingURLProtocol.capturedBody == nil {
            if let stream = request.httpBodyStream {
                stream.open()
                var body = Data()
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer {
                    buffer.deallocate()
                    stream.close()
                }
                // Use read-until-zero rather than hasBytesAvailable; the latter
                // can return false prematurely for in-memory streams.
                while true {
                    let count = stream.read(buffer, maxLength: bufferSize)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
                BodyCapturingURLProtocol.capturedBody = body
            } else if let bodyData = request.httpBody {
                // Fallback: some configurations pass the body directly in httpBody.
                BodyCapturingURLProtocol.capturedBody = bodyData
            }
        }

        // Reply with a minimal HTTP 400 response so the API call fails fast.
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

@Suite("Shorts clients — Regression #96", .serialized)
struct FEShortsClientRegressionTests {

    // MARK: - Helpers

    /// Returns an `InnerTubeAPI` wired to `BodyCapturingURLProtocol` via an ephemeral
    /// `URLSession`. This avoids polluting the global URLProtocol registry.
    private func makeTestAPI(authToken: String) -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BodyCapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        return InnerTubeAPI(authToken: authToken, session: session)
    }

    // MARK: - fetchShorts

    /// Verifies the current fetchShorts shape: an unauthenticated "#shorts" search
    /// through the WEB client. Sending the TV device-code Bearer token with a WEB
    /// body is what made authenticated Shorts return HTTP 400 in the #96 regression.
    @Test("fetchShorts sends an unauthenticated WEB search request")
    func fetchShortsSendsUnauthenticatedWebSearch() async throws {
        BodyCapturingURLProtocol.capturedBody = nil
        BodyCapturingURLProtocol.capturedAuthorizationHeader = nil
        let api = makeTestAPI(authToken: "fake-tv-oauth-token")

        // The call will throw (HTTP 400 from BodyCapturingURLProtocol), which is expected.
        _ = try? await api.fetchShorts()

        let bodyData = try #require(
            BodyCapturingURLProtocol.capturedBody,
            "URLProtocol should have captured the POST body"
        )
        let json = try #require(
            try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            "Request body must be valid JSON"
        )

        let context = json["context"] as? [String: Any]
        let clientDict = context?["client"] as? [String: Any]

        #expect(clientDict?["clientName"] as? String == "WEB")
        #expect(json["query"] as? String == "#shorts")
        #expect(
            BodyCapturingURLProtocol.capturedAuthorizationHeader == nil,
            """
            fetchShorts must not send the device-code OAuth token with a WEB client body.
            Sending it returns HTTP 400 (regression #96).
            Found Authorization=\(String(describing: BodyCapturingURLProtocol.capturedAuthorizationHeader))
            """
        )
    }

    // MARK: - fetchShortsMore

    /// Verifies that fetchShortsMore sends `clientName: "TVHTML5"`.
    ///
    /// Continuation tokens are client-scoped: a token from a TVHTML5 FEshorts
    /// response must be submitted with TVHTML5 context to work correctly.
    @Test("fetchShortsMore sends TVHTML5 clientName")
    func fetchShortsMoreSendsTVClient() async throws {
        BodyCapturingURLProtocol.capturedBody = nil
        let api = makeTestAPI(authToken: "fake-tv-oauth-token")

        _ = try? await api.fetchShortsMore(continuationToken: "test-continuation-token-12345")

        let bodyData = try #require(
            BodyCapturingURLProtocol.capturedBody,
            "URLProtocol should have captured the POST body"
        )
        let json = try #require(
            try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            "Request body must be valid JSON"
        )

        let context = json["context"] as? [String: Any]
        let clientDict = context?["client"] as? [String: Any]

        #expect(
            clientDict?["clientName"] as? String == "TVHTML5",
            """
            fetchShortsMore must use TVHTML5 client.
            Found clientName=\(String(describing: clientDict?["clientName"]))
            """
        )
        #expect(
            json["continuation"] as? String == "test-continuation-token-12345",
            "fetchShortsMore must forward the continuation token in the body"
        )
    }
}
