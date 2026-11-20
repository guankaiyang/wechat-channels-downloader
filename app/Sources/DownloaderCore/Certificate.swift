import Foundation

private let securityPath = "/usr/bin/security"

/// True when macOS trusts the downloader's own CA certificate.
public func isCertificateTrusted(_ cert: URL, runner: CommandRunner) -> Bool {
    runner.run(securityPath, ["verify-cert", "-c", cert.path, "-p", "basic", "-l", "-L", "-q"]).status == 0
}

/// Trusts the CA for this user only (login keychain). macOS shows its own password dialog.
public func trustCertificate(_ cert: URL, runner: CommandRunner, home: URL) -> Bool {
    let keychain = home.appendingPathComponent("Library/Keychains/login.keychain-db").path
    return runner.run(securityPath, ["add-trusted-cert", "-r", "trustRoot", "-k", keychain, cert.path]).status == 0
}
