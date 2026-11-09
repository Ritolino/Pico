import Foundation

enum AppConfig {
    /// Intervallo di aggiornamento a riposo nella barra dei menu (secondi).
    static let barUpdateInterval: TimeInterval = 3.0

    /// Leeway generoso per timer coalescing del kernel (millisecondi).
    static let timerLeewayMilliseconds: Int = 500

    /// Dimensioni fisse dell'immagine template in punti per ciascuno dei 3 NSStatusItem (zero jitter).
    static let itemImageWidth: CGFloat = 32.0
    static let itemImageHeight: CGFloat = 22.0
}
