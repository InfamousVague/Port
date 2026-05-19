import Darwin
import Foundation

struct PortError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ProcessControl {
    private static func send(_ signal: Int32, to pid: Int32) throws {
        if kill(pid, signal) != 0 {
            let code = errno
            throw PortError(message: "kill(pid: \(pid), sig: \(signal)) failed: \(String(cString: strerror(code)))")
        }
    }

    static func terminate(_ pid: Int32, force: Bool = false) throws {
        try send(force ? SIGKILL : SIGTERM, to: pid)
    }

    static func pause(_ pid: Int32) throws {
        try send(SIGSTOP, to: pid)
    }

    static func resume(_ pid: Int32) throws {
        try send(SIGCONT, to: pid)
    }
}
