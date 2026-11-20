import CoreGraphics
import UIKit

/// Partícula suelta del sistema de efectos: llamas de los chorros y de
/// las bolas de fuego, chispas de impacto y estelas. Se integra con dt
/// en segundos (a diferencia del ragdoll, que va por paso fijo).
struct Particle {
    var pos: CGPoint
    var vel: CGPoint
    var life: Double
    var maxLife: Double
    var size: Double
    var color: UIColor
    /// Multiplicador de gravedad (1 = cae como un cuerpo; negativo = sube,
    /// como las llamas).
    var gravityScale: Double = 0
    /// Amortiguación por segundo.
    var drag: Double = 0
}

/// Bola de fuego en vuelo. Impacta contra el primer stickman que no sea
/// su dueño (o estalla en su punto objetivo, al disparar contra el dedo).
struct Fireball {
    let ownerID: UUID
    var pos: CGPoint
    var vel: CGPoint
    var targetPoint: CGPoint?
    var life: Double = 1.6
}

/// Haz de láser instantáneo: se dibuja desvaneciéndose durante su vida.
struct Laser {
    var from: CGPoint
    var to: CGPoint
    var life: Double
    var maxLife: Double
    var color: UIColor
}

/// Silueta fantasma que deja el dash de supervelocidad.
struct TrailGhost {
    var joints: [Joint: CGPoint]
    var color: UIColor
    var hollowHead: Bool
    var headRadius: Double
    var life: Double
    var maxLife: Double
}
