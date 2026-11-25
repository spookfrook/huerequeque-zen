import Darwin
import Foundation

final class MacOSSystemBlocker: SystemBlocker {
    private let hostsPath: String
    private let pfConfPath: String
    private let pfAnchorPath: String
    private let anchorName: String
    private let pfTokenPath: String

    init(
        hostsPath: String = ZenConstants.hostsPath,
        pfConfPath: String = ZenConstants.pfConfPath,
        pfAnchorPath: String = ZenConstants.pfAnchorPath,
        anchorName: String = ZenConstants.anchorName,
        pfTokenPath: String = ZenConstants.supportDir + "/pf.token"
    ) {
        self.hostsPath = hostsPath
        self.pfConfPath = pfConfPath
        self.pfAnchorPath = pfAnchorPath
        self.anchorName = anchorName
        self.pfTokenPath = pfTokenPath
    }

    func apply(spec: EffectiveBlockingSpec, killExistingConnections: Bool) throws {
        // 1. Resolve IPs BEFORE writing /etc/hosts (otherwise /etc/hosts returns 0.0.0.0!)
        let resolvedBlockedIPs: [String]
        let resolvedAllowedIPs: [String]
        let hostsDomains: [String]

        switch spec {
        case .none:
            hostsDomains = []
            resolvedBlockedIPs = []
            resolvedAllowedIPs = []

        case .blocklist(let domains):
            hostsDomains = domains
            let hosts = DomainNormalizer.expandedHosts(for: domains)
            resolvedBlockedIPs = Self.resolveHosts(hosts)
            resolvedAllowedIPs = []

        case .allowlist(let allowedDomains, let extraBlockedDomains):
            hostsDomains = extraBlockedDomains
            let allowedHosts = DomainNormalizer.expandedHosts(for: allowedDomains)
            let extraBlockedHosts = DomainNormalizer.expandedHosts(for: extraBlockedDomains)
            resolvedAllowedIPs = Self.resolveHosts(allowedHosts)
            resolvedBlockedIPs = Self.resolveHosts(extraBlockedHosts)
        }

        // 2. Atomically update /etc/hosts
        try writeHostsFile(domains: hostsDomains)

        // 3. Configure & apply PF firewall rules
        try applyPF(
            spec: spec,
            blockedIPs: resolvedBlockedIPs,
            allowedIPs: resolvedAllowedIPs,
            killExistingConnections: killExistingConnections
        )

        // 4. Flush macOS DNS caches so browsers drop cached answers immediately
        flushDNSCache()
    }

    func verifyHostsIntegrity(for spec: EffectiveBlockingSpec) -> Bool {
        guard let current = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return false }
        let expectedDomains: [String]
        switch spec {
        case .none: expectedDomains = []
        case .blocklist(let domains): expectedDomains = domains
        case .allowlist(_, let extraBlocked): expectedDomains = extraBlocked
        }
        return HostsFileEditor.containsExactBlock(domains: expectedDomains, in: current)
    }

    // MARK: - /etc/hosts

    private func writeHostsFile(domains: [String]) throws {
        let existing = (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
        let updated = HostsFileEditor.apply(domains: domains, to: existing)
        guard updated != existing else { return }

        let url = URL(fileURLWithPath: hostsPath)
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".hosts.huerequeque.\(UUID().uuidString).tmp")
        try updated.write(to: tmp, atomically: true, encoding: .utf8)
        chmod(tmp.path, 0o644)
        chown(tmp.path, 0, 0)
        if rename(tmp.path, hostsPath) != 0 {
            let err = errno
            try? FileManager.default.removeItem(at: tmp)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "No se pudo actualizar /etc/hosts (\(err))."
            ])
        }
    }

    // MARK: - PF Firewall

    private func applyPF(
        spec: EffectiveBlockingSpec,
        blockedIPs: [String],
        allowedIPs: [String],
        killExistingConnections: Bool
    ) throws {
        if !spec.isBlockingAnything {
            // Clean up anchor and release PF token
            try? "".write(toFile: pfAnchorPath, atomically: true, encoding: .utf8)
            _ = run("/sbin/pfctl", ["-a", anchorName, "-F", "all"])
            releasePFToken()
            return
        }

        // Ensure /etc/pf.conf references our anchor
        if let pfConf = try? String(contentsOfFile: pfConfPath, encoding: .utf8) {
            let check = PFConfigGenerator.ensureAnchorReference(
                in: pfConf,
                anchorName: anchorName,
                anchorPath: pfAnchorPath
            )
            if check.changed {
                let tmp = URL(fileURLWithPath: pfConfPath).deletingLastPathComponent()
                    .appendingPathComponent(".pf.conf.huerequeque.\(UUID().uuidString).tmp")
                try check.content.write(to: tmp, atomically: true, encoding: .utf8)
                chmod(tmp.path, 0o644)
                chown(tmp.path, 0, 0)
                _ = rename(tmp.path, pfConfPath)
                _ = run("/sbin/pfctl", ["-f", pfConfPath])
            }
        }

        // Write anchor rules
        let rules = PFConfigGenerator.anchorRules(
            for: spec,
            resolvedBlockedIPs: blockedIPs,
            resolvedAllowedIPs: allowedIPs
        )
        try rules.write(toFile: pfAnchorPath, atomically: true, encoding: .utf8)
        chmod(pfAnchorPath, 0o644)

        // Ensure PF is enabled with a reference token
        ensurePFEnabled()

        // Load rules into our dedicated anchor
        _ = run("/sbin/pfctl", ["-a", anchorName, "-f", pfAnchorPath])

        // Kill existing network states to blocked IPs so already-open tabs disconnect immediately
        if killExistingConnections {
            for ip in PFConfigGenerator.sanitizeIPs(blockedIPs).prefix(64) {
                _ = run("/sbin/pfctl", ["-k", "0.0.0.0/0", "-k", ip])
                _ = run("/sbin/pfctl", ["-k", "::/0", "-k", ip])
            }
        }
    }

    private func ensurePFEnabled() {
        if let existing = try? String(contentsOfFile: pfTokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return
        }
        let result = run("/sbin/pfctl", ["-E"])
        // pfctl -E prints "Token : <digits>" on stderr or stdout
        let combined = result.stdout + "\n" + result.stderr
        for line in combined.components(separatedBy: .newlines) {
            if line.lowercased().contains("token") {
                let digits = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if !digits.isEmpty {
                    try? FileManager.default.createDirectory(
                        atPath: ZenConstants.supportDir,
                        withIntermediateDirectories: true
                    )
                    try? digits.write(toFile: pfTokenPath, atomically: true, encoding: .utf8)
                    chmod(pfTokenPath, 0o600)
                    return
                }
            }
        }
    }

    private func releasePFToken() {
        guard let token = try? String(contentsOfFile: pfTokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return }
        _ = run("/sbin/pfctl", ["-X", token])
        try? FileManager.default.removeItem(atPath: pfTokenPath)
    }

    // MARK: - DNS Resolution & Cache Flush

    static func resolveHosts(_ hosts: [String]) -> [String] {
        var ips: [String] = []
        for host in hosts {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &res)
            guard status == 0, let first = res else { continue }
            defer { freeaddrinfo(first) }

            var ptr: UnsafeMutablePointer<addrinfo>? = first
            while let current = ptr {
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if current.pointee.ai_family == AF_INET, let sa = current.pointee.ai_addr {
                    var sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                    if inet_ntop(AF_INET, &sin, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                        ips.append(String(cString: buf))
                    }
                } else if current.pointee.ai_family == AF_INET6, let sa = current.pointee.ai_addr {
                    var sin6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                    if inet_ntop(AF_INET6, &sin6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                        ips.append(String(cString: buf))
                    }
                }
                ptr = current.pointee.ai_next
            }
        }
        return PFConfigGenerator.sanitizeIPs(ips)
    }

    private func flushDNSCache() {
        _ = run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    private func run(_ executable: String, _ args: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, out, err)
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
