import AppKit

/// Vista riga singola per gli elementi informativi dei menu di Pico.
/// Disegna direttamente in draw(_:) per garantire zero allocazioni,
/// contrasto elevato conforme ad Apple HIG e allineamento perfetto.
final class MenuRowView: NSView {
    var label: String = "" {
        didSet { if label != oldValue { needsDisplay = true } }
    }

    var value: String = "" {
        didSet { if value != oldValue { needsDisplay = true } }
    }

    var isHeader: Bool = false {
        didSet { if isHeader != oldValue { needsDisplay = true } }
    }

    var indent: CGFloat = 0.0 {
        didSet { if indent != oldValue { needsDisplay = true } }
    }

    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let headerValueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    init(label: String, value: String = "", isHeader: Bool = false, width: CGFloat = 270.0, height: CGFloat = 22.0) {
        self.label = label
        self.value = value
        self.isHeader = isHeader
        self.indent = 0.0
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let font = isHeader ? Self.headerFont : Self.labelFont
        let color = isHeader ? NSColor.labelColor : NSColor.secondaryLabelColor

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let labelY = round((bounds.height - labelSize.height) / 2.0)
        // Allineamento a filo sinistro per tutte le righe a 14pt (nessuna indentazione da tabulazione)
        let labelX: CGFloat = 14.0
        (label as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: labelAttrs)

        guard !value.isEmpty else { return }

        let valFont = isHeader ? Self.headerValueFont : Self.valueFont
        let valColor = NSColor.labelColor

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valFont,
            .foregroundColor: valColor
        ]

        let valueSize = (value as NSString).size(withAttributes: valueAttrs)
        let valueY = round((bounds.height - valueSize.height) / 2.0)
        let valueX = bounds.width - 14.0 - valueSize.width
        (value as NSString).draw(at: NSPoint(x: valueX, y: valueY), withAttributes: valueAttrs)
    }
}

/// Vista per righe CPU a due colonne (es. S1: 2%   S2: 1%).
final class MenuDualCoreRowView: NSView {
    var col1Label: String = "" {
        didSet { if col1Label != oldValue { needsDisplay = true } }
    }
    var col1Value: String = "" {
        didSet { if col1Value != oldValue { needsDisplay = true } }
    }
    var col2Label: String = "" {
        didSet { if col2Label != oldValue { needsDisplay = true } }
    }
    var col2Value: String = "" {
        didSet { if col2Value != oldValue { needsDisplay = true } }
    }

    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    init(width: CGFloat = 270.0, height: CGFloat = 20.0) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCores(c1Label: String, c1Val: String, c2Label: String, c2Val: String) {
        self.col1Label = c1Label
        self.col1Value = c1Val
        self.col2Label = c2Label
        self.col2Value = c2Val
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let midX = round(bounds.width / 2.0)

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.valueFont,
            .foregroundColor: NSColor.labelColor
        ]

        // Colonna 1: c1Label ("S1:", "E1:", ecc.) allineato a filo sinistro su x = 14.0 (identico a tutte le altre scritte)
        let c1LblSize = (col1Label as NSString).size(withAttributes: labelAttrs)
        let c1LblY = round((bounds.height - c1LblSize.height) / 2.0)
        (col1Label as NSString).draw(at: NSPoint(x: 14.0, y: c1LblY), withAttributes: labelAttrs)

        let c1ValSize = (col1Value as NSString).size(withAttributes: valAttrs)
        let c1ValY = round((bounds.height - c1ValSize.height) / 2.0)
        let c1ValX = midX - 14.0 - c1ValSize.width
        (col1Value as NSString).draw(at: NSPoint(x: c1ValX, y: c1ValY), withAttributes: valAttrs)

        // Colonna 2: c2Label a metà larghezza (midX + 10), c2Value allineato a destra su bounds.width - 14
        if !col2Label.isEmpty || !col2Value.isEmpty {
            let c2LblSize = (col2Label as NSString).size(withAttributes: labelAttrs)
            let c2LblY = round((bounds.height - c2LblSize.height) / 2.0)
            (col2Label as NSString).draw(at: NSPoint(x: midX + 10.0, y: c2LblY), withAttributes: labelAttrs)

            let c2ValSize = (col2Value as NSString).size(withAttributes: valAttrs)
            let c2ValY = round((bounds.height - c2ValSize.height) / 2.0)
            let c2ValX = bounds.width - 14.0 - c2ValSize.width
            (col2Value as NSString).draw(at: NSPoint(x: c2ValX, y: c2ValY), withAttributes: valAttrs)
        }
    }
}
