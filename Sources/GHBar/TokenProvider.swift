import Foundation

enum TokenProvider {

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

    static func token() throws -> String {
        guard let executable = locate() else { throw AppError.ghNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "token"]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw AppError.ghNotFound
        }

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
