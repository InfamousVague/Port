import Foundation

/// Labels for notable public IPs (well-known resolvers / networks) and for
/// reserved/private ranges. Only confidently-known entries — no guesses.
enum KnownIPs {
    static func label(_ ip: String) -> String? {
        if let exact = exact[ip] { return exact }
        if ip == "::1" { return "Loopback" }
        if ip.hasPrefix("fe80:") { return "Link-local (IPv6)" }
        if ip.hasPrefix("fd") || ip.hasPrefix("fc") { return "Private (IPv6 ULA)" }

        let o = ip.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return nil }
        if o[0] == 127 { return "Loopback" }
        if o[0] == 10 { return "Private (10/8)" }
        if o[0] == 172, (16...31).contains(o[1]) { return "Private (172.16/12)" }
        if o[0] == 192, o[1] == 168 { return "Private LAN" }
        if o[0] == 169, o[1] == 254 { return "Link-local" }
        if o[0] == 100, (64...127).contains(o[1]) { return "CGNAT (carrier)" }
        if o[0] == 17 { return "Apple" }
        if o[0] >= 224, o[0] <= 239 { return "Multicast" }
        if o[0] == 255 { return "Broadcast" }
        return nil
    }

    private static let exact: [String: String] = [
        "1.1.1.1": "Cloudflare DNS", "1.0.0.1": "Cloudflare DNS",
        "1.1.1.2": "Cloudflare (malware-blocking)", "1.1.1.3": "Cloudflare (family)",
        "8.8.8.8": "Google DNS", "8.8.4.4": "Google DNS",
        "9.9.9.9": "Quad9 DNS", "149.112.112.112": "Quad9 DNS",
        "208.67.222.222": "OpenDNS", "208.67.220.220": "OpenDNS",
        "208.67.222.123": "OpenDNS FamilyShield",
        "94.140.14.14": "AdGuard DNS", "94.140.15.15": "AdGuard DNS",
        "94.140.14.15": "AdGuard (family)",
        "45.90.28.0": "NextDNS", "45.90.30.0": "NextDNS",
        "8.26.56.26": "Comodo Secure DNS", "8.20.247.20": "Comodo Secure DNS",
        "64.6.64.6": "Verisign DNS", "64.6.65.6": "Verisign DNS",
        "4.2.2.1": "Level3/CenturyLink DNS", "4.2.2.2": "Level3/CenturyLink DNS",
        "76.76.2.0": "Control D", "76.76.10.0": "Control D",
        "185.228.168.9": "CleanBrowsing", "185.228.169.9": "CleanBrowsing",
        "2606:4700:4700::1111": "Cloudflare DNS (v6)",
        "2001:4860:4860::8888": "Google DNS (v6)",
        "2620:fe::fe": "Quad9 DNS (v6)",
    ]
}
