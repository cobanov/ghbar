import Foundation

enum TokenProvider {

    /// gh'nin token'i, varsa. Hangi kaynagin kullanilacagina `Auth.resolve` karar verir.
    ///
    /// MAS varyantinda gh adimi DERLEME DISI (#if MAS): sandbox alt surec
    /// calistiramaz, kacak bir cagri sessiz bozulma olurdu. #if MAS bunun
    /// disinda yalnizca guncelleme kontrolunu kapatir (UpdateChecker).
    static func ghTokenIfAvailable() -> String? {
        #if MAS
        return nil
        #else
        return try? ghToken()
        #endif
    }

    /// `.app` icinden baslatilan bir surec kabuk ortamini miras almaz — PATH
    /// neredeyse bostur. Bu yuzden tam yol denemesi sart; sadece PATH'e
    /// guvenmek cogu makinede sessizce basarisiz olur.
    static let knownPaths = [
        "/opt/homebrew/bin/gh",   // Apple Silicon
        "/usr/local/bin/gh",      // Intel
    ]

    static func locate(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        if let known = knownPaths.first(where: fileExists) { return known }

        guard let pathEnvironment else { return nil }
        for directory in pathEnvironment.split(separator: ":") {
            let candidate = "\(directory)/gh"
            if fileExists(candidate) { return candidate }
        }
        return nil
    }

    static func ghToken() throws -> String {
        guard let executable = locate() else { throw AppError.ghNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        // Only github.com: with no host, gh prints whichever host it has, which may be an
        // Enterprise server whose token must not go to api.github.com.
        process.arguments = ["auth", "token", "--hostname", "github.com"]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw AppError.ghNotFound
        }
        // gh can wait on a keychain prompt; do not let that hold a refresh forever.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        defer { watchdog.cancel() }

        // Boru dolup surecin kilitlenmemesi icin once oku, sonra bekle.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0, !token.isEmpty else {
            throw AppError.ghNotAuthenticated
        }
        return token
    }
}
