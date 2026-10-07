import Foundation

/// Decide cuándo cortar un dictado largo en trozos: en una pausa, para no partir palabras.
/// Así cada trozo se transcribe mientras sigues hablando y al terminar solo falta el último.
public struct PauseDetector: Sendable {
    /// Antes de esto no se corta: los dictados cortos van enteros.
    public var minimum: TimeInterval = 10
    /// Silencio que cuenta como pausa.
    public var pause: TimeInterval = 0.45
    /// Pasado este tiempo vale una pausa más corta…
    public var relaxedAfter: TimeInterval = 18
    public var relaxedPause: TimeInterval = 0.22
    /// …y pasado este se corta aunque no haya pausa.
    public var maximum: TimeInterval = 28

    private var elapsed: TimeInterval = 0
    private var silence: TimeInterval = 0
    /// Nivel del ruido de fondo: el mínimo reciente, que sube despacio por si cambia el ambiente.
    private var floor: Float = 1
    /// Nivel de la voz: el máximo reciente, que baja despacio.
    private var peak: Float = 0
    /// Segundos con voz desde el último corte. Un trozo sin voz no se corta ni se envía:
    /// con silencio, Whisper se inventa frases.
    public private(set) var voiced: TimeInterval = 0

    public init() {}

    /// `level`: volumen entre 0 y 1. Devuelve true cuando toca cortar (y empieza a contar de nuevo).
    public mutating func feed(level: Float, elapsed delta: TimeInterval) -> Bool {
        elapsed += delta
        floor = min(level, floor + Float(delta) * 0.02)
        peak = max(level, peak - Float(delta) * 0.05)
        // Es pausa lo que queda cerca del ruido de fondo y lejos de la voz. Si aún no se han
        // visto las dos cosas (todo suena igual), no se puede saber y no cuenta.
        let range = peak - floor
        if range >= 0.15, level < floor + range * 0.35 {
            silence += delta
        } else {
            silence = 0
        }
        if range >= 0.15 ? level >= floor + range * 0.5 : level > 0.3 {
            voiced += delta
        }
        let needed = elapsed >= relaxedAfter ? relaxedPause : pause
        guard voiced >= 0.6, elapsed >= maximum || (elapsed >= minimum && silence >= needed) else { return false }
        elapsed = 0
        silence = 0
        voiced = 0
        return true
    }
}
