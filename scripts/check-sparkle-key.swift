import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("Sparkle key check failed: \(message)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: check-sparkle-key.swift APP_PATH")
}

let plistURL = URL(fileURLWithPath: CommandLine.arguments[1])
    .appendingPathComponent("Contents/Info.plist")
guard let plistData = try? Data(contentsOf: plistURL),
      let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        as? [String: Any],
      let publicKeyString = plist["SUPublicEDKey"] as? String,
      let publicKey = Data(base64Encoded: publicKeyString),
      publicKey.count == 32 else {
    fail("app is missing a valid SUPublicEDKey")
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let encodedSeed = String(data: input, encoding: .utf8),
      let seed = Data(base64Encoded: encodedSeed.trimmingCharacters(in: .whitespacesAndNewlines)),
      seed.count == 32,
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    fail("SPARKLE_ED_PRIVATE_KEY must be a Sparkle Ed25519 seed")
}

guard privateKey.publicKey.rawRepresentation == publicKey else {
    fail("SPARKLE_ED_PRIVATE_KEY does not match the app's SUPublicEDKey")
}
