import SwiftUI
import Combine

@main
struct MacStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var monitor = SystemMonitor()
    
    // Toggles
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showDisk") private var showDisk = false
    @AppStorage("showNetwork") private var showNetwork = false
    @AppStorage("showBattery") private var showBattery = false
    
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(monitor: monitor))
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Listen to monitor updates
        monitor.$stats
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBar()
            }
            .store(in: &cancellables)
            
        // Listen to settings changes using UserDefaults observation
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenuBar), name: UserDefaults.didChangeNotification, object: nil)
        
        updateMenuBar()
    }
    
    @objc func updateMenuBar() {
        guard let button = statusItem.button else { return }
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        
        func createAttachment(icon: String) -> NSAttributedString {
            let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            image?.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = image
            return NSAttributedString(attachment: attachment)
        }
        
        let attrString = NSMutableAttributedString()
        var isFirst = true
        
        if showCPU {
            attrString.append(createAttachment(icon: "cpu"))
            attrString.append(NSAttributedString(string: String(format: " %.0f%%", monitor.stats.cpuUsage), attributes: [.font: font]))
            isFirst = false
        }
        
        if showMemory {
            if !isFirst { attrString.append(NSAttributedString(string: " · ", attributes: [.font: font])) }
            attrString.append(createAttachment(icon: "memorychip"))
            attrString.append(NSAttributedString(string: " " + formatShortBytes(monitor.stats.memoryUsed), attributes: [.font: font]))
            isFirst = false
        }
        
        if showDisk {
            if !isFirst { attrString.append(NSAttributedString(string: " · ", attributes: [.font: font])) }
            attrString.append(createAttachment(icon: "internaldrive"))
            attrString.append(NSAttributedString(string: " " + formatShortBytes(monitor.stats.diskUsed), attributes: [.font: font]))
            isFirst = false
        }
        
        if showNetwork {
            if !isFirst { attrString.append(NSAttributedString(string: " · ", attributes: [.font: font])) }
            attrString.append(createAttachment(icon: "network"))
            attrString.append(NSAttributedString(string: " ↓\(formatSpeed(monitor.stats.networkDownload)) ↑\(formatSpeed(monitor.stats.networkUpload))", attributes: [.font: font]))
            isFirst = false
        }
        
        if showBattery {
            if !isFirst { attrString.append(NSAttributedString(string: " · ", attributes: [.font: font])) }
            attrString.append(createAttachment(icon: getBatteryIcon(level: monitor.stats.batteryLevel)))
            attrString.append(NSAttributedString(string: String(format: " %.0f%%", monitor.stats.batteryLevel), attributes: [.font: font]))
            isFirst = false
        }
        
        if attrString.length == 0 {
            button.image = NSImage(systemSymbolName: "chart.bar.doc.horizontal", accessibilityDescription: "MacStat")
            button.title = ""
        } else {
            button.image = nil
            button.attributedTitle = attrString
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }

    private func getBatteryIcon(level: Double) -> String {
        if level > 85 { return "battery.100" }
        if level > 60 { return "battery.75" }
        if level > 35 { return "battery.50" }
        if level > 10 { return "battery.25" }
        return "battery.0"
    }
    
    private func formatShortBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showDisk") private var showDisk = false
    @AppStorage("showNetwork") private var showNetwork = false
    @AppStorage("showBattery") private var showBattery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MacStat")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Divider()
            
            StatRowView(title: "CPU", value: String(format: "%.1f%%", monitor.stats.cpuUsage))
            StatRowView(title: "Memory", value: formatBytes(monitor.stats.memoryUsed) + " / " + formatBytes(monitor.stats.memoryTotal))
            StatRowView(title: "Disk", value: formatBytes(monitor.stats.diskUsed) + " / " + formatBytes(monitor.stats.diskTotal))
            StatRowView(title: "Network", value: "↑ " + formatSpeed(monitor.stats.networkUpload) + "  ↓ " + formatSpeed(monitor.stats.networkDownload))
            StatRowView(title: "Battery", value: String(format: "%.0f%%", monitor.stats.batteryLevel))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("메뉴바 표시 옵션")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Toggle("CPU", isOn: $showCPU)
                    Toggle("Memory", isOn: $showMemory)
                    Toggle("Disk", isOn: $showDisk)
                    Toggle("Network", isOn: $showNetwork)
                    Toggle("Battery", isOn: $showBattery)
                }
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            .padding(.vertical, 4)
            
            Divider()
            
            Button("Quit MacStat") {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding()
        .frame(width: 320)
    }
    
    // Formatting Helpers
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

struct StatRowView: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.vertical, 2)
    }
}
