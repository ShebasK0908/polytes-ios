import Foundation
import CryptoKit

/// Generador determinista (SplitMix64). Solo se usa para que la personalidad
/// sea siempre la misma para el mismo nombre, como en el diseño original,
/// donde los rasgos se sembraban con un hash del nombre.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Rasgos fijos de un stickman: energía, curiosidad y sociabilidad,
/// de 1 a 100, todos de la misma semilla (el nombre).
struct Personality {
    let energy: Int
    let curiosity: Int
    let sociability: Int

    /// Genera la personalidad a partir del nombre (semilla = SHA-256 del
    /// nombre), con los refuerzos del diseño original: la cabeza hueca da
    /// +20 % de energía; los colores fríos (verde a azul, tono 120–240)
    /// dan +20 % de curiosidad y los cálidos +20 % de energía. Un color
    /// sin tono (gris, blanco, negro) no da refuerzo.
    static func generate(name: String, hollowHead: Bool, hueDegrees: Double?) -> Personality {
        let digest = SHA256.hash(data: Data(name.utf8))
        var seed: UInt64 = 0
        for byte in digest.prefix(8) {
            seed = (seed << 8) | UInt64(byte)
        }
        var rng = SplitMix64(state: seed)

        var energy = Double(rng.next() % 101)
        var curiosity = Double(rng.next() % 101)
        // Tercer rasgo de la misma semilla: la sociabilidad (v4), que
        // modula saludos, seguimientos y ayudas. Sin bonus de cabeza ni
        // de color: es puramente del nombre.
        let sociability = Double(rng.next() % 101)

        if hollowHead {
            energy *= 1.2
        }
        if let hue = hueDegrees {
            if hue >= 120 && hue <= 240 {
                curiosity *= 1.2
            } else {
                energy *= 1.2
            }
        }

        energy = clampValue(energy, 1, 100)
        curiosity = clampValue(curiosity, 1, 100)
        return Personality(
            energy: Int(energy.rounded()),
            curiosity: Int(curiosity.rounded()),
            sociability: Int(clampValue(sociability, 1, 100).rounded())
        )
    }
}

/// Necesidades cambiantes: stamina y aburrimiento. Estar quieto recupera
/// stamina pero aburre; caminar gasta stamina pero entretiene. Las tasas
/// dependen de los rasgos, igual que en el diseño original.
enum Needs {
    static func update(_ s: Stickman, dt: Double) {
        let staminaDrain = (65 / Double(s.energy)) * dt
        let staminaGain = (Double(s.energy) / 50) * dt
        let boredomDrain = (Double(s.curiosity) / 50) * dt
        let boredomGain = (Double(s.curiosity) / 30) * dt

        // Sentado en un borde o tumbado también se descansa (v4).
        if s.state == .idle || s.state == .rest || s.state == .sit {
            s.stamina += staminaGain
            s.boredom += boredomGain
        } else {
            s.stamina -= staminaDrain
            s.boredom -= boredomDrain
        }

        // Pelear cansa más que pasear (v3).
        if s.opponentID != nil {
            s.stamina -= (30 / Double(s.energy)) * dt
        }

        s.stamina = clampValue(s.stamina, 0, 100)
        s.boredom = clampValue(s.boredom, 0, 100)
    }
}

/// El cerebro decide por utilidad: puntúa caminar y estar quieto sumando
/// los factores (energía, curiosidad, stamina, aburrimiento) y sus
/// inversos, y cambia de estado si una opción supera a la otra con margen.
enum Brain {
    static func update(_ s: Stickman, worldWidth: Double, dt: Double) {
        s.decideCooldown -= dt

        if s.decideCooldown <= 0 {
            decide(s, worldWidth: worldWidth)
            s.decideCooldown = C.decideCooldownDefault
        }

        if s.state == .walk, let target = s.targetX, abs(s.x - target) < 10 {
            s.targetX = chooseTargetX(s, worldWidth: worldWidth)
        }
    }

    static func decide(_ s: Stickman, worldWidth: Double) {
        let previousState = s.state

        let scoreWalk = score(s, inverted: false)
        let scoreIdle = score(s, inverted: true)

        if scoreWalk > scoreIdle + C.scoreMargin && !s.holding && !s.flying {
            s.state = .walk
            s.targetX = chooseTargetX(s, worldWidth: worldWidth)
        } else if scoreIdle > scoreWalk {
            s.state = .idle
            s.targetX = nil
        }

        if s.state != previousState {
            // Transición suave: la animación parte de la pose actual.
            s.animationFrameIndex = -1
            s.animationTimer = 0
            s.basePose = s.currentPose
        }
    }

    static func score(_ s: Stickman, inverted: Bool) -> Double {
        let factors = [Double(s.energy), Double(s.curiosity), s.stamina, s.boredom]
        var utility: Double = 0
        for factor in factors {
            utility += inverted ? 1 - factor / 100 : factor / 100
        }
        return utility
    }

    /// Objetivo de paseo: un punto aleatorio del mundo, a 300 pt o más
    /// de la posición actual (el escritorio apaisado de la v2 es ancho y
    /// da para paseos largos; con margen reducido si el mundo es estrecho).
    static func chooseTargetX(_ s: Stickman, worldWidth: Double) -> Double {
        let minX = C.stickmanWidth
        let maxX = worldWidth - C.stickmanWidth
        if maxX <= minX { return s.x }

        let minDistance = min(300, (maxX - minX) / 2)
        for _ in 0..<60 {
            let target = Double.random(in: minX...maxX)
            if abs(target - s.x) >= minDistance {
                return target
            }
        }
        return (maxX - s.x) >= (s.x - minX) ? maxX : minX
    }
}
