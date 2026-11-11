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
    private let cpuThermalStateView = MenuRowView(label: "Thermal State:", value: "…", width: menuRowWidth, height: 22.0)
    private let cpuPowerView = MenuRowView(label: "System Power:", value: "…", width: menuRowWidth, height: 22.0)
    private let superClusterView: MenuRowView
    private let superRowViews: [MenuDualCoreRowView]
    private let effClusterView: MenuRowView
    private let effRowViews: [MenuDualCoreRowView]
    private let perfPrefix: String
    private let effPrefix: String

    // GPU Graphic Views
    private let gpuUsageView = MenuRowView(label: "GPU Usage:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let gpuTempView = MenuRowView(label: "Temperature:", value: "…", width: menuRowWidth, height: 22.0)
    private let gpuHotspotView = MenuRowView(label: "GPU Hotspot:", value: "…", width: menuRowWidth, height: 22.0)

    // RAM Graphic Views (flush-left alignment on x = 14pt)
    private let ramTotalView = MenuRowView(label: "Used RAM:", value: "…", isHeader: true, width: menuRowWidth, height: 22.0)
    private let ramAppView = MenuRowView(label: "App Memory:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramWiredView = MenuRowView(label: "Wired:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramCompressedView = MenuRowView(label: "Compressed:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramCachedView = MenuRowView(label: "Cached Files:", value: "…", width: menuRowWidth, height: 22.0)
    private let ramSwapView = MenuRowView(label: "Swap Used:", value: "…", width: menuRowWidth, height: 22.0)
    private let topProcessHeaderView = MenuRowView(label: "Top Processes (Footprint):", isHeader: true, width: menuRowWidth, height: 22.0)
    private let topProcessViews = (0..<5).map { _ in MenuRowView(label: "…", value: "…", width: menuRowWidth, height: 22.0) }

    /// Traccia l'ID della finestra del menu correntemente aperto per calibrare una sola volta la posizione verticale.
    private var adjustedMenuWindowNumber: Int?

    init(cpu: CPUCollector, gpu: GPUCollector, ram: RAMCollector) {
        self.cpuCollector = cpu
        self.gpuCollector = gpu
        self.ramCollector = ram

        let pName = cpu.superName.isEmpty ? "Performance" : cpu.superName
        let eName = cpu.efficiencyName.isEmpty ? "Efficiency" : cpu.efficiencyName
        self.superClusterView = MenuRowView(label: "\(pName) Cluster:", value: "…", isHeader: true, width: Self.menuRowWidth, height: 22.0)
        self.effClusterView = MenuRowView(label: "\(eName) Cluster:", value: "…", isHeader: true, width: Self.menuRowWidth, height: 22.0)
        self.perfPrefix = pName.first.map { String($0).uppercased() } ?? "P"
        self.effPrefix = eName.first.map { String($0).uppercased() } ?? "E"

        let pRowCount = max(0, (cpu.superCores + 1) / 2)
        let eRowCount = max(0, (cpu.efficiencyCores + 1) / 2)
        self.superRowViews = (0..<pRowCount).map { _ in MenuDualCoreRowView(width: Self.menuRowWidth, height: 20.0) }
        self.effRowViews = (0..<eRowCount).map { _ in MenuDualCoreRowView(width: Self.menuRowWidth, height: 20.0) }

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

    private static func formatSwap(_ bytes: UInt64) -> String {
        if bytes == 0 {
            return "0.00 GB"
        }
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.0f MB", mb)
        }
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

        var items: [NSMenuItem] = [
            makeItem(with: cpuTotalView),
            makeItem(with: cpuTempView),
            makeItem(with: cpuHotspotView),
            makeItem(with: cpuThermalStateView),
            makeItem(with: cpuPowerView),
            NSMenuItem.separator()
        ]

        if cpuCollector.superCores > 0 {
            items.append(makeItem(with: superClusterView))
            for (idx, rowView) in superRowViews.enumerated() {
                let c1Num = idx * 2 + 1
                let c2Num = idx * 2 + 2
                let c2Label = c2Num <= cpuCollector.superCores ? "\(perfPrefix)\(c2Num):" : ""
                let c2Val = c2Num <= cpuCollector.superCores ? "…%" : ""
                rowView.setCores(c1Label: "\(perfPrefix)\(c1Num):", c1Val: "…%", c2Label: c2Label, c2Val: c2Val)
                items.append(makeItem(with: rowView))
            }
        }

        if cpuCollector.efficiencyCores > 0 {
            items.append(makeItem(with: effClusterView))
            for (idx, rowView) in effRowViews.enumerated() {
                let c1Num = idx * 2 + 1
                let c2Num = idx * 2 + 2
                let c2Label = c2Num <= cpuCollector.efficiencyCores ? "\(effPrefix)\(c2Num):" : ""
                let c2Val = c2Num <= cpuCollector.efficiencyCores ? "…%" : ""
                rowView.setCores(c1Label: "\(effPrefix)\(c1Num):", c1Val: "…%", c2Label: c2Label, c2Val: c2Val)
                items.append(makeItem(with: rowView))
            }
        }

        items.append(NSMenuItem.separator())
        items.append(makeActivityMonitorItem(tag: 1))
        items.append(makeQuitItem())

        for item in items {
            menu.addItem(item)
        }

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
            makeItem(with: ramCachedView),
            makeItem(with: ramSwapView),
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
            let effCount = cpuCollector.efficiencyCores
            let superCount = cpuCollector.superCores

            // In host_processor_info su Apple Silicon (M1..M5), gli indici 0..<effCount sono Efficiency
            // e gli indici effCount..<(effCount+superCount) sono Performance / Super.
            for (rowIdx, rowView) in superRowViews.enumerated() {
                let c1Local = rowIdx * 2
                let c2Local = rowIdx * 2 + 1
                let c1Global = effCount + c1Local
                let c2Global = effCount + c2Local

                let c1Label = c1Local < superCount ? "\(perfPrefix)\(c1Local + 1):" : ""
                let c1Val = (c1Local < superCount && c1Global < cores.count) ? "\(cores[c1Global])%" : "…"
                let hasSecond = (c2Local < superCount)
                let c2Label = hasSecond ? "\(perfPrefix)\(c2Local + 1):" : ""
                let c2Val = (hasSecond && c2Global < cores.count) ? "\(cores[c2Global])%" : ""

                rowView.setCores(c1Label: c1Label, c1Val: c1Val, c2Label: c2Label, c2Val: c2Val)
            }

            for (rowIdx, rowView) in effRowViews.enumerated() {
                let c1Local = rowIdx * 2
                let c2Local = rowIdx * 2 + 1

                let c1Label = c1Local < effCount ? "\(effPrefix)\(c1Local + 1):" : ""
                let c1Val = (c1Local < effCount && c1Local < cores.count) ? "\(cores[c1Local])%" : "…"
                let hasSecond = (c2Local < effCount)
                let c2Label = hasSecond ? "\(effPrefix)\(c2Local + 1):" : ""
                let c2Val = (hasSecond && c2Local < cores.count) ? "\(cores[c2Local])%" : ""

                rowView.setCores(c1Label: c1Label, c1Val: c1Val, c2Label: c2Label, c2Val: c2Val)
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

        cpuThermalStateView.value = thermalCollector.readThermalStateLabel()

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
            ramCachedView.value = Self.formatGB(r.cachedFilesBytes)
            ramSwapView.value = Self.formatSwap(r.swapUsedBytes)
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
