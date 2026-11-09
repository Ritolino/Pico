import AppKit

final class StatusItemFormatter {
    private static let labelFont = NSFont.systemFont(ofSize: 7.0, weight: .bold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    private let label: String
    private var lastPercent: Int? = -9999
    private var currentImage: NSImage?

    init(label: String) {
        self.label = label
        // Inizializza subito con l'immagine di bootstrap ("…")
        self.currentImage = Self.buildImage(label: label, value: "…")
    }

    private static func buildImage(label: String, value: String) -> NSImage {
        let width = AppConfig.itemImageWidth
        let height = AppConfig.itemImageHeight
        let size = NSSize(width: width, height: height)

        let img = NSImage(size: size, flipped: true) { rect in
            let str1 = NSAttributedString(string: label, attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle
            ])
            let str2 = NSAttributedString(string: value, attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle
            ])

            // Centratura ottica verticale bilanciata:
            // - Etichetta superiore compatta (7.0pt bold) a y = 0.5
            // - Percentuale ingrandita e dominante (10.5pt medium) a y = 8.5
            // Margine superiore = 0.5 pt, margine inferiore = 0.5 pt.
            // Il baricentro del blocco testo cade esattamente al centro della pillola (y = 11.0 pt),
            // perfettamente allineato verticalmente al centro di tutte le altre icone di sistema (es. Batteria).
            str1.draw(in: NSRect(x: 0, y: 0.5, width: width, height: 8.5))
            str2.draw(in: NSRect(x: 0, y: 8.5, width: width, height: 13.0))
            return true
        }

        // isTemplate = true garantisce che macOS gestisca automaticamente
        // contrasto, Light Mode, Dark Mode e stato di selezione
        img.isTemplate = true
        return img
    }

    /// Restituisce l'istanza di NSImage (template) aggiornata.
    /// Mantiene in memoria solo l'immagine corrente: quando il valore non cambia,
    /// restituisce l'istanza esistente senza alcuna riallocazione.
    /// Quando il valore cambia, alloca la nuova immagine e rilascia la precedente,
    /// azzerando l'accumulo di bitmap CGImage in memoria nel tempo.
    func image(for percent: Int?) -> NSImage {
        guard let p = percent else {
            if lastPercent == nil, let img = currentImage {
                return img
            }
            lastPercent = nil
            let img = Self.buildImage(label: label, value: "…")
            currentImage = img
            return img
        }

        if p == lastPercent, let img = currentImage {
            return img
        }

        lastPercent = p
        let strVal = (p >= 0 && p <= 100) ? "\(p)%" : "N/A"
        let img = Self.buildImage(label: label, value: strVal)
        currentImage = img
        return img
    }
}
