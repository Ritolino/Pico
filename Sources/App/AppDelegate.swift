import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cpuCollector = CPUCollector()
    private let gpuCollector = GPUCollector()
    private let ramCollector = RAMCollector()

    private let cpuFormatter = StatusItemFormatter(label: "CPU")
    private let gpuFormatter = StatusItemFormatter(label: "GPU")
    private let ramFormatter = StatusItemFormatter(label: "RAM")

    private var cpuItem: NSStatusItem!
    private var gpuItem: NSStatusItem!
    private var ramItem: NSStatusItem!

    private var menuController: MenuController!
    private var barTimer: DispatchSourceTimer?
    private let updateManager = UpdateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = MenuController(
            cpu: cpuCollector,
            gpu: gpuCollector,
            ram: ramCollector
        )

        updateManager.onUpdateStateChanged = { [weak self] release, isDownloading in
            self?.menuController.setAvailableUpdate(release, isDownloading: isDownloading)
        }
        menuController.onUpdateItemClicked = { [weak self] in
            self?.updateManager.presentUpdatePrompt()
        }

        setupStatusItems()
        startBarTimer()
        setupSleepWakeObservers()

        // Registrazione automatica login item solo al primo avvio in /Applications (o ripristino post-update)
        LoginItemManager.registerIfFirstLaunchInApplications()
        LoginItemManager.restoreAfterUpdateIfNeeded()

        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--simulate-update"), idx + 1 < args.count {
            updateManager.setSimulatedUpdate(version: args[idx + 1])
        } else {
            updateManager.scheduleInitialCheckIfAllowed()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateManager.cancelPendingChecks()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        barTimer?.cancel()
        barTimer = nil
    }

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleWillSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        // Rilascia le risorse IOKit prima dello sleep per prevenire handle stale
        pico_release_gpu_service()
    }

    @objc private func handleDidWake(_ notification: Notification) {
        // Al risveglio aggiorna immediatamente la barra senza attendere il tick da 3.0s
        autoreleasepool {
            updateBarItems()
        }
        updateManager.scheduleWakeCheckIfDue()
    }

    private func setupStatusItems() {
        let statusBar = NSStatusBar.system

        // Creazione in ordine RAM, GPU, CPU in modo che macOS
        // posizioni gli elementi da sinistra a destra come CPU | GPU | RAM
        ramItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        ramItem.autosaveName = "Pico_RAM"
        ramItem.menu = menuController.ramMenu
        ramItem.button?.imagePosition = .imageOnly

        gpuItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        gpuItem.autosaveName = "Pico_GPU"
        gpuItem.menu = menuController.gpuMenu
        gpuItem.button?.imagePosition = .imageOnly

        cpuItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        cpuItem.autosaveName = "Pico_CPU"
        cpuItem.menu = menuController.cpuMenu
        cpuItem.button?.imagePosition = .imageOnly

        // Ad ogni apertura o refresh (1.0s) del menu aperto, aggiorna tutte le icone in barra
        // mantenendo il tab aperto 100% coerente con il valore mostrato sotto.
        menuController.onMenuDidRefresh = { [weak self] syncReading in
            self?.updateBarItems(syncReading: syncReading)
        }

        // Assegna stato iniziale (pending "…" per CPU, lettura istantanea per GPU e RAM)
        updateBarItems()
    }

    private func startBarTimer() {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.schedule(
            deadline: .now() + AppConfig.barUpdateInterval,
            repeating: AppConfig.barUpdateInterval,
            leeway: .milliseconds(AppConfig.timerLeewayMilliseconds)
        )
        timer.setEventHandler { [weak self] in
            guard let self, !self.menuController.isAnyMenuOpen else { return }
            autoreleasepool {
                self.updateBarItems()
            }
        }
        timer.resume()
        self.barTimer = timer
    }

    private func updateBarItems(syncReading: MenuController.MenuBarSyncReading? = nil) {
        let cpuPct: Int?
        let gpuPct: Int?
        let ramPct: Int?

        switch syncReading {
        case .cpu(let activeCPU):
            cpuPct = activeCPU
            gpuPct = gpuCollector.readTotalPercent()
            ramPct = ramCollector.readTotalPercent()
        case .gpu(let activeGPU):
            cpuPct = cpuCollector.readTotalPercent()
            gpuPct = activeGPU
            ramPct = ramCollector.readTotalPercent()
        case .ram(let activeRAM):
            cpuPct = cpuCollector.readTotalPercent()
            gpuPct = gpuCollector.readTotalPercent()
            ramPct = activeRAM
        case .none:
            // A menu aperto il refresh della barra è guidato esclusivamente dal timer a 1.0s di MenuController
            guard !menuController.isAnyMenuOpen else { return }
            cpuPct = cpuCollector.readTotalPercent()
            gpuPct = gpuCollector.readTotalPercent()
            ramPct = ramCollector.readTotalPercent()
        }

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.allowsImplicitAnimation = false
        defer { NSAnimationContext.endGrouping() }

        let newCpuImg = cpuFormatter.image(for: cpuPct)
        if cpuItem.button?.image !== newCpuImg {
            cpuItem.button?.image = newCpuImg
        }

        let newGpuImg = gpuFormatter.image(for: gpuPct)
        if gpuItem.button?.image !== newGpuImg {
            gpuItem.button?.image = newGpuImg
        }

        let newRamImg = ramFormatter.image(for: ramPct)
        if ramItem.button?.image !== newRamImg {
            ramItem.button?.image = newRamImg
        }
    }
}
