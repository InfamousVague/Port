import Darwin
import Foundation

struct LocalAddress {
    let hostname: String
    let primary: String?

    static func current() -> LocalAddress {
        let host = ProcessInfo.processInfo.hostName
        var primary: String?
        var fallback: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return LocalAddress(hostname: host, primary: nil)
        }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &hostBuf, socklen_t(hostBuf.count),
                nil, 0, NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = String(cString: hostBuf)
            let name = String(cString: ptr.pointee.ifa_name)
            if name.hasPrefix("en"), primary == nil { primary = ip }
            if fallback == nil { fallback = ip }
        }

        return LocalAddress(hostname: host, primary: primary ?? fallback)
    }
}
