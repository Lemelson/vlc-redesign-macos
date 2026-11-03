// Ed25519 keys and signatures in Sparkle's format, with Apple's CryptoKit only (no download).
//
// Sparkle 2 reads `SUPublicEDKey` as the base64 of the 32-byte public key and `sparkle:edSignature`
// as the base64 of the 64-byte signature of the whole archive. The private key file holds the
// base64 of the 32-byte seed, the format of Sparkle's `generate_keys -x` and `sign_update -f`.
//
//   generate-key <private-key-file>        writes a new key (mode 600, refuses to overwrite),
//                                         prints the public key
//   public-key <private-key-file>          prints the public key
//   sign <private-key-file> <file>         prints the signature of <file>
//   verify <public-key> <file> <signature> exit 0 when the signature is valid
//
// Nothing secret is ever printed.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func readPrivateKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read the private key file") }
    guard let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), seed.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
        fail("the private key file is not a base64 Ed25519 seed (32 bytes)")
    }
    return key
}

func readFile(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    return data
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("generate-key", 2):
    let path = arguments[1]
    guard !FileManager.default.fileExists(atPath: path) else { fail("refusing to overwrite an existing key: \(path)") }
    let key = Curve25519.Signing.PrivateKey()
    let created = FileManager.default.createFile(atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                                 attributes: [.posixPermissions: 0o600])
    guard created else { fail("cannot write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case ("public-key", 2):
    print(readPrivateKey(arguments[1]).publicKey.rawRepresentation.base64EncodedString())
case ("sign", 3):
    let key = readPrivateKey(arguments[1])
    guard let signature = try? key.signature(for: readFile(arguments[2])) else { fail("signing failed") }
    print(signature.base64EncodedString())
case ("verify", 4):
    guard let raw = Data(base64Encoded: arguments[1]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
        fail("the public key is not a base64 Ed25519 key (32 bytes)")
    }
    guard let signature = Data(base64Encoded: arguments[3]), signature.count == 64 else { fail("the signature is not 64 bytes of base64") }
    guard key.isValidSignature(signature, for: readFile(arguments[2])) else { fail("INVALID signature") }
    print("valid")
default:
    fail("usage: sparkle-ed25519 generate-key KEY | public-key KEY | sign KEY FILE | verify PUBLIC FILE SIGNATURE")
}
