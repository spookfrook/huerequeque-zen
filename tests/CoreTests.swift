import Foundation

private var passed = 0
private var failed = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        fputs("FAIL (\(URL(fileURLWithPath: file).lastPathComponent):\(line)): \(message)\n", stderr)
    }
}

final class MockBlocker: SystemBlocker {
    var appliedSpecs: [EffectiveBlockingSpec] = []
    var killFlags: [Bool] = []
    var integrityReturn = true

    func apply(spec: EffectiveBlockingSpec, killExistingConnections: Bool) throws {
        appliedSpecs.append(spec)
        killFlags.append(killExistingConnections)
    }

    func verifyHostsIntegrity(for spec: EffectiveBlockingSpec) -> Bool {
        return integrityReturn
    }
}

func makeTempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("huerequeque-test-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

@main
struct CoreTestsRunner {
static func main() {
// MARK: - 1. DomainNormalizer Tests

do {
    check(DomainNormalizer.normalize("https://X.COM/home?foo=bar") == "x.com", "strips scheme, path, query, lowercases")
    check(DomainNormalizer.normalize("*.reddit.com:443/r/all") == "reddit.com", "strips wildcard, port, path")
    check(DomainNormalizer.normalize("  Instagram.com. ") == "instagram.com", "trims whitespace and trailing dot")
    check(DomainNormalizer.normalize("localhost") == nil, "rejects localhost")
    check(DomainNormalizer.normalize("127.0.0.1") == nil, "rejects raw IPv4")
    check(DomainNormalizer.normalize("notadomain") == nil, "rejects single label")
    check(DomainNormalizer.normalize("bad host.com") == nil, "rejects spaces")

    let parsed = DomainNormalizer.parseInput("https://x.com/explore, twitter.com\nX.COM ; reddit.com")
    check(parsed == ["x.com", "twitter.com", "reddit.com"], "parses mixed separators and deduplicates")

    let expanded = DomainNormalizer.expandedHosts(for: ["x.com", "news.ycombinator.com"])
    check(expanded.contains("x.com") && expanded.contains("www.x.com") && expanded.contains("m.x.com") && expanded.contains("mobile.x.com"), "expands apex + www + mobile for major distractors")
    check(expanded.contains("news.ycombinator.com") && !expanded.contains("www.news.ycombinator.com"), "does not prefix www to deep subdomain")
}

// MARK: - 2. HostsFileEditor Tests

do {
    let baseHosts = """
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost
    """
    let withBlock = HostsFileEditor.apply(domains: ["x.com"], to: baseHosts)
    check(withBlock.contains("127.0.0.1 localhost"), "preserves original hosts")
    check(withBlock.contains(HostsFileEditor.beginMarker), "adds begin marker")
    check(withBlock.contains("0.0.0.0 x.com"), "blocks ipv4 x.com")
    check(withBlock.contains(":: www.x.com"), "blocks ipv6 www.x.com")
    check(HostsFileEditor.containsExactBlock(domains: ["x.com"], in: withBlock), "integrity check passes")
    check(!HostsFileEditor.containsExactBlock(domains: ["x.com", "reddit.com"], in: withBlock), "integrity detects drift")

    // Idempotent replace
    let reapplied = HostsFileEditor.apply(domains: ["x.com"], to: withBlock)
    check(reapplied == withBlock, "applying same domains twice is idempotent")

    // Clean removal
    let removed = HostsFileEditor.apply(domains: [], to: withBlock)
    check(!removed.contains(HostsFileEditor.beginMarker), "removes managed markers when empty")
    check(removed.contains("127.0.0.1 localhost"), "keeps original lines after cleanup")
}

// MARK: - 3. PFConfigGenerator Tests

do {
    let blockRules = PFConfigGenerator.anchorRules(
        for: .blocklist(domains: ["x.com"]),
        resolvedBlockedIPs: ["104.244.42.1", "127.0.0.1", "0.0.0.0", "bad;rm -rf /"],
        resolvedAllowedIPs: []
    )
    check(blockRules.contains("104.244.42.1"), "includes valid resolved IP")
    check(!blockRules.contains("127.0.0.1") && !blockRules.contains("0.0.0.0") && !blockRules.contains("rm -rf"), "sanitizes loopback and injection attempts")
    check(blockRules.contains("block drop out quick proto { tcp, udp } to <huerequeque_blocked>"), "emits block rule")

    let allowRules = PFConfigGenerator.anchorRules(
        for: .allowlist(allowedDomains: ["github.com"], extraBlockedDomains: ["x.com"]),
        resolvedBlockedIPs: ["104.244.42.1"],
        resolvedAllowedIPs: ["140.82.121.4"]
    )
    check(allowRules.contains("pass out quick proto { tcp, udp } to <huerequeque_allowed>"), "allows whitelisted table")
    check(allowRules.contains("block drop out quick proto { tcp, udp } to any port { 80, 443 }"), "blocks non-whitelisted web traffic")

    let pfConf = "anchor \"com.apple/*\"\nload anchor \"com.apple\" from \"/etc/pf.anchors/com.apple\"\n"
    let first = PFConfigGenerator.ensureAnchorReference(in: pfConf)
    check(first.changed && first.content.contains("anchor \"\(ZenConstants.anchorName)\""), "adds anchor reference")
    let second = PFConfigGenerator.ensureAnchorReference(in: first.content)
    check(!second.changed && second.content == first.content, "anchor reference is idempotent")
}

// MARK: - 4. DaemonCore Unbreakable Invariants & Reboot Recovery

do {
    var fakeNow = Date(timeIntervalSince1970: 1_800_000_000) // fixed deterministic timestamp
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let stateURL = makeTempURL("state.json")
    let blocker = MockBlocker()

    let core = DaemonCore(stateURL: stateURL, blocker: blocker, clock: { fakeNow }, calendar: cal)
    core.bootstrapEnforcement()
    check(blocker.appliedSpecs.last == EffectiveBlockingSpec.none, "starts clean when idle")

    // Start 30-min block
    let startResp = core.handle(DaemonRequest(command: .startBlock, domains: ["x.com", "reddit.com"], mode: .blocklist, durationSeconds: 1800, label: "Enfoque"))
    check(startResp.ok, "starts on-demand block")
    check(blocker.appliedSpecs.last == .blocklist(domains: ["x.com", "reddit.com"]), "enforces blocklist immediately")
    check(blocker.killFlags.last == true, "kills existing connections on start")

    // Cannot start another block while active
    let dupResp = core.handle(DaemonRequest(command: .startBlock, domains: ["youtube.com"], mode: .blocklist, durationSeconds: 600))
    check(!dupResp.ok, "refuses overlapping start_block")

    // Cannot shorten active block
    let negExtend = core.handle(DaemonRequest(command: .extendBlock, durationSeconds: -600))
    check(!negExtend.ok, "refuses negative extend")

    // Can extend active block
    let posExtend = core.handle(DaemonRequest(command: .extendBlock, durationSeconds: 900))
    check(posExtend.ok && core.state.blockRemainingSeconds(at: fakeNow) == 2700, "extends block by 15 min")

    // Can add new domain while locked (never remove)
    let addResp = core.handle(DaemonRequest(command: .addBlockDomains, domains: ["youtube.com"]))
    check(addResp.ok, "adds domain to active blocklist")
    check(core.state.activeBlock?.domains == ["x.com", "reddit.com", "youtube.com"], "merges new domain into active block")

    // Simulate reboot: instantiate fresh DaemonCore from persisted state.json
    let blockerAfterReboot = MockBlocker()
    fakeNow = fakeNow.addingTimeInterval(600) // 10 min later
    let coreAfterReboot = DaemonCore(stateURL: stateURL, blocker: blockerAfterReboot, clock: { fakeNow }, calendar: cal)
    coreAfterReboot.bootstrapEnforcement()
    check(coreAfterReboot.state.isBlockActive(at: fakeNow), "block survives daemon restart / reboot")
    check(blockerAfterReboot.appliedSpecs.last == .blocklist(domains: ["x.com", "reddit.com", "youtube.com"]), "re-applies block on boot")

    // Advance past expiration
    fakeNow = fakeNow.addingTimeInterval(2200)
    coreAfterReboot.tick()
    check(!coreAfterReboot.state.isBlockActive(at: fakeNow), "expires automatically when timer elapses")
    check(blockerAfterReboot.appliedSpecs.last == EffectiveBlockingSpec.none, "lifts block automatically on expiration")
}

// MARK: - 5. Allowtime Mode, Daily Budget, Strict Lock & Day Rollover

do {
    // 2026-11-25 10:00:00 UTC
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    var fakeNow = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 10, minute: 0, second: 0))!
    let stateURL = makeTempURL("allowtime.json")
    let blocker = MockBlocker()

    let core = DaemonCore(stateURL: stateURL, blocker: blocker, clock: { fakeNow }, calendar: cal)
    core.bootstrapEnforcement()

    // Arm Allowtime with 15 min daily budget, strictDailyLock = true
    let cfg = AllowtimeConfig(enabled: true, domains: ["x.com", "instagram.com"], dailyBudgetSeconds: 900, defaultWindowSeconds: 600, strictDailyLock: true)
    let armResp = core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: cfg))
    check(armResp.ok, "arms Allowtime with strict daily lock")
    check(blocker.appliedSpecs.last == .blocklist(domains: ["x.com", "instagram.com"]), "Allowtime immediately blocks domains 24/7")

    // Strict daily lock rejects disabling Allowtime, removing a domain, or raising budget
    var badCfg1 = cfg; badCfg1.enabled = false
    check(!core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: badCfg1)).ok, "strict lock forbids disabling Allowtime today")
    var badCfg2 = cfg; badCfg2.domains = ["x.com"]
    check(!core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: badCfg2)).ok, "strict lock forbids removing Allowtime domain today")
    var badCfg3 = cfg; badCfg3.dailyBudgetSeconds = 1800
    check(!core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: badCfg3)).ok, "strict lock forbids raising daily budget today")
    var badCfg4 = cfg; badCfg4.strictDailyLock = false
    check(!core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: badCfg4)).ok, "strict lock forbids turning itself off today")

    // Strict daily lock STILL permits adding another domain!
    var tighterCfg = cfg; tighterCfg.domains = ["x.com", "instagram.com", "tiktok.com"]
    check(core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: tighterCfg)).ok, "strict lock allows adding domains")

    // Open a 10-minute window (600s out of 900s daily budget)
    let openResp = core.handle(DaemonRequest(command: .openAllowtimeWindow, durationSeconds: 600))
    check(openResp.ok, "opens Allowtime window")
    check(blocker.appliedSpecs.last == EffectiveBlockingSpec.none, "lifts block while Allowtime window is open")

    // Close window early after 3 minutes (180s) -> saves remaining 7 min for later!
    fakeNow = fakeNow.addingTimeInterval(180)
    let closeResp = core.handle(DaemonRequest(command: .closeAllowtimeWindow))
    check(closeResp.ok, "closes Allowtime window early")
    check(blocker.appliedSpecs.last == .blocklist(domains: ["x.com", "instagram.com", "tiktok.com"]), "re-blocks immediately on early close")
    check(core.state.effectiveAllowtimeUsedToday(at: fakeNow, calendar: cal) == 180, "charges only actual elapsed 180s")
    check(core.state.allowtimeBudgetRemaining(at: fakeNow, calendar: cal) == 720, "leaves 720s remaining today")

    // Request 20 min (1200s) -> clamped to remaining 720s!
    let open2 = core.handle(DaemonRequest(command: .openAllowtimeWindow, durationSeconds: 1200))
    check(open2.ok && core.state.allowtimeWindowRemainingSeconds(at: fakeNow) == 720, "clamps requested window to remaining daily budget")

    // Let window expire naturally
    fakeNow = fakeNow.addingTimeInterval(725)
    core.tick()
    check(!core.state.isAllowtimeWindowOpen(at: fakeNow), "window closes automatically at expiry")
    check(blocker.appliedSpecs.last == .blocklist(domains: ["x.com", "instagram.com", "tiktok.com"]), "re-blocks automatically at expiry")
    check(core.state.allowtimeBudgetRemaining(at: fakeNow, calendar: cal) == 0, "daily budget exhausted")

    // Attempting to open another window today is rejected
    let open3 = core.handle(DaemonRequest(command: .openAllowtimeWindow, durationSeconds: 300))
    check(!open3.ok, "rejects opening window when daily budget is 0")

    // Next day rollover (2026-11-26 08:00:00 UTC) resets budget & unlocks strictDailyLock!
    fakeNow = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 8, minute: 0, second: 0))!
    core.tick()
    check(core.state.allowtimeBudgetRemaining(at: fakeNow, calendar: cal) == 900, "resets daily budget at midnight")
    check(!core.state.isStrictDailyLockActive(at: fakeNow, calendar: cal), "unlocks strict daily lock next day")
    let openTomorrow = core.handle(DaemonRequest(command: .openAllowtimeWindow, durationSeconds: 300))
    check(openTomorrow.ok, "can open Allowtime window again tomorrow")
}

// MARK: - 6. On-Demand Block Overrides Allowtime

do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let fakeNow = Date(timeIntervalSince1970: 1_800_050_000)
    let stateURL = makeTempURL("overlap.json")
    let blocker = MockBlocker()
    let core = DaemonCore(stateURL: stateURL, blocker: blocker, clock: { fakeNow }, calendar: cal)

    let cfg = AllowtimeConfig(enabled: true, domains: ["x.com"], dailyBudgetSeconds: 1800, defaultWindowSeconds: 600, strictDailyLock: false)
    _ = core.handle(DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: cfg))
    _ = core.handle(DaemonRequest(command: .openAllowtimeWindow, durationSeconds: 600))
    check(core.state.isAllowtimeWindowOpen(at: fakeNow), "Allowtime window starts open")

    // Starting an On-Demand block covering x.com closes the open Allowtime window immediately!
    let startBlock = core.handle(DaemonRequest(command: .startBlock, domains: ["x.com", "youtube.com"], mode: .blocklist, durationSeconds: 1800))
    check(startBlock.ok, "starts On-Demand block")
    check(!core.state.isAllowtimeWindowOpen(at: fakeNow), "On-Demand block closes overlapping Allowtime window")
    let tryOpen = core.handle(DaemonRequest(command: .openAllowtimeWindow, durationSeconds: 300))
    check(!tryOpen.ok, "cannot open Allowtime window while On-Demand block covers those sites")
}

// MARK: - 7. Unix Domain Socket IPC Roundtrip

do {
    let sockPath = "/tmp/hz-test-\(getpid()).sock"
    let stateURL = makeTempURL("ipc.json")
    let blocker = MockBlocker()
    let core = DaemonCore(stateURL: stateURL, blocker: blocker)
    let server = SocketServer(socketPath: sockPath, allowedUIDs: [getuid()])
    try! server.start { req in core.handle(req) }
    defer { server.stop() }

    let client = SocketClient(socketPath: sockPath)
    let pingResp = try! client.send(DaemonRequest(command: .ping))
    check(pingResp.ok && pingResp.state?.daemonVersion == ZenConstants.daemonVersion, "IPC ping roundtrip succeeds")

    let startResp = try! client.send(DaemonRequest(command: .startBlock, domains: ["x.com"], mode: .blocklist, durationSeconds: 600))
    check(startResp.ok && startResp.state?.activeBlock?.domains == ["x.com"], "IPC start_block roundtrip succeeds")
}

if failed > 0 {
    fputs("FAILED: \(failed) failed, \(passed) passed.\n", stderr)
    exit(1)
} else {
    print("OK: \(passed) checks passed.")
}
}
}
