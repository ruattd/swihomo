import Foundation

enum ScreenshotDemoMode {
    static let launchArgument = "--screenshot-demo"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

struct ScreenshotDemoState {
    let snapshot: ClientSnapshot
    let proxyGroups: [MihomoProxyGroup]
    let delays: [String: Int]
    let logEntries: [LogEntry]
    let externalResources: [ExternalResource]
    let connectionActivities: [MihomoConnectionActivity]
    let trafficUploadSpeed: Int64
    let trafficDownloadSpeed: Int64
    let trafficUploadTotal: Int64
    let trafficDownloadTotal: Int64
    let profileContents: [UUID: String]
    let resourceContents: [String: Data]
}

enum ScreenshotDemoFixtures {
    static func make() -> ScreenshotDemoState {
        let activeProfileID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let backupProfileID = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
        let localProfileID = UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!
        let activeProfileDate = date("2025-06-18T09:20:00Z")
        let backupProfileDate = date("2025-06-15T14:05:00Z")
        let localProfileDate = date("2025-05-27T11:40:00Z")

        let activeSubscription = MihomoSubscriptionInfo(
            upload: 3_214_000_000,
            download: 28_742_000_000,
            total: 107_374_182_400,
            expire: 1_800_000_000
        )
        let backupSubscription = MihomoSubscriptionInfo(
            upload: 1_208_000_000,
            download: 9_461_000_000,
            total: 53_687_091_200,
            expire: 1_791_000_000
        )

        let activeProfile = Profile(
            id: activeProfileID,
            name: "Aurora Relay",
            source: .remote,
            remoteURL: URL(string: "https://demo.example.test/subscriptions/aurora.yaml"),
            customUserAgent: nil,
            createdAt: date("2025-05-22T08:30:00Z"),
            updatedAt: activeProfileDate,
            lastFetchedAt: activeProfileDate,
            subscriptionInfo: activeSubscription,
            customOverridesEnabled: true,
            customOverrideYAML: "rules:\n  - DOMAIN-SUFFIX,example.test,DIRECT\n"
        )
        let backupProfile = Profile(
            id: backupProfileID,
            name: "Cedar Backup",
            source: .remote,
            remoteURL: URL(string: "https://demo.example.test/subscriptions/cedar.yaml"),
            customUserAgent: "Swihomo Demo",
            createdAt: date("2025-04-11T16:10:00Z"),
            updatedAt: backupProfileDate,
            lastFetchedAt: backupProfileDate,
            subscriptionInfo: backupSubscription,
            customOverridesEnabled: false
        )
        let localProfile = Profile(
            id: localProfileID,
            name: "Local Lab",
            source: .local,
            remoteURL: nil,
            customUserAgent: nil,
            createdAt: date("2025-03-04T10:15:00Z"),
            updatedAt: localProfileDate,
            lastFetchedAt: nil,
            subscriptionInfo: nil,
            customOverridesEnabled: true,
            customOverrideYAML: "dns:\n  nameserver:\n    - 1.1.1.1\n"
        )

        let overrides = ProxyOverrides(
            mode: .rule,
            logLevel: .debug,
            mixedPort: 7897,
            allowLAN: true,
            ipv6Enabled: true,
            dnsEnabled: true,
            controllerPort: 9097,
            controllerSecret: "demo-controller-secret",
            customYAML: "tun:\n  mtu: 1400\nprofile:\n  store-selected: true\n"
        )
        let snapshot = ClientSnapshot(
            schemaVersion: 1,
            profiles: [activeProfile, backupProfile, localProfile],
            activeProfileID: activeProfileID,
            overrides: overrides
        )

        let proxyGroups = [
            MihomoProxyGroup(
                name: "Auto Select",
                selected: "Tokyo Relay · VMess",
                candidates: [
                    "Tokyo Relay · VMess",
                    "Seoul Edge · Trojan",
                    "Sydney Fast · Hysteria2",
                    "Frankfurt Core · Shadowsocks",
                    "New York Hub · WireGuard"
                ]
            ),
            MihomoProxyGroup(
                name: "Streaming",
                selected: "Singapore Stream · Hysteria2",
                candidates: [
                    "Singapore Stream · Hysteria2",
                    "Los Angeles Media · Trojan",
                    "London Media · VMess",
                    "DIRECT"
                ]
            ),
            MihomoProxyGroup(
                name: "Fallback",
                selected: "Seoul Edge · Trojan",
                candidates: [
                    "Seoul Edge · Trojan",
                    "Tokyo Relay · VMess",
                    "DIRECT"
                ]
            ),
            MihomoProxyGroup(
                name: "Privacy Route",
                selected: "Frankfurt Core · Shadowsocks",
                candidates: [
                    "Frankfurt Core · Shadowsocks",
                    "New York Hub · WireGuard",
                    "DIRECT"
                ]
            )
        ]
        let delays = [
            "Tokyo Relay · VMess": 82,
            "Seoul Edge · Trojan": 116,
            "Sydney Fast · Hysteria2": 174,
            "Frankfurt Core · Shadowsocks": 228,
            "New York Hub · WireGuard": 261,
            "Singapore Stream · Hysteria2": 143,
            "Los Angeles Media · Trojan": 196,
            "London Media · VMess": 247,
            "DIRECT": 8
        ]

        let connectionActivities = [
            connectionActivity(
                id: "demo-connection-001",
                process: "Demo Browser",
                network: "tcp",
                type: "HTTP",
                host: "api.example.test",
                remoteDestination: "",
                destinationIP: "198.51.100.24",
                destinationPort: "443",
                sourcePort: "53218",
                upload: 1_842_000,
                download: 18_426_000,
                uploadSpeed: 284_000,
                downloadSpeed: 2_640_000,
                startedAt: "10:42:18",
                chains: ["Auto Select", "Tokyo Relay · VMess"],
                providerChains: ["Privacy Essentials"],
                rule: "RULE-SET",
                rulePayload: "privacy,Proxy"
            ),
            connectionActivity(
                id: "demo-connection-002",
                process: "Music Player",
                network: "tcp",
                type: "TLS",
                host: "stream.example.test",
                remoteDestination: "",
                destinationIP: "198.51.100.38",
                destinationPort: "443",
                sourcePort: "53242",
                upload: 428_000,
                download: 42_180_000,
                uploadSpeed: 46_000,
                downloadSpeed: 1_860_000,
                startedAt: "10:41:03",
                chains: ["Streaming", "Singapore Stream · Hysteria2"],
                providerChains: ["Streaming Policies"],
                rule: "GEOSITE",
                rulePayload: "media,Streaming"
            ),
            connectionActivity(
                id: "demo-connection-003",
                process: "Photo Library",
                network: "udp",
                type: "QUIC",
                host: "sync.example.test",
                remoteDestination: "",
                destinationIP: "203.0.113.52",
                destinationPort: "443",
                sourcePort: "53267",
                upload: 12_640_000,
                download: 8_942_000,
                uploadSpeed: 1_420_000,
                downloadSpeed: 738_000,
                startedAt: "10:39:27",
                chains: ["Auto Select", "Seoul Edge · Trojan"],
                providerChains: ["Regional Rules"],
                rule: "MATCH",
                rulePayload: ""
            ),
            connectionActivity(
                id: "demo-connection-004",
                process: "Notes Sync",
                network: "tcp",
                type: "HTTP",
                host: "notes.example.test",
                remoteDestination: "",
                destinationIP: "203.0.113.77",
                destinationPort: "443",
                sourcePort: "53301",
                upload: 2_310_000,
                download: 6_780_000,
                uploadSpeed: 92_000,
                downloadSpeed: 412_000,
                startedAt: "10:37:54",
                chains: ["Privacy Route", "Frankfurt Core · Shadowsocks"],
                providerChains: ["Privacy Essentials"],
                rule: "DOMAIN-SUFFIX",
                rulePayload: "example.test,Proxy"
            ),
            connectionActivity(
                id: "demo-connection-005",
                process: "Software Update",
                network: "tcp",
                type: "TLS",
                host: "updates.example.test",
                remoteDestination: "",
                destinationIP: "198.51.100.91",
                destinationPort: "443",
                sourcePort: "53328",
                upload: 96_000,
                download: 3_840_000,
                uploadSpeed: 18_000,
                downloadSpeed: 226_000,
                startedAt: "10:35:11",
                chains: ["DIRECT"],
                providerChains: [],
                rule: "DOMAIN-SUFFIX",
                rulePayload: "updates.example.test,DIRECT"
            )
        ]

        let externalResources = [
            ExternalResource(
                id: "demo-provider-aurora",
                kind: .proxyProvider,
                name: "Aurora Nodes",
                providerType: "http",
                path: "providers/aurora.yaml",
                url: "https://demo.example.test/providers/aurora.yaml",
                behavior: "classical",
                isPresent: true,
                updatedAt: date("2025-06-18T08:55:00Z"),
                subscriptionInfo: activeSubscription,
                ruleCount: nil
            ),
            ExternalResource(
                id: "demo-provider-cedar",
                kind: .proxyProvider,
                name: "Cedar Community Nodes",
                providerType: "file",
                path: "providers/cedar.yaml",
                url: nil,
                behavior: "classical",
                isPresent: false,
                updatedAt: date("2025-06-10T12:30:00Z"),
                subscriptionInfo: nil,
                ruleCount: nil
            ),
            ExternalResource(
                id: "demo-rules-privacy",
                kind: .ruleProvider,
                name: "Privacy Essentials",
                providerType: "http",
                path: "rules/privacy.mrs",
                url: "https://demo.example.test/rules/privacy.mrs",
                behavior: "domain",
                isPresent: true,
                updatedAt: date("2025-06-17T21:10:00Z"),
                subscriptionInfo: nil,
                ruleCount: 12_840
            ),
            ExternalResource(
                id: "demo-rules-streaming",
                kind: .ruleProvider,
                name: "Streaming Policies",
                providerType: "http",
                path: "rules/streaming.yaml",
                url: "https://demo.example.test/rules/streaming.yaml",
                behavior: "classical",
                isPresent: true,
                updatedAt: date("2025-06-16T07:45:00Z"),
                subscriptionInfo: nil,
                ruleCount: 3_420
            ),
            ExternalResource(
                id: "demo-geoip",
                kind: .geoData,
                name: "GeoIP Database",
                providerType: "mmdb",
                path: "geo/geoip.metadb",
                url: nil,
                behavior: nil,
                isPresent: true,
                updatedAt: date("2025-06-12T06:00:00Z"),
                subscriptionInfo: nil,
                ruleCount: nil
            ),
            ExternalResource(
                id: "demo-geosite",
                kind: .geoData,
                name: "GeoSite Database",
                providerType: "mrs",
                path: "geo/geosite.dat",
                url: nil,
                behavior: nil,
                isPresent: false,
                updatedAt: nil,
                subscriptionInfo: nil,
                ruleCount: nil
            )
        ]

        let logEntries = [
            log("B0000000-0000-4000-8000-000000000001", "2025-06-18T09:21:12Z", .app, "Lifecycle", .info, "Loaded screenshot demo fixtures."),
            log("B0000000-0000-4000-8000-000000000002", "2025-06-18T09:20:44Z", .core, "mihomo", .info, "REST controller is ready on 127.0.0.1:9097."),
            log("B0000000-0000-4000-8000-000000000003", "2025-06-18T09:20:31Z", .app, "Profiles", .debug, "Loaded 3 profiles from the in-memory demo catalog."),
            log("B0000000-0000-4000-8000-000000000004", "2025-06-18T09:20:27Z", .core, "DNS", .debug, "Using demo resolver policy with 3 upstreams."),
            log("B0000000-0000-4000-8000-000000000005", "2025-06-18T09:20:18Z", .app, "Proxies", .info, "Loaded 4 proxy groups and 9 delay results."),
            log("B0000000-0000-4000-8000-000000000006", "2025-06-18T09:19:55Z", .core, "Router", .warning, "Fallback route selected for an unclassified destination."),
            log("B0000000-0000-4000-8000-000000000007", "2025-06-18T09:19:42Z", .app, "Resources", .info, "Loaded 6 external resources."),
            log("B0000000-0000-4000-8000-000000000008", "2025-06-18T09:19:20Z", .core, "Provider", .warning, "Cedar Community Nodes is not present in the cache."),
            log("B0000000-0000-4000-8000-000000000009", "2025-06-18T09:18:47Z", .app, "Connections", .debug, "Tracking 5 live connections."),
            log("B0000000-0000-4000-8000-000000000010", "2025-06-18T09:18:11Z", .core, "Tunnel", .error, "A sample upstream was retried after a timeout."),
            log("B0000000-0000-4000-8000-000000000011", "2025-06-18T09:17:36Z", .app, "Configuration", .info, "Applied routing mode Rule and DNS settings."),
            log("B0000000-0000-4000-8000-000000000012", "2025-06-18T09:16:58Z", .core, "TUN", .debug, "Packet flow attached with MTU 1400.")
        ]

        let profileContents = [
            activeProfileID: "proxies:\n  - name: Tokyo Relay · VMess\n    type: vmess\n    server: tokyo.demo.example.test\n    port: 443\n    uuid: 00000000-0000-4000-8000-000000000001\nproxy-groups:\n  - name: Auto Select\n    type: select\n    proxies:\n      - Tokyo Relay · VMess\n      - Seoul Edge · Trojan\nrules:\n  - RULE-SET,Privacy Essentials,Proxy\n  - MATCH,Auto Select\n",
            backupProfileID: "proxies:\n  - name: Cedar Backup · Trojan\n    type: trojan\n    server: cedar.demo.example.test\n    port: 443\n    password: demo-password\nproxy-groups:\n  - name: Proxy\n    type: select\n    proxies:\n      - Cedar Backup · Trojan\n      - DIRECT\nrules:\n  - MATCH,Proxy\n",
            localProfileID: "mixed-port: 7897\nproxies:\n  - name: Local HTTP\n    type: http\n    server: 192.0.2.10\n    port: 8080\nproxy-groups:\n  - name: Local Route\n    type: select\n    proxies:\n      - Local HTTP\n      - DIRECT\nrules:\n  - MATCH,Local Route\n"
        ]
        let resourceContents = [
            "demo-provider-aurora": Data("proxies:\n  - name: Tokyo Relay · VMess\n    type: vmess\n    server: tokyo.demo.example.test\n    port: 443\n".utf8),
            "demo-rules-privacy": Data("payload:\n  - DOMAIN-SUFFIX,telemetry.example.test\n  - DOMAIN-SUFFIX,ads.example.test\n".utf8),
            "demo-rules-streaming": Data("payload:\n  - DOMAIN-SUFFIX,video.example.test\n  - DOMAIN-SUFFIX,music.example.test\n".utf8)
        ]

        return ScreenshotDemoState(
            snapshot: snapshot,
            proxyGroups: proxyGroups,
            delays: delays,
            logEntries: logEntries,
            externalResources: externalResources,
            connectionActivities: connectionActivities,
            trafficUploadSpeed: 2_400_000,
            trafficDownloadSpeed: 8_700_000,
            trafficUploadTotal: 4_826_000_000,
            trafficDownloadTotal: 38_412_000_000,
            profileContents: profileContents,
            resourceContents: resourceContents
        )
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)!
    }

    private static func log(
        _ id: String,
        _ timestamp: String,
        _ source: LogSource,
        _ module: String,
        _ level: LogLevel,
        _ message: String
    ) -> LogEntry {
        LogEntry(
            id: UUID(uuidString: id)!,
            timestamp: date(timestamp),
            source: source,
            module: module,
            level: level,
            message: message
        )
    }

    private static func connectionActivity(
        id: String,
        process: String,
        network: String,
        type: String,
        host: String,
        remoteDestination: String,
        destinationIP: String,
        destinationPort: String,
        sourcePort: String,
        upload: Int64,
        download: Int64,
        uploadSpeed: Int64,
        downloadSpeed: Int64,
        startedAt: String,
        chains: [String],
        providerChains: [String],
        rule: String,
        rulePayload: String
    ) -> MihomoConnectionActivity {
        let metadata = MihomoConnectionMetadata(
            network: network,
            type: type,
            sourceIP: "192.0.2.24",
            sourcePort: sourcePort,
            destinationIP: destinationIP,
            destinationPort: destinationPort,
            host: host,
            process: process,
            processPath: "/Applications/Swihomo Demo.app/Contents/MacOS/Swihomo Demo",
            remoteDestination: remoteDestination
        )
        let connection = MihomoConnection(
            id: id,
            metadata: metadata,
            upload: upload,
            download: download,
            startedAt: startedAt,
            chains: chains,
            providerChains: providerChains,
            rule: rule,
            rulePayload: rulePayload
        )
        return MihomoConnectionActivity(
            connection: connection,
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed
        )
    }
}

extension MihomoConnectionMetadata {
    init(
        network: String,
        type: String,
        sourceIP: String,
        sourcePort: String,
        destinationIP: String,
        destinationPort: String,
        host: String,
        process: String,
        processPath: String,
        remoteDestination: String
    ) {
        self.network = network
        self.type = type
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.host = host
        self.process = process
        self.processPath = processPath
        self.remoteDestination = remoteDestination
    }
}

extension MihomoConnection {
    init(
        id: String,
        metadata: MihomoConnectionMetadata,
        upload: Int64,
        download: Int64,
        startedAt: String?,
        chains: [String],
        providerChains: [String],
        rule: String,
        rulePayload: String
    ) {
        self.id = id
        self.metadata = metadata
        self.upload = upload
        self.download = download
        self.startedAt = startedAt
        self.chains = chains
        self.providerChains = providerChains
        self.rule = rule
        self.rulePayload = rulePayload
    }
}
