import Foundation
import Combine
import IOKit
import os

struct SystemStats {
    var cpuUsage: Double = 0.0
    var memoryUsed: Double = 0.0
    var memoryTotal: Double = 0.0
    var diskUsed: Double = 0.0
    var diskTotal: Double = 0.0
    var networkUpload: Double = 0.0
    var networkDownload: Double = 0.0
    var batteryLevel: Double = 0.0
}

class SystemMonitor: ObservableObject {
    @Published var stats = SystemStats()
    private var timer: Timer?

    // CPU state
    private var previousCpuInfo: host_cpu_load_info?

    // Network state
    private var previousNetworkTime: Date = Date()
    private var previousNetworkBytesIn: UInt64 = 0
    private var previousNetworkBytesOut: UInt64 = 0

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        updateStats()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateStats() {
        let cpu = getCPUUsage()
        let mem = getMemoryUsage()
        let disk = getDiskUsage()
        let net = getNetworkUsage()
        let battery = getBatteryLevel()

        DispatchQueue.main.async {
            self.stats.cpuUsage = cpu
            self.stats.memoryUsed = mem.used
            self.stats.memoryTotal = mem.total
            self.stats.diskUsed = disk.used
            self.stats.diskTotal = disk.total
            self.stats.networkUpload = net.upload
            self.stats.networkDownload = net.download
            self.stats.batteryLevel = battery
        }
    }

    // MARK: - CPU
    private func getCPUUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return 0.0 }

        var usage: Double = 0.0
        if let prev = previousCpuInfo {
            let userDiff = Double(cpuInfo.cpu_ticks.0 - prev.cpu_ticks.0)
            let sysDiff  = Double(cpuInfo.cpu_ticks.1 - prev.cpu_ticks.1)
            let idleDiff = Double(cpuInfo.cpu_ticks.2 - prev.cpu_ticks.2)
            let niceDiff = Double(cpuInfo.cpu_ticks.3 - prev.cpu_ticks.3)
            
            let totalTicks = userDiff + sysDiff + idleDiff + niceDiff
            let usedTicks = userDiff + sysDiff + niceDiff

            if totalTicks > 0 {
                usage = (usedTicks / totalTicks) * 100.0
            }
        }

        previousCpuInfo = cpuInfo
        return usage
    }

    // MARK: - Memory
    private func getMemoryUsage() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory) // Bytes

        if result == KERN_SUCCESS {
            // Page size
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)

            let active = Double(stats.active_count) * Double(pageSize)
            let wired = Double(stats.wire_count) * Double(pageSize)
            let compressed = Double(stats.compressor_page_count) * Double(pageSize)

            let used = active + wired + compressed
            return (used: used, total: physicalMemory)
        }

        return (used: 0, total: physicalMemory)
    }

    // MARK: - Disk
    private func getDiskUsage() -> (used: Double, total: Double) {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity {
                let used = Double(total - available)
                return (used: used, total: Double(total))
            }
        } catch {
            print("Disk usage error: \(error)")
        }
        return (used: 0, total: 0)
    }

    // MARK: - Network
    private func getNetworkUsage() -> (upload: Double, download: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let name = String(cString: interface.ifa_name)
            
            // Only aggregate en0 typically, or sum all
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if name.hasPrefix("en") {
                    let data = unsafeBitCast(interface.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    bytesIn += UInt64(data.pointee.ifi_ibytes)
                    bytesOut += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = interface.ifa_next
        }
        
        freeifaddrs(ifaddr)
        
        let now = Date()
        let timeDiff = now.timeIntervalSince(previousNetworkTime)
        
        var downloadSpeed: Double = 0
        var uploadSpeed: Double = 0
        
        if timeDiff > 0 {
            let inDiff = bytesIn >= previousNetworkBytesIn ? bytesIn - previousNetworkBytesIn : 0
            let outDiff = bytesOut >= previousNetworkBytesOut ? bytesOut - previousNetworkBytesOut : 0
            
            downloadSpeed = Double(inDiff) / timeDiff
            uploadSpeed = Double(outDiff) / timeDiff
        }
        
        previousNetworkTime = now
        previousNetworkBytesIn = bytesIn
        previousNetworkBytesOut = bytesOut
        
        return (upload: uploadSpeed, download: downloadSpeed)
    }

    // MARK: - Battery
    private func getBatteryLevel() -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let regex = try? NSRegularExpression(pattern: "(\\d+)%"),
                   let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                    if let range = Range(match.range(at: 1), in: output) {
                        if let percent = Double(output[range]) {
                            return percent
                        }
                    }
                }
            }
        } catch {
            print("Failed to get battery info: \(error)")
        }
        
        return 100.0 // Default or fallback if desktop (like Mac Mini)
    }
}
