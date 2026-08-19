import Foundation

struct DeviceCodeGrant: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let interval: Int
}

enum DeviceFlowError: Error, Equatable {
    case denied
    case expired
    case network(String)
    case malformed(String)
}

/// GitHub OAuth device flow (spec §5). Klasik web akisinin istedigi
/// client_secret dagitilan bir uygulamada sir olamaz; device flow secret
/// istemez — tam bu durum icin tasarlandi. Kullanici ekrandaki kodu
/// github.com/login/device'ta onaylar, biz arka planda yoklariz.
struct DeviceFlowAuth: Sendable {

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    static let defaultClientID = "Ov23lid00njVuTIgpnyF"

    var clientID = DeviceFlowAuth.defaultClientID
    var transport: Transport = DeviceFlowAuth.live
    /// Yoklama araliginin tabani; testler 0'a indirir.
    var pollFloor: TimeInterval = 1

    func requestCode(includePrivate: Bool) async throws -> DeviceCodeGrant {
        // repo: ozel repolardaki PR/issue'lar; read:org: organizasyon repolari.
        let scope = includePrivate ? "repo read:org" : "public_repo read:org"
        let data = try await post("https://github.com/login/device/code",
                                  form: ["client_id": clientID, "scope": scope])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device_code"] as? String,
              let user = object["user_code"] as? String,
              let uri = object["verification_uri"] as? String else {
            throw DeviceFlowError.malformed("device/code")
        }
        return DeviceCodeGrant(
            deviceCode: device,
            userCode: user,
            verificationURI: uri,
            interval: object["interval"] as? Int ?? 5
        )
    }

    /// Kullanici tarayicida onaylayana kadar yoklar. GitHub'in soyledigi
    /// araliga uyar; slow_down gelirse 5 sn ekler (RFC 8628).
    func waitForToken(_ grant: DeviceCodeGrant) async throws -> String {
        var interval = max(pollFloor, TimeInterval(grant.interval))
        while true {
            try await Task.sleep(for: .seconds(interval))
            let data = try await post("https://github.com/login/oauth/access_token", form: [
                "client_id": clientID,
                "device_code": grant.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DeviceFlowError.malformed("access_token")
            }
            if let token = object["access_token"] as? String { return token }

            switch object["error"] as? String {
            case "authorization_pending": continue
            case "slow_down":             interval += 5
            case "expired_token":         throw DeviceFlowError.expired
            case "access_denied":         throw DeviceFlowError.denied
            case let other:               throw DeviceFlowError.malformed(other ?? "unknown")
            }
        }
    }

    // MARK: - Private

    private func post(_ address: String, form: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // RFC 3986 unreserved kumesi: alfanumerik + "-._~". .alphanumerics
        // tek basina alt cizgiyi bile yuzde-kodluyordu (public%5Frepo).
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, status) = try await transport(request)
            guard status == 200 else { throw DeviceFlowError.network("HTTP \(status)") }
            return data
        } catch let error as DeviceFlowError {
            throw error
        } catch {
            throw DeviceFlowError.network(error.localizedDescription)
        }
    }

    static let live: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
