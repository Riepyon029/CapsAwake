import Foundation

final class FakePower: PowerBackend {
    var disabled = false
    var saved: Bool?
    var writes: [Bool] = []
    var failWrite = false
    var failSave = false
    var failReadRecovery = false
    func readDisabled() throws -> Bool { disabled }
    func setDisabled(_ value: Bool) throws {
        if failWrite { throw CapsError.message("write failed") }
        writes.append(value); disabled = value
    }
    func saveOriginal(_ value: Bool) throws {
        if failSave { throw CapsError.message("disk full") }; saved = value
    }
    func loadOriginal() throws -> Bool? {
        if failReadRecovery { throw CapsError.message("cannot read recovery") }; return saved
    }
    func clearOriginal() throws { saved = nil }
}

@main
enum Tests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(label)") }
    }
    static func start(_ seconds: Int = 1800, token: String = UUID().uuidString) -> HelperRequest {
        HelperRequest(action: "start", seconds: seconds, token: token)
    }
    static func main() throws {
        for minutes in Product.durations {
            let power = FakePower(); let core = SessionController(backend: power)
            let token = UUID().uuidString
            let result = core.handle(start(minutes * 60, token: token), now: 10)
            expect(result.ok && result.active, "\(minutes) minute start")
            expect(power.disabled && power.saved == false, "saved before enabled")
            expect(result.remaining == minutes * 60, "duration exact")
            // A heartbeat just before the deadline keeps the session alive.
            for t in stride(from: 20, to: minutes * 60 + 10, by: 10) {
                _ = core.handle(HelperRequest(action: "heartbeat", token: token), now: Double(t))
            }
            core.tick(now: Double(minutes * 60 + 10))
            expect(!core.active && !power.disabled && power.saved == nil, "\(minutes) timer restores")
        }
        do {
            let p = FakePower(); p.disabled = true
            let c = SessionController(backend: p)
            _ = c.handle(start(), now: 0)
            _ = c.handle(HelperRequest(action: "stop"), now: 1)
            expect(p.disabled && p.saved == nil, "preserve original disabled=true")
        }
        do {
            let p = FakePower(); let c = SessionController(backend: p)
            _ = c.handle(start(), now: 0)
            c.tick(now: 19.999); expect(c.active, "heartbeat grace")
            c.tick(now: 20); expect(!c.active && !p.disabled, "crash watchdog restores")
        }
        do {
            let p = FakePower(); let c = SessionController(backend: p)
            _ = c.handle(start(), now: 0)
            let r = c.handle(HelperRequest(action: "heartbeat", token: UUID().uuidString), now: 19)
            expect(!r.ok, "wrong session token rejected")
            c.tick(now: 20); expect(!c.active, "wrong token cannot keep awake")
        }
        for seconds in [-1, 0, 30, 61, 1799, 1801, 86500, Int.max] {
            let p = FakePower(); let c = SessionController(backend: p)
            let r = c.handle(start(seconds), now: 0)
            expect(!r.ok && p.writes.isEmpty && p.saved == nil, "invalid duration \(seconds)")
        }
        do {
            let p = FakePower(); let c = SessionController(backend: p)
            expect(!c.handle(start(token: "bad"), now: 0).ok, "invalid UUID")
            var r = start(); r.version = 999
            expect(!c.handle(r, now: 0).ok && p.writes.isEmpty, "protocol mismatch")
            expect(!c.handle(HelperRequest(action: "execute"), now: 0).ok, "unknown action rejected")
        }
        do {
            let p = FakePower(); p.saved = false; p.disabled = true
            let c = SessionController(backend: p); c.recover()
            expect(!p.disabled && p.saved == nil, "restart recovers persisted original")
        }
        do {
            let p = FakePower(); p.failSave = true
            let c = SessionController(backend: p)
            expect(!c.handle(start(), now: 0).ok && p.writes.isEmpty, "no mutation without recovery record")
        }
        do {
            let p = FakePower(); let c = SessionController(backend: p)
            _ = c.handle(start(), now: 0); p.failWrite = true
            let r = c.handle(HelperRequest(action: "stop"), now: 1)
            expect(!r.ok && c.active && p.saved == false, "failed restore retains record")
            p.failWrite = false; c.tick(now: 2)
            expect(!c.active && !p.disabled && p.saved == nil, "failed restore retries")
        }
        do {
            let p = FakePower(); p.failWrite = true
            let c = SessionController(backend: p)
            expect(!c.handle(start(), now: 0).ok && p.saved == false, "failed start retains recovery")
            p.failWrite = false; c.tick(now: 1)
            expect(!c.active && p.saved == nil, "failed start rolls back")
        }
        do {
            let p = FakePower(); p.saved = false; p.disabled = true; p.failReadRecovery = true
            let c = SessionController(backend: p); c.recover()
            expect(!c.handle(start(), now: 0).ok && p.writes.isEmpty, "corrupt recovery prevents new start")
            p.failReadRecovery = false; c.tick(now: 1)
            expect(!p.disabled && p.saved == nil, "recovery read retries")
        }
        do {
            let p = FakePower(); let c = SessionController(backend: p)
            _ = c.handle(start(), now: 0)
            expect(!c.handle(start(3600), now: 1).ok, "double start rejected")
            expect(c.duration == 1800, "double start preserves timer")
        }
        do {
            var pair: [Int32] = [0, 0]
            expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0, "socketpair")
            defer { close(pair[0]); close(pair[1]) }
            let input = start(5400)
            try writePacket(input, to: pair[0])
            let output = try readPacket(HelperRequest.self, from: pair[1])
            expect(output.seconds == input.seconds && output.token == input.token, "socket protocol round trip")
        }
        do {
            var pair: [Int32] = [0, 0]
            expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0, "timeout socketpair")
            defer { close(pair[0]); close(pair[1]) }
            setSocketTimeout(pair[1])
            let began = continuousSeconds()
            do {
                _ = try readPacket(HelperRequest.self, from: pair[1])
                expect(false, "silent client must time out")
            } catch {
                expect(continuousSeconds() - began < 5, "silent client cannot block watchdog")
            }
        }
        print("PASS: \(checks) checks, all 8 timers, watchdog, recovery, original-state preservation, validation and socket framing")
    }
}
