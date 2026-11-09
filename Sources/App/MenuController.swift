import AppKit
import Foundation

final class MenuController: NSObject, NSMenuDelegate {
    private let cpuCollector: CPUCollector
    private let gpuCollector: GPUCollector
    private let ramCollector: RAMCollector
    private let thermalCollector = ThermalCollector()
    private let powerCollector = PowerCollector()
    private let processCollector = ProcessCollector()

    private(set) var cpuMenu: NSMenu!
    private(set) var gpuMenu: NSMenu!
    private(set) var ramMenu: NSMenu!

    private var activeMenu: NSMenu?
    private var detailTimer: Timer?

    /// Restituisce true se uno dei menu è attualmente aperto dall'utente.
    var isAnyMenuOpen: Bool {
        return activeMenu != nil
    }

    /// Callback invocato alla chiusura di un menu per aggiornare istantaneamente la barra.
    var onMenuClosed: (() -> Void)?

    // Larghezza fissa uniforme per tutte le righe dei menu
    private static let menuRowWidth: CGFloat = 270.0

    // CPU Graphic Views
    private let cpuTotalView = MenuRowView(label: "Total CPU:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let cpuTempView = MenuRowView(label: "Temperature:", value: "…", width: menuRowWidth, height: 22.0)
    private let cpuHotspotView = MenuRowView(label: "CPU Hotspot:", value: "…", width: menuRowWidth, height: 22.0)
    private let cpuPowerView = MenuRowView(label: "System Power:", value: "…", width: menuRowWidth, height: 22.0)
    private let superClusterView = MenuRowView(label: "Super Cluster:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let superRow1View = MenuDualCoreRowView(width: menuRowWidth, height: 20.0)
    private let superRow2View = MenuDualCoreRowView(width: menuRowWidth, height: 20.0)
    private let effClusterView = MenuRowView(label: "Efficiency Cluster:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let effRow1View = MenuDualCoreRowView(width: menuRowWidth, height: 20.0)
    private let effRow2View = MenuDualCoreRowView(width: menuRowWidth, height: 20.0)
    private let effRow3View = MenuDualCoreRowView(width: menuRowWidth, height: 20.0)

    // GPU Graphic Views
    private let gpuUsageView = MenuRowView(label: "GPU Usage:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let gpuTempView = MenuRowView(label: "Temperature:", value: "…", width: menuRowWidth, height: 22.0)
    private let gpuHotspotView = MenuRowView(label: "GPU Hotspot:", value: "…", width: menuRowWidth, height: 22.0)

    // RAM Graphic Views (flush-left alignment on x = 14pt)
    private let ramTotalView = MenuRowView(label: "Used RAM:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let ramAppView = MenuRowView(label: "App Memory:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramWiredView = MenuRowView(label: "Wired:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramCompressedView = MenuRowView(label: "Compressed:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramCacheView = MenuRowView(label: "Cached Files:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramFreeView = MenuRowView(label: "Free Memory:", value: "…", width: menuRowWidth, height: 22.0)
    private let topProcessHeaderView = MenuRowView(label: "Top Processes (Footprint):", isHeader: true, width: menuRowWidth, height: 22.0)
    private let topProcessViews = (0..<5).map { _ in MenuRowView(label: "…", value: "…", width: menuRowWidth, height: 22.0) }

    /// Traccia l'ID della finestra del menu correntemente aperto per calibrare una sola volta la posizione verticale.
    private var adjustedMenuWindowNumber: Int?

    init(cpu: CPUCollector, gpu: GPUCollector, ram: RAMCollector) {
        self.cpuCollector = cpu
        self.gpuCollector = gpu
        self.ramCollector = ram
        super.init()

        setupMenuPositionAdjuster()
        buildCPUMenu()
        buildGPUMenu()
        buildRAMMenu()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Su schermi Apple Silicon con notch (MacBook Pro 14"/16" e Air), AppKit posiziona
    /// la finestra di popup del menu (NSPopupMenuWindow) sotto l'altezza virtuale della barra (65pt)
    /// creando uno spazio vuoto non nativo di ~15-20pt rispetto al fondo della barra dei menu visibile.
    /// Questo observer riallinea la finestra a filo contro la base della barra, identico alla Batteria di sistema.
    private func setupMenuPositionAdjuster() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
    }

    @objc private func handleWindowDidUpdate(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        let cls = String(describing: type(of: win))
        if cls.contains("PopupMenuWindow") && adjustedMenuWindowNumber != win.windowNumber {
            guard let screen = win.screen ?? NSScreen.main else { return }
            let barBottom = screen.visibleFrame.maxY
            let delta = barBottom - win.frame.maxY
            if delta > 1.0 {
                adjustedMenuWindowNumber = win.windowNumber
                var frame = win.frame
                frame.origin.y += delta
                win.setFrame(frame, display: true)
            }
        }
    }

    private static func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.2f GB", gb)
    }

    private static func truncateName(_ name: String, maxLength: Int = 18) -> String {
        if name.count <= maxLength {
            return name
        }
        return String(name.prefix(maxLength - 1)) + "…"
    }

    private func makeItem(with view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    private func makeActivityMonitorItem(tag: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Open Activity Monitor…",
            action: #selector(openActivityMonitor(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = tag
        return item
    }

    private func makeQuitItem() -> NSMenuItem {
        return NSMenuItem(
            title: "Quit Pico",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    // MARK: - Costruzione Menu

    private func buildCPUMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let items: [NSMenuItem] = [
            makeItem(with: cpuTotalView),
            makeItem(with: cpuTempView),
            makeItem(with: cpuHotspotView),
            makeItem(with: cpuPowerView),
            NSMenuItem.separator(),
            makeItem(with: superClusterView),
            makeItem(with: superRow1View),
            makeItem(with: superRow2View),
            makeItem(with: effClusterView),
            makeItem(with: effRow1View),
            makeItem(with: effRow2View),
            makeItem(with: effRow3View),
            NSMenuItem.separator(),
            makeActivityMonitorItem(tag: 1),
            makeQuitItem()
        ]

        for item in items {
            menu.addItem(item)
        }

        superRow1View.setCores(c1Label: "S1:", c1Val: "…%", c2Label: "S2:", c2Val: "…%")
        superRow2View.setCores(c1Label: "S3:", c1Val: "…%", c2Label: "S4:", c2Val: "…%")
        effRow1View.setCores(c1Label: "E1:", c1Val: "…%", c2Label: "E2:", c2Val: "…%")
        effRow2View.setCores(c1Label: "E3:", c1Val: "…%", c2Label: "E4:", c2Val: "…%")
        effRow3View.setCores(c1Label: "E5:", c1Val: "…%", c2Label: "E6:", c2Val: "…%")

        self.cpuMenu = menu
    }

    private func buildGPUMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let items: [NSMenuItem] = [
            makeItem(with: gpuUsageView),
            makeItem(with: gpuTempView),
            makeItem(with: gpuHotspotView),
            NSMenuItem.separator(),
            makeActivityMonitorItem(tag: 2),
            makeQuitItem()
        ]

        for item in items {
            menu.addItem(item)
        }

        self.gpuMenu = menu
    }

    private func buildRAMMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        var items: [NSMenuItem] = [
            makeItem(with: ramTotalView),
            makeItem(with: ramAppView),
            makeItem(with: ramWiredView),
            makeItem(with: ramCompressedView),
            makeItem(with: ramCacheView),
            makeItem(with: ramFreeView),
            NSMenuItem.separator(),
            makeItem(with: topProcessHeaderView)
        ]

        for view in topProcessViews {
            items.append(makeItem(with: view))
        }

        items.append(NSMenuItem.separator())
        items.append(makeActivityMonitorItem(tag: 3))
        items.append(makeQuitItem())

        for item in items {
            menu.addItem(item)
        }

        self.ramMenu = menu
    }

    // MARK: - Apertura Monitoraggio Attività

    @objc private func openActivityMonitor(_ sender: NSMenuItem) {
        let tag = sender.tag
        DispatchQueue.global(qos: .userInitiated).async {
            let script: String
            switch tag {
            case 1: // CPU (Scheda 1)
                script = """
                tell application "Activity Monitor" to activate
                try
                    tell application "System Events"
                        repeat 10 times
                            if exists (window 1 of process "Activity Monitor") then exit repeat
                            delay 0.1
                        end repeat
                        tell process "Activity Monitor"
                            repeat with w in windows
                                if exists toolbar 1 of w then
                                    perform action "AXRaise" of w
                                    click radio button 1 of radio group 1 of group 1 of toolbar 1 of w
                                    exit repeat
                                end if
                            end repeat
                        end tell
                    end tell
                end try
                """
            case 2: // GPU (Cronologia GPU / Scheda CPU)
                script = """
                tell application "Activity Monitor" to activate
                try
                    tell application "System Events"
                        repeat 10 times
                            if exists (window 1 of process "Activity Monitor") then exit repeat
                            delay 0.1
                        end repeat
                        tell process "Activity Monitor"
                            repeat with w in windows
                                if exists toolbar 1 of w then
                                    perform action "AXRaise" of w
                                    click radio button 1 of radio group 1 of group 1 of toolbar 1 of w
                                    exit repeat
                                end if
                            end repeat
                            try
                                click menu item "Cronologia GPU" of menu 1 of menu bar item "Finestra" of menu bar 1
                            on error
                                try
                                    click menu item "GPU History" of menu 1 of menu bar item "Window" of menu bar 1
                                on error
                                    keystroke "4" using command down
                                end try
                            end try
                        end tell
                    end tell
                end try
                """
            case 3: // RAM (Scheda 2 - Memoria)
                script = """
                tell application "Activity Monitor" to activate
                try
                    tell application "System Events"
                        repeat 10 times
                            if exists (window 1 of process "Activity Monitor") then exit repeat
                            delay 0.1
                        end repeat
                        tell process "Activity Monitor"
                            repeat with w in windows
                                if exists toolbar 1 of w then
                                    perform action "AXRaise" of w
                                    click radio button 2 of radio group 1 of group 1 of toolbar 1 of w
                                    exit repeat
                                end if
                            end repeat
                        end tell
                    end tell
                end try
                """
            default:
                script = "tell application \"Activity Monitor\" to activate"
            }
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }

    // MARK: - Aggiornamento Dettagli On-Demand

    func updateCPUMenu() {
        if let c = cpuCollector.readDetailed() {
            cpuTotalView.value = "\(c.totalPercent)%"
            superClusterView.value = "\(c.superClusterPercent)%"
            effClusterView.value = "\(c.efficiencyClusterPercent)%"

            let cores = c.corePercents
            // Indici 0..5 = Efficiency (E1..E6), indici 6..9 = Super (S1..S4)
            if cores.count >= 10 {
                superRow1View.setCores(
                    c1Label: "S1:", c1Val: "\(cores[6])%",
                    c2Label: "S2:", c2Val: "\(cores[7])%"
                )
                superRow2View.setCores(
                    c1Label: "S3:", c1Val: "\(cores[8])%",
                    c2Label: "S4:", c2Val: "\(cores[9])%"
                )
                effRow1View.setCores(
                    c1Label: "E1:", c1Val: "\(cores[0])%",
                    c2Label: "E2:", c2Val: "\(cores[1])%"
                )
                effRow2View.setCores(
                    c1Label: "E3:", c1Val: "\(cores[2])%",
                    c2Label: "E4:", c2Val: "\(cores[3])%"
                )
                effRow3View.setCores(
                    c1Label: "E5:", c1Val: "\(cores[4])%",
                    c2Label: "E6:", c2Val: "\(cores[5])%"
                )
            }
        } else {
            cpuTotalView.value = "…"
        }

        if let t = thermalCollector.readCPUThermal() {
            cpuTempView.value = String(format: "%.0f °C", t.averageCelsius)
            cpuHotspotView.value = String(format: "%.0f °C", t.hotspotCelsius)
        } else {
            cpuTempView.value = "N/A"
            cpuHotspotView.value = "N/A"
        }

        if let watts = powerCollector.readSystemWatts() {
            cpuPowerView.value = String(format: "%.1f W", watts)
        } else {
            cpuPowerView.value = "N/A"
        }
    }

    func updateGPUMenu() {
        if let g = gpuCollector.readDetailed() {
            gpuUsageView.value = "\(g.deviceUtilizationPercent)%"
        } else {
            gpuUsageView.value = "N/A"
        }

        if let t = thermalCollector.readGPUThermal() {
            gpuTempView.value = String(format: "%.0f °C", t.averageCelsius)
            gpuHotspotView.value = String(format: "%.0f °C", t.hotspotCelsius)
        } else {
            gpuTempView.value = "N/A"
            gpuHotspotView.value = "N/A"
        }
    }

    func updateRAMMenu() {
        if let r = ramCollector.readDetailed() {
            let totalGB = Double(r.totalBytes) / (1024.0 * 1024.0 * 1024.0)
            let usedGB = Double(r.usedBytes) / (1024.0 * 1024.0 * 1024.0)
            ramTotalView.value = String(format: "%.1f / %.1f GB (%d%%)", usedGB, totalGB, r.usedPercent)
            ramAppView.value = Self.formatGB(r.appBytes)
            ramWiredView.value = Self.formatGB(r.wiredBytes)
            ramCompressedView.value = Self.formatGB(r.compressedBytes)
            ramCacheView.value = Self.formatGB(r.cachedFilesBytes)
            ramFreeView.value = Self.formatGB(r.freeBytes)
        } else {
            ramTotalView.value = "…"
        }

        let top = processCollector.readTopProcesses()
        for i in 0..<5 {
            if i < top.count {
                let p = top[i]
                topProcessViews[i].label = Self.truncateName(p.name, maxLength: 18)
                topProcessViews[i].value = String(format: "%.0f MB", p.footprintMB)
            } else {
                topProcessViews[i].label = "-"
                topProcessViews[i].value = "-"
            }
        }
    }

    private func updateActiveMenu() {
        guard let menu = activeMenu else { return }
        if menu === cpuMenu {
            updateCPUMenu()
        } else if menu === gpuMenu {
            updateGPUMenu()
        } else if menu === ramMenu {
            updateRAMMenu()
        }
    }

    // MARK: - NSMenuDelegate (Timer On-Demand a 1.0s)

    func menuWillOpen(_ menu: NSMenu) {
        activeMenu = menu
        adjustedMenuWindowNumber = nil

        autoreleasepool {
            updateActiveMenu()
        }

        detailTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            autoreleasepool {
                self?.updateActiveMenu()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.detailTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        detailTimer?.invalidate()
        detailTimer = nil
        activeMenu = nil
        adjustedMenuWindowNumber = nil

        thermalCollector.releaseResources()
        powerCollector.releaseResources()

        onMenuClosed?()
    }
}
