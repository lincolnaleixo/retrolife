// Test-only ephemeral signing seed. Never touches a user's Keychain.
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let path = CommandLine.arguments[1]
try key.rawRepresentation.base64EncodedString().write(toFile: path, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
print(key.publicKey.rawRepresentation.base64EncodedString())
