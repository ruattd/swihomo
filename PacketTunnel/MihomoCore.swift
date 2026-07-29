import Foundation
import NetworkExtension

protocol MihomoCoreEngine: AnyObject {
    func start(configuration: MihomoRuntimeConfiguration, packetFlow: NEPacketTunnelFlow) async throws
    func stop() async
}

enum MihomoCoreFactory {
    static func make() -> any MihomoCoreEngine {
        EmbeddedMihomoCore()
    }

    static func prewarmGeoData(requiring requirements: MihomoGeoDataRequirements) async throws {
        await GeoDataCache.prewarm(
            in: try EmbeddedMihomoCore.homeDirectory(),
            requiring: requirements
        )
    }
}

private final class EmbeddedMihomoCore: MihomoCoreEngine {
    private var bridge: PacketFlowBridge?

    func start(configuration: MihomoRuntimeConfiguration, packetFlow: NEPacketTunnelFlow) async throws {
        let bridge = PacketFlowBridge(packetFlow: packetFlow)
        PacketFlowBridgeRegistry.set(bridge)

        var profile = [UInt8](configuration.profileYAML)
        let homeDirectory = try Self.homeDirectory()
        let result = profile.withUnsafeMutableBufferPointer { profileBuffer in
            homeDirectory.path.withCString { homeDirectoryPointer in
                SwihomoCoreStart(
                    profileBuffer.baseAddress,
                    profileBuffer.count,
                    homeDirectoryPointer
                )
            }
        }

        guard result == 0 else {
            bridge.stop()
            PacketFlowBridgeRegistry.clear(bridge)
            throw MihomoCoreError(message: Self.lastError())
        }

        self.bridge = bridge
        bridge.start()
    }

    func stop() async {
        bridge?.stop()
        SwihomoCoreStop()
        if let bridge {
            PacketFlowBridgeRegistry.clear(bridge)
        }
        bridge = nil
    }

    static func homeDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ClientError.storageUnavailable
        }
        let directory = applicationSupport.appendingPathComponent("MihomoCore", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func lastError() -> String {
        guard let error = SwihomoCoreLastError() else {
            return "Mihomo core failed to start."
        }
        defer { SwihomoCoreFreeString(error) }
        let message = String(cString: error)
        return message.isEmpty ? "Mihomo core failed to start." : message
    }
}

private enum GeoDataCache {
    private enum Resource {
        case geoIP
        case geoIPMMDB
        case geoSite

        var fileName: String {
            switch self {
            case .geoIP: "GeoIP.dat"
            case .geoIPMMDB: "geoip.metadb"
            case .geoSite: "GeoSite.dat"
            }
        }

        var sources: [URL] {
            let name: String
            switch self {
            case .geoIP: name = "geoip.dat"
            case .geoIPMMDB: name = "geoip.metadb"
            case .geoSite: name = "geosite.dat"
            }
            return [
                URL(string: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/\(name)")!,
                URL(string: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/\(name)")!
            ]
        }
    }

    private static let minimumFileSize = 1_024
    private static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    static func prewarm(in directory: URL, requiring requirements: MihomoGeoDataRequirements) async {
        var resources = [Resource]()
        if requirements.requiresGeoIP {
            resources.append(requirements.usesGeoIPDat ? .geoIP : .geoIPMMDB)
        }
        if requirements.requiresGeoSite {
            resources.append(.geoSite)
        }
        for resource in resources {
            await prewarm(resource, in: directory)
        }
    }

    private static func prewarm(_ resource: Resource, in directory: URL) async {
        let fileURL = directory.appendingPathComponent(resource.fileName)
        guard shouldRefresh(fileURL) else { return }

        do {
            let data = try await download(resource)
            try data.write(to: fileURL, options: .atomic)
            CoreLogStore.append(level: .info, message: "Downloaded \(resource.fileName) before starting Mihomo.")
        } catch {
            CoreLogStore.append(
                level: .warning,
                message: "Couldn't prewarm \(resource.fileName). Mihomo will use its configured downloader: \(error.localizedDescription)"
            )
        }
    }

    private static func shouldRefresh(_ fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= minimumFileSize,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }
        return Date.now.timeIntervalSince(modificationDate) >= maximumAge
    }

    private static func download(_ resource: Resource) async throws -> Data {
        var failures = [String]()
        for source in resource.sources {
            do {
                var request = URLRequest(url: source)
                request.timeoutInterval = 8
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                request.setValue("Swihomo", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw GeoDataDownloadError(message: "Unexpected server response from \(source.host ?? source.absoluteString).")
                }
                guard data.count >= minimumFileSize else {
                    throw GeoDataDownloadError(message: "Downloaded \(resource.fileName) from \(source.host ?? source.absoluteString) is incomplete.")
                }
                return data
            } catch {
                failures.append("\(source.host ?? source.absoluteString): \(error.localizedDescription)")
            }
        }
        throw GeoDataDownloadError(message: failures.joined(separator: "; "))
    }
}

private struct GeoDataDownloadError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct MihomoCoreError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum MihomoCoreResources {
    static func list() throws -> [ExternalResource] {
        guard let contents = SwihomoCoreExternalResources() else {
            throw MihomoCoreError(message: lastError())
        }
        defer { SwihomoCoreFreeString(contents) }
        return try JSONDecoder().decode(
            [ExternalResource].self,
            from: Data(String(cString: contents).utf8)
        )
    }

    static func read(identifier: String) throws -> Data {
        var contents: UnsafeMutablePointer<UInt8>?
        var length = 0
        let result = identifier.withCString {
            SwihomoCoreReadExternalResource($0, &contents, &length)
        }
        guard result == 0 else {
            throw MihomoCoreError(message: lastError())
        }
        guard let contents else { return Data() }
        defer { SwihomoCoreFreeData(contents) }
        return Data(bytes: contents, count: length)
    }

    static func write(identifier: String, contents: Data) throws {
        var bytes = [UInt8](contents)
        let result = identifier.withCString { identifierPointer in
            bytes.withUnsafeMutableBufferPointer { buffer in
                SwihomoCoreWriteExternalResource(identifierPointer, buffer.baseAddress, buffer.count)
            }
        }
        guard result == 0 else {
            throw MihomoCoreError(message: lastError())
        }
    }

    private static func lastError() -> String {
        guard let error = SwihomoCoreLastError() else {
            return "Mihomo core resource operation failed."
        }
        defer { SwihomoCoreFreeString(error) }
        let message = String(cString: error)
        return message.isEmpty ? "Mihomo core resource operation failed." : message
    }
}

enum MihomoCoreProxyGroups {
    static func order() throws -> [String] {
        guard let contents = SwihomoCoreProxyGroupOrder() else {
            throw MihomoCoreError(message: lastError())
        }
        defer { SwihomoCoreFreeString(contents) }
        return try JSONDecoder().decode([String].self, from: Data(String(cString: contents).utf8))
    }

    private static func lastError() -> String {
        guard let error = SwihomoCoreLastError() else {
            return "Mihomo core proxy group order is unavailable."
        }
        defer { SwihomoCoreFreeString(error) }
        let message = String(cString: error)
        return message.isEmpty ? "Mihomo core proxy group order is unavailable." : message
    }
}

private final class PacketFlowBridge: @unchecked Sendable {
    private let packetFlow: NEPacketTunnelFlow
    private let queue = DispatchQueue(label: "com.swihomo.packet-flow")
    private var isStopped = false

    init(packetFlow: NEPacketTunnelFlow) {
        self.packetFlow = packetFlow
    }

    func start() {
        readPackets()
    }

    func stop() {
        queue.sync {
            isStopped = true
        }
    }

    func write(_ data: Data, family: Int32) {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: family)])
        }
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.queue.async {
                guard !self.isStopped else { return }
                for (packet, family) in zip(packets, protocols) {
                    var bytes = [UInt8](packet)
                    _ = bytes.withUnsafeMutableBufferPointer { buffer in
                        SwihomoCoreInputPacket(buffer.baseAddress, buffer.count, family.int32Value)
                    }
                }
                self.readPackets()
            }
        }
    }
}

private enum PacketFlowBridgeRegistry {
    private static let lock = NSLock()
    private static var activeBridge: PacketFlowBridge?

    static func set(_ bridge: PacketFlowBridge) {
        lock.lock()
        activeBridge = bridge
        lock.unlock()
    }

    static func clear(_ bridge: PacketFlowBridge) {
        lock.lock()
        if activeBridge === bridge {
            activeBridge = nil
        }
        lock.unlock()
    }

    static func write(_ data: Data, family: Int32) {
        lock.lock()
        let bridge = activeBridge
        lock.unlock()
        bridge?.write(data, family: family)
    }
}

enum CoreLogStore {
    private static let store = PersistentLogStore(directoryName: "CoreLogs")

    static func append(level: LogLevel, message: String) {
        store.appendAsynchronously(source: .core, module: "Mihomo", level: level, message: message)
    }

    static func entries() -> [LogEntry] {
        store.entries()
    }

    static func clear() {
        _ = store.clear()
    }
}

@_cdecl("swihomo_write_packet")
func swihomoWritePacket(
    _ packet: UnsafePointer<UInt8>?,
    _ length: Int,
    _ family: Int32
) {
    guard let packet, length > 0 else { return }
    PacketFlowBridgeRegistry.write(Data(bytes: packet, count: length), family: family)
}

@_cdecl("swihomo_write_log")
func swihomoWriteLog(_ level: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?) {
    guard let level, let message else { return }
    let logLevel = LogLevel(rawValue: String(cString: level)) ?? .info
    CoreLogStore.append(level: logLevel, message: String(cString: message))
}
