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

    /// Identifica il tab correntemente aperto per mantenere coerente la barra in alto senza doppie letture.
    enum MenuBarSyncReading {
        case cpu(Int?)
        case gpu(Int?)
        case ram(Int?)
    }

    /// Callback invocato ad ogni refresh del menu aperto (apertura iniziale + tick ogni 1.0s).
    var onMenuDidRefresh: ((MenuBarSyncReading) -> Void)?

    /// Callback invocato al click sulla voce "Update Available…" presente nei menu.
    var onUpdateItemClicked: (() -> Void)?

    private var updateMenuItems: [NSMenuItem] = []

    // Larghezza fissa uniforme per tutte le righe dei menu
    private static let menuRowWidth: CGFloat = 300.0

    // CPU Graphic Views
    private let cpuTotalView = MenuHeroView(title: "Total CPU", width: menuRowWidth)
    private let cpuTempView = MenuRowView(label: "Temperature", value: "…", width: menuRowWidth, height: 22.0)
    private let cpuHotspotView = MenuRowView(label: "CPU Hotspot", value: "…", width: menuRowWidth, height: 22.0)
    private let cpuThermalStateView = MenuRowView(label: "Thermal State", value: "…", width: menuRowWidth, height: 22.0)
    private let cpuPowerView = MenuRowView(label: "System Power", value: "…", width: menuRowWidth, height: 22.0)
    private let superClusterCard: MenuClusterView?
    private let effClusterCard: MenuClusterView?

    // GPU Graphic Views
    private let gpuUsageView = MenuHeroView(title: "GPU Usage", width: menuRowWidth)
    private let gpuTempView = MenuRowView(label: "Temperature", value: "…", width: menuRowWidth, height: 22.0)
    private let gpuHotspotView = MenuRowView(label: "GPU Hotspot", value: "…", width: menuRowWidth, height: 22.0)

    // RAM Graphic Views
    private let ramTotalView = MenuHeroView(title: "Memory Usage", hasSubtitle: true, warningThreshold: 75, criticalThreshold: 90, width: menuRowWidth)
    private let ramPressureView = MenuRowView(label: "Memory Pressure", value: "…", width: menuRowWidth, height: 22.0)
    private let ramAppView = MenuRowView(label: "App Memory", value: "…", width: menuRowWidth, height: 22.0)
    private let ramWiredView = MenuRowView(label: "Wired", value: "…", width: menuRowWidth, height: 22.0)
    private let ramCompressedView = MenuRowView(label: "Compressed", value: "…", width: menuRowWidth, height: 22.0)
    private let ramCachedView = MenuRowView(label: "Cached Files", value: "…", width: menuRowWidth, height: 22.0)
    private let ramSwapView = MenuRowView(label: "Swap Used", value: "…", width: menuRowWidth, height: 22.0)
    private let topProcessHeaderView = MenuRowView(label: "Top Processes", isHeader: true, width: menuRowWidth, height: 20.0)
    private let topProcessViews = (0..<5).map { _ in MenuRowView(label: "…", value: "…", width: menuRowWidth, height: 22.0) }

    /// Traccia l'ID della finestra del menu correntemente aperto per calibrare una sola volta la posizione verticale.
    private var adjustedMenuWindowNumber: Int?

    init(cpu: CPUCollector, gpu: GPUCollector, ram: RAMCollector) {
        self.cpuCollector = cpu
        self.gpuCollector = gpu
        self.ramCollector = ram

        let pName = cpu.superName.isEmpty ? "Performance" : cpu.superName
        let eName = cpu.efficiencyName.isEmpty ? "Efficiency" : cpu.efficiencyName
        let perfPrefix = pName.first.map { String($0).uppercased() } ?? "P"
        let effPrefix = eName.first.map { String($0).uppercased() } ?? "E"

        self.superClusterCard = cpu.superCores > 0
            ? MenuClusterView(clusterTitle: "\(pName) Cluster", corePrefix: perfPrefix, coreCount: cpu.superCores, width: Self.menuRowWidth)
            : nil
        self.effClusterCard = cpu.efficiencyCores > 0
            ? MenuClusterView(clusterTitle: "\(eName) Cluster", corePrefix: effPrefix, coreCount: cpu.efficiencyCores, width: Self.menuRowWidth)
            : nil

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

    private func makeUpdateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Update Available…",
            action: #selector(handleUpdateClicked(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.isHidden = true
        if let symbol = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Update Available") {
            symbol.isTemplate = true
            item.image = symbol
        }
        updateMenuItems.append(item)
        return item
    }

    @objc private func handleUpdateClicked(_ sender: NSMenuItem) {
        onUpdateItemClicked?()
    }

    func setAvailableUpdate(_ release: UpdateReleaseInfo?, isDownloading: Bool = false) {
        for item in updateMenuItems {
            if let release {
                item.isHidden = false
                item.title = isDownloading ? "Downloading Update…" : "Update Available (v\(release.version))…"
                item.isEnabled = !isDownloading
            } else {
                item.isHidden = true
            }
        }
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
            NSMenuItem.separator(),
            makeItem(with: cpuThermalStateView),
            makeItem(with: cpuTempView),
            makeItem(with: cpuHotspotView),
            makeItem(with: cpuPowerView),
            NSMenuItem.separator()
        ]

        if let superCard = superClusterCard {
            items.append(makeItem(with: superCard))
        }

        if superClusterCard != nil && effClusterCard != nil {
            items.append(makeItem(with: MenuSpacerView(width: Self.menuRowWidth, height: 6.0)))
        }

        if let effCard = effClusterCard {
            items.append(makeItem(with: effCard))
        }

        items.append(NSMenuItem.separator())
        items.append(makeUpdateMenuItem())
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
            NSMenuItem.separator(),
            makeItem(with: gpuTempView),
            makeItem(with: gpuHotspotView),
            NSMenuItem.separator(),
            makeUpdateMenuItem(),
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
            NSMenuItem.separator(),
            makeItem(with: ramPressureView),
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
        items.append(makeUpdateMenuItem())
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

    @discardableResult
    func updateCPUMenu() -> Int? {
        var cpuBarPercent: Int?
        if let c = cpuCollector.readDetailed() {
            cpuBarPercent = c.totalPercent
            cpuTotalView.update(percent: c.totalPercent)

            let cores = c.corePercents
            let effCount = cpuCollector.efficiencyCores
            let superCount = cpuCollector.superCores

            // In host_processor_info su Apple Silicon (M1..M5), gli indici 0..<effCount sono Efficiency
            // e gli indici effCount..<(effCount+superCount) sono Performance / Super.
            let superSlice: [Int?] = (0..<superCount).map { localIdx in
                let globalIdx = effCount + localIdx
                return globalIdx < cores.count ? cores[globalIdx] : nil
            }
            superClusterCard?.update(clusterPercent: c.superClusterPercent, corePercents: superSlice)

            let effSlice: [Int?] = (0..<effCount).map { localIdx in
                return localIdx < cores.count ? cores[localIdx] : nil
            }
            effClusterCard?.update(clusterPercent: c.efficiencyClusterPercent, corePercents: effSlice)
        } else {
            cpuTotalView.update(percent: nil, valueText: "…")
        }

        if let t = thermalCollector.readCPUThermal() {
            cpuTempView.value = String(format: "%.0f °C", t.averageCelsius)
            cpuHotspotView.value = String(format: "%.0f °C", t.hotspotCelsius)
        } else {
            cpuTempView.value = "N/A"
            cpuHotspotView.value = "N/A"
        }

        let thermalState = thermalCollector.readThermalStateLabel()
        cpuThermalStateView.value = thermalState
        cpuThermalStateView.valueColorOverride = MenuVisualStyle.thermalStateColor(for: thermalState)

        if let watts = powerCollector.readSystemWatts() {
            cpuPowerView.value = String(format: "%.1f W", watts)
        } else {
            cpuPowerView.value = "N/A"
        }
        return cpuBarPercent
    }

    @discardableResult
    func updateGPUMenu() -> Int? {
        let gpuBarPercent = gpuCollector.readTotalPercent()
        if let pct = gpuBarPercent {
            gpuUsageView.update(percent: pct)
        } else {
            gpuUsageView.update(percent: nil, valueText: "N/A")
        }

        if let t = thermalCollector.readGPUThermal() {
            gpuTempView.value = String(format: "%.0f °C", t.averageCelsius)
            gpuHotspotView.value = String(format: "%.0f °C", t.hotspotCelsius)
        } else {
            gpuTempView.value = "N/A"
            gpuHotspotView.value = "N/A"
        }
        return gpuBarPercent
    }

    @discardableResult
    func updateRAMMenu() -> Int? {
        var ramBarPercent: Int?
        if let r = ramCollector.readDetailed() {
            ramBarPercent = r.usedPercent
            let totalDouble = max(1.0, Double(r.totalBytes))
            let totalGB = totalDouble / (1024.0 * 1024.0 * 1024.0)
            let usedGB = Double(r.usedBytes) / (1024.0 * 1024.0 * 1024.0)
            ramTotalView.update(
                percent: r.usedPercent,
                subtitle: String(format: "%.1f of %.1f GB used", usedGB, totalGB)
            )

            ramPressureView.value = r.pressureLabel
            ramPressureView.valueColorOverride = MenuVisualStyle.memoryPressureColor(for: r.pressureLabel)

            let appFraction = Double(r.appBytes) / totalDouble
            let wiredFraction = Double(r.wiredBytes) / totalDouble
            let compressedFraction = Double(r.compressedBytes) / totalDouble
            let cachedFraction = Double(r.cachedFilesBytes) / totalDouble

            ramAppView.setBarValue(
                RAMCollector.formatGB(r.appBytes),
                fraction: appFraction,
                color: MenuVisualStyle.semanticColor(forFraction: appFraction, warningAt: 75, criticalAt: 90)
            )
            ramWiredView.setBarValue(
                RAMCollector.formatGB(r.wiredBytes),
                fraction: wiredFraction,
                color: MenuVisualStyle.semanticColor(forFraction: wiredFraction, warningAt: 75, criticalAt: 90)
            )
            ramCompressedView.setBarValue(
                RAMCollector.formatGB(r.compressedBytes),
                fraction: compressedFraction,
                color: MenuVisualStyle.semanticColor(forFraction: compressedFraction, warningAt: 75, criticalAt: 90)
            )
            ramCachedView.setBarValue(
                RAMCollector.formatGB(r.cachedFilesBytes),
                fraction: cachedFraction,
                color: .systemTeal
            )

            let activeSwapBytes: UInt64 = r.swapUsedBytes >= 1024 * 1024 ? r.swapUsedBytes : 0
            let swapFraction: Double
            if activeSwapBytes == 0 {
                swapFraction = 0.0
            } else if r.swapTotalBytes > 0 {
                swapFraction = Double(activeSwapBytes) / Double(r.swapTotalBytes)
            } else {
                swapFraction = Double(activeSwapBytes) / totalDouble
            }
            ramSwapView.setBarValue(
                RAMCollector.formatSwap(activeSwapBytes),
                fraction: swapFraction,
                color: MenuVisualStyle.semanticColor(forFraction: swapFraction, warningAt: 60, criticalAt: 85),
                dimWhenZero: true
            )
        } else {
            ramTotalView.update(percent: nil, valueText: "…", subtitle: "")
        }

        let top = processCollector.readTopProcesses()
        for i in 0..<5 {
            if i < top.count {
                let p = top[i]
                topProcessViews[i].label = Self.truncateName(p.name, maxLength: 28)
                topProcessViews[i].value = String(format: "%.0f MB", p.footprintMB)
            } else {
                topProcessViews[i].label = "-"
                topProcessViews[i].value = "-"
            }
        }
        return ramBarPercent
    }

    private func updateActiveMenu() {
        guard let menu = activeMenu else { return }
        if menu === cpuMenu {
            onMenuDidRefresh?(.cpu(updateCPUMenu()))
        } else if menu === gpuMenu {
            onMenuDidRefresh?(.gpu(updateGPUMenu()))
        } else if menu === ramMenu {
            onMenuDidRefresh?(.ram(updateRAMMenu()))
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
    }
}
