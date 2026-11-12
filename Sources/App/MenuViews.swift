import AppKit

// MARK: - Stile Visivo Condiviso (CoreGraphics puro, Zero Overhead a Riposo)

enum MenuVisualStyle {
    static let horizontalPadding: CGFloat = 14.0

    private static func adaptiveGray(darkAlpha: CGFloat, lightAlpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(white: 1.0, alpha: darkAlpha)
                : NSColor(white: 0.0, alpha: lightAlpha)
        }
    }

    static let barTrackColor = adaptiveGray(darkAlpha: 0.13, lightAlpha: 0.12)
    static let cardFillColor = adaptiveGray(darkAlpha: 0.045, lightAlpha: 0.045)
    static let cardHeaderFillColor = adaptiveGray(darkAlpha: 0.035, lightAlpha: 0.035)
    static let cardStrokeColor = adaptiveGray(darkAlpha: 0.10, lightAlpha: 0.11)
    static let cardDividerColor = adaptiveGray(darkAlpha: 0.08, lightAlpha: 0.09)
    static let neutralBadgeFillColor = adaptiveGray(darkAlpha: 0.09, lightAlpha: 0.08)

    static func semanticColor(for percent: Int?, warningAt: Int = 60, criticalAt: Int = 85) -> NSColor {
        guard let pct = percent, pct > 0 else {
            return NSColor.tertiaryLabelColor
        }
        switch pct {
        case ..<warningAt:
            return NSColor.systemTeal
        case warningAt..<criticalAt:
            return NSColor.systemOrange
        default:
            return NSColor.systemRed
        }
    }

    static func semanticColor(forFraction fraction: Double, warningAt: Int = 60, criticalAt: Int = 85) -> NSColor {
        guard fraction > 0.0 else {
            return NSColor.tertiaryLabelColor
        }
        let pct = max(1, Int((min(1.0, fraction) * 100.0).rounded()))
        return semanticColor(for: pct, warningAt: warningAt, criticalAt: criticalAt)
    }

    static func thermalStateColor(for label: String) -> NSColor {
        switch label {
        case "Normal", "Nominal":
            return NSColor.systemGreen
        case "Warning", "Fair":
            return NSColor.systemOrange
        case "Serious", "Critical":
            return NSColor.systemRed
        default:
            return NSColor.secondaryLabelColor
        }
    }

    static func memoryPressureColor(for label: String) -> NSColor {
        switch label {
        case "Normal":
            return NSColor.systemGreen
        case "Warning":
            return NSColor.systemOrange
        case "Critical":
            return NSColor.systemRed
        default:
            return NSColor.secondaryLabelColor
        }
    }

    static func drawCapsuleBar(
        in rect: NSRect,
        fraction: Double,
        fillColor: NSColor,
        trackColor: NSColor = barTrackColor
    ) {
        let radius = rect.height / 2.0
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        trackColor.setFill()
        trackPath.fill()

        let clamped = min(1.0, max(0.0, fraction))
        guard clamped > 0.0 else { return }

        let fillWidth = min(rect.width, max(rect.height, round(rect.width * CGFloat(clamped))))
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        fillColor.setFill()
        fillPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Compone una percentuale tipografica (es. "29" grande + "%" piccolo attenuato).
    /// Se `text` non è numerico ("…", "N/A"), renderizza come fallback neutro.
    static func attributedPercent(
        _ text: String,
        digitFont: NSFont,
        pctFont: NSFont,
        digitColor: NSColor,
        pctColor: NSColor
    ) -> NSAttributedString {
        if text.hasSuffix("%") {
            let numberPart = text.dropLast()
            if !numberPart.isEmpty && numberPart.allSatisfy({ $0.isNumber }) {
                let result = NSMutableAttributedString(
                    string: String(numberPart),
                    attributes: [.font: digitFont, .foregroundColor: digitColor]
                )
                result.append(
                    NSAttributedString(
                        string: "%",
                        attributes: [.font: pctFont, .foregroundColor: pctColor]
                    )
                )
                return result
            }
        }

        return NSAttributedString(
            string: text,
            attributes: [.font: digitFont, .foregroundColor: NSColor.secondaryLabelColor]
        )
    }
}

/// Spaziatore verticale leggero fra card adiacenti senza introdurre divisori aggiuntivi.
final class MenuSpacerView: NSView {
    override var isFlipped: Bool { true }

    init(width: CGFloat = 300.0, height: CGFloat = 6.0) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Vista riepilogativa "Hero" in cima a CPU, GPU e RAM (Titolo + % grande + barra piena larga).
final class MenuHeroView: NSView {
    override var isFlipped: Bool { true }

    private let title: String
    private let hasSubtitle: Bool
    private let warningThreshold: Int
    private let criticalThreshold: Int
    private var subtitle: String = ""
    private var valueText: String = "…"
    private var percent: Int?

    private static let titleFont = NSFont.systemFont(ofSize: 13.0, weight: .semibold)
    private static let subtitleFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
    private static let valueDigitFont = NSFont.monospacedDigitSystemFont(ofSize: 17.0, weight: .semibold)
    private static let valuePctFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)

    init(
        title: String,
        hasSubtitle: Bool = false,
        warningThreshold: Int = 60,
        criticalThreshold: Int = 85,
        width: CGFloat = 300.0
    ) {
        self.title = title
        self.hasSubtitle = hasSubtitle
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        let height: CGFloat = hasSubtitle ? 60.0 : 46.0
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(percent: Int?, valueText: String? = nil, subtitle: String = "") {
        let resolvedText = valueText ?? percent.map { "\($0)%" } ?? "…"
        guard self.percent != percent || self.valueText != resolvedText || self.subtitle != subtitle else {
            return
        }
        self.percent = percent
        self.valueText = resolvedText
        self.subtitle = subtitle
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = MenuVisualStyle.horizontalPadding
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: NSColor.labelColor
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let rowCenterY: CGFloat = 17.0
        let titleY = round(rowCenterY - titleSize.height / 2.0)
        (title as NSString).draw(at: NSPoint(x: pad, y: titleY), withAttributes: titleAttrs)

        let attrVal = MenuVisualStyle.attributedPercent(
            valueText,
            digitFont: Self.valueDigitFont,
            pctFont: Self.valuePctFont,
            digitColor: NSColor.labelColor,
            pctColor: NSColor.secondaryLabelColor
        )
        let valSize = attrVal.size()
        let valX = bounds.width - pad - valSize.width
        let valY = round(rowCenterY - valSize.height / 2.0 - 0.5)
        attrVal.draw(at: NSPoint(x: valX, y: valY))

        if hasSubtitle && !subtitle.isEmpty {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.subtitleFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            (subtitle as NSString).draw(at: NSPoint(x: pad, y: 27.0), withAttributes: subAttrs)
        }

        let barY: CGFloat = hasSubtitle ? 46.0 : 32.0
        let barRect = NSRect(x: pad, y: barY, width: bounds.width - pad * 2.0, height: 6.0)
        let fraction = Double(percent ?? 0) / 100.0
        let fillColor = MenuVisualStyle.semanticColor(
            for: percent,
            warningAt: warningThreshold,
            criticalAt: criticalThreshold
        )
        MenuVisualStyle.drawCapsuleBar(in: barRect, fraction: fraction, fillColor: fillColor)
    }
}

/// Vista riga singola per telemetria tabellare, scomposizione RAM con micro-barra o Top Processes.
final class MenuRowView: NSView {
    override var isFlipped: Bool { true }

    var label: String = "" {
        didSet { if label != oldValue { needsDisplay = true } }
    }

    var value: String = "" {
        didSet { if value != oldValue { needsDisplay = true } }
    }

    var isHeader: Bool = false {
        didSet { if isHeader != oldValue { needsDisplay = true } }
    }

    var valueColorOverride: NSColor? {
        didSet { if valueColorOverride != oldValue { needsDisplay = true } }
    }

    private var barFraction: Double?
    private var barColor: NSColor = NSColor.systemTeal
    private var dimValueWhenZero: Bool = false

    private static let labelFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    private static let headerFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
    private static let truncatedParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    init(
        label: String,
        value: String = "",
        isHeader: Bool = false,
        width: CGFloat = 300.0,
        height: CGFloat = 22.0
    ) {
        self.label = label
        self.value = value
        self.isHeader = isHeader
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setBarValue(
        _ value: String,
        fraction: Double?,
        color: NSColor = NSColor.systemTeal,
        dimWhenZero: Bool = false
    ) {
        let clamped = fraction.map { min(1.0, max(0.0, $0)) }
        guard self.value != value || self.barFraction != clamped || self.barColor != color || self.dimValueWhenZero != dimWhenZero else {
            return
        }
        self.value = value
        self.barFraction = clamped
        self.barColor = color
        self.dimValueWhenZero = dimWhenZero
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = MenuVisualStyle.horizontalPadding
        let font = isHeader ? Self.headerFont : Self.labelFont

        if let fraction = barFraction {
            let barWidth: CGFloat = 90.0
            let barHeight: CGFloat = 5.0
            let barX: CGFloat = 122.0
            let barY = round((bounds.height - barHeight) / 2.0)
            let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
            MenuVisualStyle.drawCapsuleBar(in: barRect, fraction: fraction, fillColor: barColor)
        }

        var reservedRightX = bounds.width - pad
        if !value.isEmpty {
            let resolvedValColor: NSColor
            if let override = valueColorOverride {
                resolvedValColor = override
            } else if dimValueWhenZero && (barFraction ?? 1.0) <= 0.0 {
                resolvedValColor = NSColor.tertiaryLabelColor
            } else {
                resolvedValColor = NSColor.labelColor
            }

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.valueFont,
                .foregroundColor: resolvedValColor
            ]

            let valueSize = (value as NSString).size(withAttributes: valueAttrs)
            let valueY = round((bounds.height - valueSize.height) / 2.0)
            let valueX = bounds.width - pad - valueSize.width
            (value as NSString).draw(at: NSPoint(x: valueX, y: valueY), withAttributes: valueAttrs)
            reservedRightX = valueX - 10.0
        }

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: Self.truncatedParagraphStyle
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let labelY = round((bounds.height - labelSize.height) / 2.0)
        let maxLabelRight = barFraction != nil ? 114.0 : reservedRightX
        let maxLabelWidth = max(40.0, maxLabelRight - pad)
        let labelRect = NSRect(x: pad, y: labelY, width: maxLabelWidth, height: ceil(labelSize.height))
        (label as NSString).draw(with: labelRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: labelAttrs)
    }
}

/// Card grafica per un singolo cluster CPU (`Super Cluster` / `Performance Cluster` / `Efficiency Cluster`).
/// Separa visivamente il totale cluster (badge a pillola nell'intestazione) dai singoli core (griglia 2 colonne con micro-barre).
final class MenuClusterView: NSView {
    override var isFlipped: Bool { true }

    private let clusterTitle: String
    private let corePrefix: String
    private let coreCount: Int

    private var clusterPercent: Int?
    private var corePercents: [Int?]

    private static let headerHeight: CGFloat = 26.0
    private static let gridTopPadding: CGFloat = 6.0
    private static let coreRowHeight: CGFloat = 22.0
    private static let gridBottomPadding: CGFloat = 6.0
    private static let cardMarginV: CGFloat = 2.0

    private static let titleFont = NSFont.systemFont(ofSize: 12.0, weight: .semibold)
    private static let badgeDigitFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
    private static let badgePctFont = NSFont.systemFont(ofSize: 9.0, weight: .medium)
    private static let coresCaptionFont = NSFont.systemFont(ofSize: 10.5, weight: .regular)
    private static let coreLabelFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    private static let coreDigitFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
    private static let corePctFont = NSFont.systemFont(ofSize: 9.0, weight: .medium)

    init(clusterTitle: String, corePrefix: String, coreCount: Int, width: CGFloat = 300.0) {
        self.clusterTitle = clusterTitle
        self.corePrefix = corePrefix
        self.coreCount = max(0, coreCount)
        self.corePercents = Array(repeating: nil, count: max(0, coreCount))

        let rowCount = (self.coreCount + 1) / 2
        let height = Self.cardMarginV * 2.0
            + Self.headerHeight
            + Self.gridTopPadding
            + CGFloat(rowCount) * Self.coreRowHeight
            + Self.gridBottomPadding

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(clusterPercent: Int?, corePercents: [Int?]) {
        let normalized = Array(corePercents.prefix(coreCount))
            + Array(repeating: nil, count: max(0, coreCount - corePercents.count))
        guard self.clusterPercent != clusterPercent || self.corePercents != normalized else {
            return
        }
        self.clusterPercent = clusterPercent
        self.corePercents = normalized
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cardRect = NSRect(
            x: 12.0,
            y: Self.cardMarginV,
            width: bounds.width - 24.0,
            height: bounds.height - Self.cardMarginV * 2.0
        )
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8.0, yRadius: 8.0)

        // Sfondo card arrotondata
        MenuVisualStyle.cardFillColor.setFill()
        cardPath.fill()

        // Banda header leggermente distinta + hairline divisorio interno
        NSGraphicsContext.saveGraphicsState()
        cardPath.addClip()
        let headerRect = NSRect(x: cardRect.minX, y: cardRect.minY, width: cardRect.width, height: Self.headerHeight)
        MenuVisualStyle.cardHeaderFillColor.setFill()
        headerRect.fill()

        let dividerRect = NSRect(x: cardRect.minX, y: cardRect.minY + Self.headerHeight - 0.5, width: cardRect.width, height: 0.5)
        MenuVisualStyle.cardDividerColor.setFill()
        dividerRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        cardPath.lineWidth = 0.75
        MenuVisualStyle.cardStrokeColor.setStroke()
        cardPath.stroke()

        // --- Intestazione Cluster (Titolo + Pillola totale affiancata + contatore core a destra) ---
        let headerCenterY = cardRect.minY + Self.headerHeight / 2.0
        let contentMinX = cardRect.minX + 10.0
        let contentMaxX = cardRect.maxX - 10.0

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: NSColor.labelColor
        ]
        let titleSize = (clusterTitle as NSString).size(withAttributes: titleAttrs)
        let titleY = round(headerCenterY - titleSize.height / 2.0)
        (clusterTitle as NSString).draw(at: NSPoint(x: contentMinX, y: titleY), withAttributes: titleAttrs)

        // Badge a pillola immediatamente accanto al nome del cluster (mai allineato sopra alla colonna 2 dei core!)
        let pillText = clusterPercent.map { "\($0)%" } ?? "…"
        let isClusterActive = (clusterPercent ?? 0) > 0
        let semanticTint = MenuVisualStyle.semanticColor(for: clusterPercent)
        let pillDigitColor = isClusterActive ? NSColor.labelColor : NSColor.secondaryLabelColor
        let pillPctColor = isClusterActive ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        let pillAttr = MenuVisualStyle.attributedPercent(
            pillText,
            digitFont: Self.badgeDigitFont,
            pctFont: Self.badgePctFont,
            digitColor: pillDigitColor,
            pctColor: pillPctColor
        )
        let pillTextSize = pillAttr.size()
        let pillWidth = pillTextSize.width + 12.0
        let pillHeight: CGFloat = 17.0
        let pillX = round(contentMinX + titleSize.width + 8.0)
        let pillY = round(headerCenterY - pillHeight / 2.0)
        let pillRect = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2.0, yRadius: pillHeight / 2.0)

        let pillBg = isClusterActive
            ? semanticTint.withAlphaComponent(0.20)
            : MenuVisualStyle.neutralBadgeFillColor
        pillBg.setFill()
        pillPath.fill()

        if isClusterActive {
            pillPath.lineWidth = 0.6
            semanticTint.withAlphaComponent(0.38).setStroke()
            pillPath.stroke()
        }

        pillAttr.draw(at: NSPoint(
            x: round(pillX + (pillWidth - pillTextSize.width) / 2.0),
            y: round(headerCenterY - pillTextSize.height / 2.0)
        ))

        // Didascalia sobria a destra ("4 cores" / "6 cores") invece di un ulteriore "%"
        let caption = coreCount == 1 ? "1 core" : "\(coreCount) cores"
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.coresCaptionFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let captionSize = (caption as NSString).size(withAttributes: captionAttrs)
        (caption as NSString).draw(
            at: NSPoint(x: contentMaxX - captionSize.width, y: round(headerCenterY - captionSize.height / 2.0)),
            withAttributes: captionAttrs
        )

        // --- Griglia Core a 2 Colonne Unite ([Etichetta + Micro-barra + %]) ---
        let gutter: CGFloat = 16.0
        let totalInnerWidth = contentMaxX - contentMinX
        let cellWidth = floor((totalInnerWidth - gutter) / 2.0)
        let gridStartY = cardRect.minY + Self.headerHeight + Self.gridTopPadding

        for index in 0..<coreCount {
            let row = index / 2
            let col = index % 2
            let cellMinX = col == 0 ? contentMinX : contentMaxX - cellWidth
            let cellMaxX = cellMinX + cellWidth
            let rowCenterY = gridStartY + CGFloat(row) * Self.coreRowHeight + Self.coreRowHeight / 2.0

            let pct = corePercents[index]
            let isActive = (pct ?? 0) > 0

            // 1. Etichetta core ("S1", "E1", ...)
            let coreName = "\(corePrefix)\(index + 1)"
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.coreLabelFont,
                .foregroundColor: isActive ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
            ]
            let lblSize = (coreName as NSString).size(withAttributes: labelAttrs)
            (coreName as NSString).draw(
                at: NSPoint(x: cellMinX, y: round(rowCenterY - lblSize.height / 2.0)),
                withAttributes: labelAttrs
            )

            // 2. Micro-barra orizzontale legata alla cella
            let barX = cellMinX + 25.0
            let barWidth = max(36.0, cellWidth - 68.0)
            let barHeight: CGFloat = 5.0
            let barRect = NSRect(x: barX, y: round(rowCenterY - barHeight / 2.0), width: barWidth, height: barHeight)
            let fraction = Double(pct ?? 0) / 100.0
            MenuVisualStyle.drawCapsuleBar(
                in: barRect,
                fraction: fraction,
                fillColor: MenuVisualStyle.semanticColor(for: pct)
            )

            // 3. Percentuale allineata a destra dentro la cella (attenuata a 0%)
            let valText = pct.map { "\($0)%" } ?? "…"
            let valDigitColor = isActive ? NSColor.labelColor : NSColor.tertiaryLabelColor
            let valPctColor = isActive ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
            let attrVal = MenuVisualStyle.attributedPercent(
                valText,
                digitFont: Self.coreDigitFont,
                pctFont: Self.corePctFont,
                digitColor: valDigitColor,
                pctColor: valPctColor
            )
            let valSize = attrVal.size()
            attrVal.draw(at: NSPoint(
                x: cellMaxX - valSize.width,
                y: round(rowCenterY - valSize.height / 2.0)
            ))
        }
    }
}
