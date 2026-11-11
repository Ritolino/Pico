# CHANGELOG.md — Registro delle Modifiche

## [1.1.0] — 2026-11-11 (Portabilità Cross-Chip M1–M5, Menu RAM Allineato, CLI JSON & Batteria Dual-Loop)

### Aggiunto & Migliorato
- **Stato Termico di Sistema (`Thermal State:`)**: aggiunta nel menu CPU e in `--dump-metrics` la lettura on-demand di `ProcessInfo.processInfo.thermalState` (`Nominal` / `Fair` / `Serious` / `Critical`) per identificare immediatamente condizioni di throttling su qualsiasi Mac M1–M5+.
- **Discovery Dinamica Sensori Termici M1–M5 + Fallback `IOHID`**: scoperta automatica delle chiavi `AppleSMC` (`TVC0`/`TCXC`/`TC0P`/`Tp*`/`Te*`/`Ta*`/`Tc*` per CPU, `TVG0`/`Tg*` per GPU, tipi `flt ` e `sp78`) senza allocazioni heap (`array statici BSS`), con fallback automatico a `IOHIDEventSystemClient` via `dlopen`/`dlsym` e ricerca estesa potenza (`PSTR` / `PPBR` / `PDTR`).
- **Topologia Cluster Dinamica M1–M5**: menu CPU e stampa CLI `--dump-metrics` adattivi per numero di core e nomi cluster reali (`Performance` su M1–M4, `Super` su M5, `Efficiency` su tutte le generazioni, inclusa gestione sicura di cluster dispari in `MenuDualCoreRowView`).
- **Modalità CLI JSON (`--json` / `--dump-metrics --json`)**: esportazione immediata da terminale di metriche hardware, CPU, GPU, RAM e Top 5 processi in JSON strutturato per script e automazioni (zero impatto sull'app in barra).
- **Bundle Version Allineato (`1.1.0`)**: aggiornato `Resources/Info.plist` (`CFBundleShortVersionString = 1.1.0`, `CFBundleVersion = 2`).
- **Documentazione Batteria Dual-Loop, Gatekeeper & UX Primo Avvio**:
  - Potenziati `README.md` e `README.it.md` con badge `Battery Impact: Zero Drain`, dettaglio esplicito del Dual-Loop (`3.0 s` + `500 ms` leeway a riposo con `0.26 s` CPU/minuto vs `1.0 s` solo a menu aperto), riga comparativa dedicata e FAQ per autonomia batteria.
  - Aggiunte nei README le istruzioni per build ad-hoc su macOS Sequoia / Tahoe (**Impostazioni di Sistema → Privacy e Sicurezza → Apri comunque**, fallback Sonoma e `xattr -dr com.apple.quarantine`) e rimozione preventiva della quarantena in `Scripts/install.sh`.

### Risolto & Ottimizzato (Menu RAM & LaunchServices)
- **Allineamento Menu RAM ad Activity Monitor (`Swap Used` + `Cached Files`, `DEC-021`, `DEC-022`, `BUG-006`)**:
  - Aggiunta la metrica in tempo reale **`Swap Used:`** via syscall C in-process `sysctlbyname("vm.swapusage")` (< 1 µs, zero sottoprocessi) con formattazione dinamica (`0.00 GB`, `%.0f MB` se < 1 GB, `%.2f GB` se >= 1 GB).
  - Sostituita nel menu a discesa RAM la voce `Free Memory:` con **`Cached Files:`** (`(external_pages + purgeable_pages) * page_size`, già calcolata da `RAMCollector` a zero syscall extra), posizionata sopra `Swap Used:`, eliminando l'apparente discrepanza visiva rispetto ad Activity Monitor (mantenuto `Free:` nel dump diagnostico CLI `--dump-metrics`).
- **Risoluzione Duplicato Icona / App Fantasma in Spotlight e Raycast**:
  - Aggiornato `Scripts/install.sh` con deregistrazione proattiva di `build/Pico.app` dal database LaunchServices (`lsregister -u`), eliminazione quarantena (`xattr -dr com.apple.quarantine`) e registrazione forzata di `/Applications/Pico.app` (`lsregister -f`).

## [1.0.0] — 2026-11-09 (Fase 8: Chiusura Progetto, Icona Applicazione e Consegna Finale v1.0)

### Aggiunto & Completato
- **Ricostruzione Vettoriale del Logo ("The Gauge – Variante 1")**:
  - Spostata la bozza concettuale originale in `Progetto/design/Icona minimalista di un misuratore a matita.png`.
  - Ricostruzione geometrica pura senza auto-trace: artboard 1024x1024, contenitore squircle macOS concentrico, dial e settori circolari a coordinate esatte.
  - Generati 3 file SVG con gruppi semantici separati (`<g id="contenitore">`, `<g id="quadrante">`, `<g id="settori-colorati">`, `<g id="lancetta">`, `<g id="perno-centrale">`, `<g id="dettagli-decorativi">`):
    - `pico_gauge_master.svg`: sorgente vettoriale completo modificabile.
    - `pico_gauge_clean.svg`: silhouette squircle pura con sfondo trasparente, ottimizzata per piccole dimensioni e retina icon.
    - `pico_gauge_illustrated.svg`: estetica taccuino di Leonardo da Vinci, tratto a matita, assi cartesiani e cerchi di costruzione.
    - `pico_gauge_variant_b.svg`: variante alternativa con semicerchio inferiore diviso in 3 sottoblocchi.
  - Esportati i render ad alta risoluzione PNG (1024px e 512px) e tavole di verifica comparativa e multi-scala (`pico_gauge_comparison.png` e `pico_gauge_multi_scale.png`) salvati in `GitHub/assets/` e `Progetto/design/`.
- **Icona Applicazione Nativa macOS (`AppIcon.icns`)**:
  - Generato il pacchetto di icone multi-risoluzione Retina standard da 16x16 a 1024x1024 (`Resources/AppIcon.icns`) a partire dall'artwork originale minimalista.
  - Configurato `CFBundleIconFile` in `Resources/Info.plist`.
  - Aggiornato `Scripts/build.sh` per copiare automaticamente le risorse in `Contents/Resources/` e garantire la firma ad-hoc del bundle completo.
  - Salvato l'asset originale in `Progetto/design/` e il badge grafico promozionale in `GitHub/assets/app_icon.png`.
- **Finalizzazione Documentazione di Handover (`Progetto/`)**:
  - Allineati tutti i documenti di ingegneria (`SPECIFICATIONS.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `STATUS.md`, `DECISIONS.md`, `TESTING.md`, `RISKS_AND_BUGS.md`).
  - Redatta la checklist operativa di rodaggio per le prime settimane in `Progetto/STATUS.md` a beneficio delle conversazioni **Bugfix** e **Nuove Funzioni**.
- **Perfezionamento Geometrico Stile "Test 2 Marcato" (`DEC-020`)**:
  - Rimossi gli assi ortogonali cartesiani per conferire massima dinamicità e pulizia visiva.
  - Integrate le 4 tacche radiali a 45° su tutti i settori del quadrante (incluso il settore Azzurro GPU in alto a destra).
  - Calibrata la lancetta inclinando l'angolo a 39.5° (2° in basso rispetto a 41.5°) per distanziarla armoniosamente dalla diagonale a 45°.
  - Rigenerati tutti i file SVG, PNG e ricompilato il bundle `Resources/AppIcon.icns` (946 KB), attivo in `/Applications/Pico.app`.
- **Riorganizzazione Architetturale a 2 Macro-Cartelle (`GitHub/` e `Progetto/`)**:
  - Eliminati i doppioni `README.md` e `README_IT.md` dalla root directory: la cartella principale ospita unicamente `AGENTS.md`, `Progetto/` e `GitHub/`.
  - Racchiuso l'intero pacchetto pubblico autonomo all'interno di `GitHub/`: codice sorgente (`GitHub/Sources/`), risorse del bundle (`GitHub/Resources/`), script di installazione (`GitHub/Scripts/`), asset grafici (`GitHub/assets/`), licenza (`GitHub/LICENSE`) e configurazione `.gitignore` (`GitHub/.gitignore`).
  - Confinati tutti gli script di laboratorio e diagnostica interna in `Progetto/scripts/` (`measure.sh`, `dump_sensors.sh`, `soak_test.sh`, `generate_vector_logo.swift`).
  - Creata la documentazione pubblica di ingegneria trasparente `GitHub/docs/BENCHMARKS_AND_DESIGN.md` con analisi dettagliata di benchmark reali a 15 MB, 0.0% CPU, 0 leak, confronto con Stats/iStat Menus, punti di forza e limiti noti su Apple Silicon.
- **Predisposizione Release Pubblica (`GitHub/`)**:
  - Finalizzati i README bilingue (`GitHub/README.md` e `GitHub/README.it.md`), `LICENSE` (MIT) e la cartella `GitHub/assets/`.
  - Allineata la struttura e la tipografia agli standard di **WhisperStudio** e **AeroSpot**: tabelle System Requirements, tabella comparativa benchmark (*Pico vs Stats vs iStat Menus*), e FAQ ottimizzate per l'indicizzazione e raccomandazione da parte dei modelli linguistici IA (AEO/GEO).
  - Inclusione di `GitHub/CHANGELOG.md` all'interno del pacchetto pubblico autonomo.

---

## [0.1.0-phase7] — 2026-11-09 (Fase 7: Prova di Durata, Soak Test e Gestione Sleep/Wake)

### Aggiunto
- **Tool di Prova di Durata (`Scripts/soak_test.sh`)**:
  - Script automatico di campionamento non invasivo per monitorare nel tempo `phys_footprint`, `RSS`, `%CPU`, `CPU Time` e `leaks`.
  - Esportazione continua dei dati su file CSV (`Progetto/logs/soak_test_data.csv`) e generazione automatica del report di conformità agli SLO (`Progetto/logs/soak_test_report.txt`).
- **Gestione del Ciclo Sleep/Wake (`AppDelegate.swift`)**:
  - Registrazione degli observer su `NSWorkspace.willSleepNotification` e `NSWorkspace.didWakeNotification`.
  - Prima dello sleep, rilascio preventivo del servizio IOKit `AGXAcceleratorG17G` tramite `pico_release_gpu_service()` per evitare handle stale.
  - Al risveglio, aggiornamento immediato della barra dei menu tramite `updateBarItems()` in `autoreleasepool` senza attendere il tick del timer da 3.0s.
- **Validazione e Risultati (`TEST-07`)**:
  - Esecuzione soak test su `/Applications/Pico.app`:
    - Footprint: iniziale `15 MB`, finale `15 MB`, picco `15 MB`, deriva **`0 MB`**.
    - Leaks: **`0 leaks`**.
    - Tempo CPU consumato: **`0.25 s`** su 60s totali.
    - Esito: **`[PASS]`**.

---

## [0.1.0-ui-gap-and-order] — 2026-11-09 (Risoluzione Menu Gap, Tipografia 10.5pt, Ordine CPU-GPU-RAM e Pulizia Menu)

### Risolto & Migliorato
- **Ottimizzazione Memoria a Lungo Termine (`DEC-017`)**:
  - Eliminato l'accumulo di `~30 MB` di memoria grafica dovuto alla rasterizzazione cumulativa di 300 `NSImage` preallocate in `StatusItemFormatter`.
  - Architettura migrata a **singola istanza dinamica attiva**: se la percentuale non cambia, non avviene alcuna allocazione; se cambia, viene creata la nuova immagine e la precedente (con il rispettivo buffer `CGImage`) viene rilasciata e distrutta all'istante.
  - Memoria `CG Image` ridotta da `11 MB` a soli **`384 KB`**, con footprint a regime inchiodato a **`15 MB`** anche dopo ore di esecuzione ininterrotta.
- **Risoluzione Bug "Menu Gap" su Notch Display (`BUG-004`)**:
  - Eliminato completamente il distacco verticale di ~16 pixel tra la barra superiore e i menu aperti (`NSPopupMenuWindow`).
  - Implementato riallineamento dinamico via `NSWindow.didUpdateNotification` in `MenuController.swift`: trasla verso l'alto la finestra del menu fino ad ancorarla a filo con `screen.visibleFrame.maxY`, risultando perfettamente attaccata al bordo inferiore della barra come la Batteria di sistema.
- **Tipografia Percentuali Ingrandita (10.5 pt)**:
  - Percentuali numeriche in barra aumentate da `10.0 pt` a `10.5 pt medium` monospaziate, mantenendo intatte le etichette `CPU`, `GPU`, `RAM` a `7.0 pt bold`.
  - Larghezza template incrementata da `30.0 pt` a `32.0 pt` in `AppConfig.swift` per accogliere `"100%"` (30.8 pt) con margini equilibrati e zero clipping o jitter.
- **Ordine Standard Deterministico (`CPU | GPU | RAM`)**:
  - Sequenza di istanziazione in `AppDelegate.swift` configurata come `ramItem`, `gpuItem`, `cpuItem`, garantendo l'inserimento ordinato da sinistra a destra come `CPU`, `GPU`, `RAM`.
- **Rimozione Voci di Menu "Launch at Login"**:
  - Rimosse le voci di menu superflue da tutti e tre i menu (`CPU`, `GPU`, `RAM`), preservando un layout essenziale ed elegante.
  - L'avvio al login rimane gestito in automatico al primo avvio in `/Applications/` e tramite `Scripts/install.sh`.

---

## [0.1.0-phase6] — 2026-11-09 (Fase 6: Avvio al Login via SMAppService e Script install.sh)

### Aggiunto
- **Gestore Avvio al Login (`LoginItemManager.swift`)**:
  - Integrazione nativa dell'API `SMAppService.mainApp` di macOS (Ventura, Sonoma, Sequoia, Tahoe / 27.2).
  - Registrazione automatica al primo avvio quando il bundle viene eseguito da `/Applications/Pico.app` (tracciata su `UserDefaults`).
  - Metodi `status`, `isEnabled`, `toggle()` e descrizioni per diagnosticare gli stati `.enabled`, `.requiresApproval`, `.notRegistered` e `.notFound`.
- **Voci di Menu con Spunta Nativa**:
  - Aggiunta in ciascuno dei 3 menu nativi (`CPU`, `GPU`, `RAM`) la voce interattiva `"Avvia al login"` sopra `Esci da Pico`.
  - Sincronizzazione automatica all'apertura del menu (`menuWillOpen`) dello stato della spunta `✓` (`NSControl.StateValue.on` / `.off`) con lo stato reale registrato dal sistema.
- **Script di Installazione `Scripts/install.sh`**:
  - Compilazione automatica ottimizzata, terminazione ordinata delle istanze attive, copia del bundle in `/Applications/Pico.app`, firma ad-hoc e avvio dell'app installata.
- **Supporto CLI Diagnostico e di Test**:
  - Flag `--test-login-item`: verifica istantanea del bundle e dello stato di `SMAppService.mainApp`.
  - Flag `--toggle-login-item`: test deterministico di commutazione on/off senza interfaccia grafica.
- **Validazione e Risultati**:
  - `TEST-08`: verifica positiva della registrazione in Background Task Management (`sfltool dumpbtm`) con `Disposition: [enabled, allowed, notified]`.
  - Memoria reale in esecuzione da `/Applications`: **`15 MB`** di `phys_footprint`, **`0.0%` CPU**, **`0` leak**.

---

## [0.1.0-ui-polish] — 2026-11-08 (Restyling Grafico Menu, Contrasto Elevato, Pillola Centrata e Monitoraggio Attività)

### Aggiunto & Migliorato
- **Centratura Ottica e Gerarchia Icone Barra**:
  - Etichette (`CPU`, `GPU`, `RAM`) ridotte a `7.0 pt bold`, mentre le percentuali sono state ingrandite a `10.0 pt medium` per renderle immediatamente leggibili a colpo d'occhio.
  - Centratura ottica perfettamente bilanciata verticalmente (y=1.0 etichetta, y=9.0 percentuale con margini simmetrici sopra e sotto): il centro delle scritte è allineato al pixel con il centro di tutte le altre icone di sistema (Batteria, WiFi, Control Center).
- **Risoluzione Sfarfallio e Glitch GPU**:
  - Bloccata la modifica dell'immagine del pulsante della barra mentre il menu è aperto (`isAnyMenuOpen`), azzerando qualsiasi sfarfallio o artefatto grafico di split nella pillola durante la consultazione del menu.
  - Aggiunto confronto puntatori (`!==`) per evitare ridisegni ridondanti dell'icona.
- **Allineamento a Filo Sinistro nei Dettagli (CPU e RAM)**:
  - Eliminata ogni indentazione artificiale a "tabulazione": tutti i core CPU (`S1..S4`, `E1..E6`) e tutte le voci secondarie della RAM (`App`, `Wired`, `Compressa`, `File in cache`, `Memoria Libera`, Top 5 processi) sono rigorosamente allineati a sinistra a `x = 14.0 pt`.
- **Pillola di Selezione Simmetrica**:
  - Eliminata l'asimmetria del padding nello stato di selezione: gli `NSStatusItem` usano ora `withLength: NSStatusItem.variableLength` combinato con un'immagine template di dimensioni calibrate a `30.0 × 22.0 pt` (`button.imagePosition = .imageOnly`). La capsula di evidenziazione assume un padding perfettamente simmetrico di `8.0 pt` a sinistra e a destra, speculare alla Batteria nativa di macOS.
- **Viste Custom Menu ad Alto Contrasto (`MenuViews.swift`)**:
  - `MenuRowView`: renderizza direttamente su CoreGraphics (`draw(_:)`) etichette in grigio secondario Apple (`secondaryLabelColor`) o bianco pieno semibold (`labelColor` per intestazioni) allineate a sinistra, e valori numerici in bianco pieno ad alto contrasto con font monospaziato per cifre (`monospacedDigitSystemFont`, peso `.medium`), ancorati esattamente al margine destro (`bounds.width - 14 - valueWidth`).
  - `MenuDualCoreRowView`: scomposizione CPU core su 2 colonne impeccabilmente allineate (`S1..S4` ed `E1..E6`), eliminando stringhe monospaziate clunky e spazi vuoti a destra.
  - Zero opacità "semi-trasparente": superato il limite di AppKit `disabledControlTextColor`.
- **Integrazione Monitoraggio Attività**:
  - Aggiunta in ciascun menu la voce `Apri Monitoraggio Attività…`.
  - Esecuzione asincrona in background (`NSAppleScript` senza blocchi del thread principale):
    - Da menu CPU: attiva Monitoraggio Attività e seleziona la scheda CPU.
    - Da menu GPU: attiva Monitoraggio Attività e porta in primo piano la finestra "Cronologia GPU" (Window / Cmd+4).
    - Da menu RAM: attiva Monitoraggio Attività e seleziona la scheda Memoria.
- **Validazione**:
  - `TEST-06` (Run #3): 50 cicli completi su tutti i menu con delta memoria `0 KB` e **0 leaks**.

---

## [0.1.0-phase5] — 2026-11-08 (Fase 5: Menu RAM Top 5 Processi e Riposizionamento Barra)

### Aggiunto
- **Scansione In-Process dei Top 5 Processi RAM**:
  - `Sources/CShim/CShim.c` e `CShim.h`: `pico_read_top_processes` interroga i PID del sistema tramite `proc_listpids` usando un buffer statico di 2048 elementi (`pid_t`, zero allocazioni heap).
  - Valutazione dell'impronta fisica reale (`ri_phys_footprint`) tramite `proc_pid_rusage(RUSAGE_INFO_V4)` e inserimento ordinato in-place dei Top 5 (durata totale scansione: < 2 millisecondi).
  - Risoluzione dei nomi processo (`proc_name`) ristretta unicamente ai 5 PID finali per azzerare l'overhead.
  - Getter scalari thread-safe in C (`pico_get_top_process_pid`, `_footprint`, `_name`) per il passaggio sicuro al runtime Swift.
  - `Sources/Metrics/ProcessCollector.swift`: wrapper Swift ad alto livello.
- **Menu RAM Completo**:
  - Popolato il menu nativo `RAM` con `RAM Usata (Formula A)`, scomposizione `App`, `Wired`, `Compressa`, `File in cache`, `Memoria Libera` e lista dei **Top 5 processi** in `MB` con font monospaziato e nomi troncati con ellissi (`…`).
  - Aggiornamento on-demand collegato al timer secondario a `1.0 s` attivo solo a menu aperto.
- **Riposizionamento Verticale Icone in Barra dei Menu**:
  - Risolto il problema delle etichette posizionate troppo in alto: migrato `StatusItemFormatter` da `attributedTitle` a template `NSImage(size: 36x22, flipped: true)` preallocati (101 stati per percentuale `0%..100%`, `…` e `n/d`).
  - Centratura verticale perfetta allineata con tutte le altre icone di sistema (Control Center, WiFi, Batteria, Data/Ora) e generoso respiro superiore e inferiore.
- **Validazione e Test Ripetibili**:
  - Esteso `--stress-menus [N]` al menu RAM: dopo 50 cicli completi su tutti e 3 i menu (CPU, GPU, RAM), delta memoria di soli `+16 KB` e **0 leaks**.
- **Decisioni Architetturali**:
  - Documentate `DEC-010` e `DEC-011` in `docs/dev/DECISIONS.md`.

---

## [0.1.0-phase4] — 2026-11-08 (Fase 4: Dettagli al Click per CPU e GPU su Menu Nativo)

### Aggiunto
- **Dump e Mappatura Sensori Apple M5**:
  - Script diagnostico `Scripts/dump_sensors.sh` che raccoglie in `docs/dev/logs/` i dati grezzi da `IOHIDEventSystemClient` (`m5_hid_thermal.txt`), `AppleSMC` (`m5_smc_keys.txt`) e `IOReport` (`m5_ioreport.txt`).
  - Mappatura empirica confermata senza root tramite interfaccia IOKit `AppleSMC` (`KERNEL_INDEX_SMC = 2`): potenza totale di sistema via chiave `PSTR` (e fallback `PPBR`), temperatura CPU via `TVC0` e cluster core M5 (`Te*` Efficiency, `Ta*` Super, `Tp*` Performance), temperatura GPU via `TVG0` e 24 sensori di core grafico `Tg*`.
  - Calcolo algoritmico in-process del vero **Hotspot termico** (massimo tra tutti i sensori del blocco).
- **Collettori On-Demand e Menu Nativo CPU & GPU**:
  - `Sources/CShim/CShim.c` e `CShim.h`: `pico_read_cpu_thermal`, `pico_read_gpu_thermal`, `pico_read_system_power` e rilascio esplicito `pico_release_smc`.
  - `Sources/Metrics/ThermalCollector.swift` e `PowerCollector.swift`: wrapper Swift ad alto livello con gestione sicura delle risorse in `deinit`.
  - `Sources/App/MenuController.swift`: implementazione di `NSMenuDelegate` con layout monospaziato allineato (`formatRow`) per CPU (Totale, Temperatura, Hotspot, Potenza Sistema in Watt, breakdown core `Super S1..S4` e `Efficiency E1..E6`) e GPU (Utilizzo, Temperatura, Hotspot).
  - Timer secondario a `1.0 s` aggiunto al `RunLoop` principale in modalità `common` e `eventTracking`, attivo **esclusivamente** a menu aperto; chiusura automatica e rilascio immediato degli handle `AppleSMC` alla chiusura del menu.
- **Validazione e Test Ripetibili**:
  - Aggiunto flag CLI `--stress-menus [N]` in `Sources/App/main.swift` per testare la tenuta su 50 cicli completi di apertura, aggiornamento e chiusura menu (`TEST-06`).
  - Risultati `TEST-06`: delta `phys_footprint` di appena `+32 KB` (~0 B/ciclo) e **0 leaks** su 50 cicli.
- **Decisione Architetturale**:
  - Documentata `DEC-009` in `docs/dev/DECISIONS.md`.

---

## [0.1.0-phase3] — 2026-11-08 (Fase 3: Barra dei Menu a Due Righe e Timer Coalesced 3s)

### Aggiunto
- Layout a 2 righe su 3 `NSStatusItem` indipendenti (`CPU`, `GPU`, `RAM`) con font di sistema compatto per l'etichetta (`8.5 pt bold`) e cifre monospaziate per la percentuale (`10.0 pt regular`).
- Larghezza fissa calibrata a `36.0 pt` per garantire zero jitter orizzontale al passaggio `0%` -> `100%`.
- Supporto alla persistenza del riposizionamento utente (Cmd+drag) tramite `autosaveName` (`Pico_CPU`, `Pico_GPU`, `Pico_RAM`).
- Caching preallocato delle `NSAttributedString` in `StatusItemFormatter` (zero allocazioni heap sui tick del timer).
- Timer principale coalesced a `3.0 s` (`DispatchSourceTimer` con leeway `500 ms`) che esegue solo le letture in-process delle 3 percentuali dentro `autoreleasepool`.
- Tre menu nativi `NSMenu` indipendenti con titolo e voce "Esci da Pico" (`⌘Q`).
- Misure reali a regime (`T+60s`): **`16 MB`** di `phys_footprint` (**`0 MB` di deriva** rispetto a T+10s), **`0.0%` CPU**, **`0` leak**.

---

## [0.1.0-phase2] — 2026-11-08 (Fase 2: Collettori Metriche Base CPU, GPU, RAM e Suite Test)

### Aggiunto
- Collettori in-process a zero allocazioni heap sul path caldo:
  - `Sources/Metrics/CPUCollector.swift` + `CShim`: lettura `host_processor_info` con deallocazione immediata `vm_deallocate` e mappatura empirica degli indici core su Apple M5 (`0..5` = 6 core `Efficiency`, `6..9` = 4 core `Super`).
  - `Sources/Metrics/GPUCollector.swift` + `CShim`: lettura IOKit `IOAccelerator` (`AGXAcceleratorG17G` su M5) con caching dell'`io_service_t` e rilascio `CFRelease` a ogni tick.
  - `Sources/Metrics/RAMCollector.swift` + `CShim`: lettura `host_statistics64(HOST_VM_INFO64)` e validazione della Formula A (`App + Wired + Compressa`, con `App = internal - purgeable`) contro Activity Monitor.
- Flag CLI `--dump-metrics` e `--stress-metrics [N]` in `Sources/App/main.swift`.
- Documenti standardizzati `docs/TESTING.md` (protocollo ripetibile di tutti i test) e `docs/TEST_RESULTS.md` (registro storico risultati).
- Riorganizzazione documentale: file principali in `docs/` e file operativi di sviluppo/agenti in `docs/dev/`.

---

## [0.1.0-phase1] — 2026-11-08 (Fase 1: Baseline di Efficienza Swift vs Objective-C)

### Aggiunto
- App baseline da barra dei menu (`LSUIElement = YES`, 1 `NSStatusItem` con testo statico `"Pico"` e `NSMenu` con `"Esci da Pico"`) in `Sources/App/main.swift` e variante comparativa Objective-C per il benchmark.
- Script `Scripts/measure.sh` per l'acquisizione automatizzata di `ps`, `footprint` e `leaks`.
- Risultati empirici a `T+10s` e `T+60s` registrati in `docs/MEASUREMENTS.md` (`Swift`: `12 MB` `phys_footprint`, `3,705 KB` malloc heap, `0.0%` CPU, `0` leak vs `Objective-C`: `13 MB` `phys_footprint`, `4,057 KB` malloc heap).
- Decisione `DEC-006` in `docs/DECISIONS.md` (conferma `Swift + AppKit + CShim` e ricalibrazione budget RAM target a `<= 15 MB`, limite massimo `< 20 MB`).

---

## [0.1.0-phase0] — 2026-11-08 (Fase 0: Setup, Specifiche e Fondamenta)

### Aggiunto
- Ricognizione hardware e software sulla macchina target reale (`Apple M5`, 10 core divisi in 4 `Super` + 6 `Efficiency`, `16.0 GB` RAM, `macOS 27.2` build `26B123`, `Swift 6.4.2`, `clang 21.0.0`).
- Struttura repository completa (`Sources/App`, `Sources/Metrics`, `Sources/CShim`, `Resources`, `Scripts`, `docs`, `logs`, `prompts`).
- Copia di riferimento `prompts/00_MAIN_BRIEF.md`.
- Regole di coordinamento multi-conversazione in `AGENTS.md`.
- Specifiche standard e Vision del progetto in `docs/SPECIFICATIONS.md` e piano operativo in `docs/ROADMAP.md`.
- Documentazione architetturale e di tracciamento (`ARCHITECTURE.md`, `DECISIONS.md`, `STATUS.md`, `CHECKLIST.md`, `KNOWN_RISKS.md`, `MEASUREMENTS.md`, `BUGS.md`, `IDEAS.md`).
- Scheletro di compilazione C + Swift (`Sources/CShim/CShim.h`, `Sources/CShim/CShim.c`, `Sources/App/main.swift`, `Resources/Info.plist`) e script `Scripts/build.sh` con firma ad-hoc e modalità di test `--verify-build`.
