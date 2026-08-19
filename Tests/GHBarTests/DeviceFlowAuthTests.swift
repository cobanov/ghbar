import Testing
import Foundation
@testable import GHBar

/// Senaryolu tasiyici: her cagri sirayla bir cevap doner. Aga hic cikilmaz.
private actor Script {
    private var responses: [(String, Int)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(String, Int)]) { self.responses = responses }
    func next(_ request: URLRequest) -> (Data, Int) {
        requests.append(request)
        let (body, status) = responses.removeFirst()
        return (Data(body.utf8), status)
    }
}

private func auth(_ script: Script) -> DeviceFlowAuth {
    var flow = DeviceFlowAuth()
    flow.transport = { request in await script.next(request) }
    flow.pollFloor = 0   // testte bekleme yok
    return flow
}

@Suite("DeviceFlowAuth")
struct DeviceFlowAuthTests {

    @Test("kod istegi cozumlenir ve kapsam dogru gider") func requestCode() async throws {
        let script = Script([
            (#"{"device_code":"dev1","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","interval":0}"#, 200),
        ])
        let grant = try await auth(script).requestCode(includePrivate: true)
        #expect(grant.userCode == "ABCD-1234")
        #expect(grant.deviceCode == "dev1")

        let request = await script.requests[0]
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("client_id=Ov23lid00njVuTIgpnyF"))
        #expect(body.contains("scope=repo"))
    }

    @Test("yalniz herkese acik kapsami public_repo") func publicScope() async throws {
        let script = Script([
            (#"{"device_code":"d","user_code":"U","verification_uri":"v","interval":0}"#, 200),
        ])
        _ = try await auth(script).requestCode(includePrivate: false)
        let request = await script.requests[0]
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("public_repo"))
    }

    @Test("pending'ten sonra token gelir") func pollsUntilToken() async throws {
        let script = Script([
            (#"{"error":"authorization_pending"}"#, 200),
            (#"{"error":"authorization_pending"}"#, 200),
            (#"{"access_token":"gho_zzz","token_type":"bearer"}"#, 200),
        ])
        let grant = DeviceCodeGrant(deviceCode: "d", userCode: "U", verificationURI: "v", interval: 0)
        #expect(try await auth(script).waitForToken(grant) == "gho_zzz")
    }

    @Test("access_denied denied hatasina cevrilir") func denied() async throws {
        let script = Script([(#"{"error":"access_denied"}"#, 200)])
        let grant = DeviceCodeGrant(deviceCode: "d", userCode: "U", verificationURI: "v", interval: 0)
        await #expect(throws: DeviceFlowError.denied) {
            _ = try await auth(script).waitForToken(grant)
        }
    }

    @Test("expired_token expired hatasina cevrilir") func expired() async throws {
        let script = Script([(#"{"error":"expired_token"}"#, 200)])
        let grant = DeviceCodeGrant(deviceCode: "d", userCode: "U", verificationURI: "v", interval: 0)
        await #expect(throws: DeviceFlowError.expired) {
            _ = try await auth(script).waitForToken(grant)
        }
    }

    @Test("HTTP hatasi network hatasi olur") func httpError() async {
        let script = Script([("oops", 500)])
        await #expect(throws: DeviceFlowError.network("HTTP 500")) {
            _ = try await auth(script).requestCode(includePrivate: true)
        }
    }
}
