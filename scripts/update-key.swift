import Foundation
import CryptoKit

// Public keys go to stdout. The private seed is only written to a protected file.
let arguments = Array(CommandLine.arguments.dropFirst())
let seed: Data
if arguments.first == "create", arguments.count == 2 {
    let destination = URL(fileURLWithPath: arguments[1])
    umask(0o077)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if FileManager.default.fileExists(atPath: destination.path) {
        guard let decoded = Data(base64Encoded: try String(contentsOf: destination, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) else { fatalError("Invalid signing key file") }
        seed = decoded
    } else {
        seed = Curve25519.Signing.PrivateKey().rawRepresentation
        try seed.base64EncodedString().write(to: destination, atomically: true, encoding: .utf8)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
} else if arguments == ["public"] {
    let encoded = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let decoded = Data(base64Encoded: encoded) else { fatalError("Invalid signing key") }
    seed = decoded
} else {
    fatalError("Usage: update-key.swift create <protected-key-file> | public < private-key-file")
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(key.publicKey.rawRepresentation.base64EncodedString())
