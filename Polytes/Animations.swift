import Foundation

/// Una pose es un conjunto de ángulos (en grados) para las articulaciones.
/// Convención: 0° apunta a la derecha y los ángulos crecen hacia abajo
/// (coordenadas de pantalla), así que -90° es "hacia arriba".
struct Pose {
    var torso: Double
    var hipOffsetY: Double
    var upperArmR: Double
    var forearmR: Double
    var upperArmL: Double
    var forearmL: Double
    var upperLegR: Double
    var lowerLegR: Double
    var upperLegL: Double
    var lowerLegL: Double

    static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return Pose(
            torso: mix(a.torso, b.torso),
            hipOffsetY: mix(a.hipOffsetY, b.hipOffsetY),
            upperArmR: mix(a.upperArmR, b.upperArmR),
            forearmR: mix(a.forearmR, b.forearmR),
            upperArmL: mix(a.upperArmL, b.upperArmL),
            forearmL: mix(a.forearmL, b.forearmL),
            upperLegR: mix(a.upperLegR, b.upperLegR),
            lowerLegR: mix(a.lowerLegR, b.lowerLegR),
            upperLegL: mix(a.upperLegL, b.upperLegL),
            lowerLegL: mix(a.lowerLegL, b.lowerLegL)
        )
    }
}

/// Tablas de poses clave de las dos animaciones del diseño original:
/// caminar (12 poses) y estar quieto (6 poses, con su respiro).
enum Animations {
    struct Clip {
        let defaultCycle: Double
        let frames: [Pose]
    }

    static let walk = Clip(defaultCycle: 0.5, frames: [
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 58, forearmR: 16, upperArmL: 107, forearmL: 9, upperLegR: 117, lowerLegR: -27, upperLegL: 77, lowerLegL: -7),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 62, forearmR: 16, upperArmL: 90, forearmL: 26, upperLegR: 111, lowerLegR: -29, upperLegL: 87, lowerLegL: -21),
        Pose(torso: -89, hipOffsetY: 0, upperArmR: 68, forearmR: 13, upperArmL: 91, forearmL: 14, upperLegR: 105, lowerLegR: -38, upperLegL: 94, lowerLegL: -5),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 71, forearmR: 16, upperArmL: 78, forearmL: 26, upperLegR: 105, lowerLegR: -27, upperLegL: 97, lowerLegL: -15),
        Pose(torso: -91, hipOffsetY: 0, upperArmR: 59, forearmR: 16, upperArmL: 96, forearmL: 26, upperLegR: 111, lowerLegR: -29, upperLegL: 84, lowerLegL: -15),
        Pose(torso: -91, hipOffsetY: 0, upperArmR: 56, forearmR: 16, upperArmL: 104, forearmL: 26, upperLegR: 120, lowerLegR: -29, upperLegL: 80, lowerLegL: -15),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 107, forearmR: 9, upperArmL: 58, forearmL: 16, upperLegR: 77, lowerLegR: -7, upperLegL: 117, lowerLegL: -27),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 90, forearmR: 26, upperArmL: 62, forearmL: 16, upperLegR: 87, lowerLegR: -21, upperLegL: 111, lowerLegL: -29),
        Pose(torso: -89, hipOffsetY: 0, upperArmR: 91, forearmR: 14, upperArmL: 68, forearmL: 13, upperLegR: 94, lowerLegR: -5, upperLegL: 105, lowerLegL: -38),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 78, forearmR: 26, upperArmL: 71, forearmL: 16, upperLegR: 97, lowerLegR: -15, upperLegL: 105, lowerLegL: -27),
        Pose(torso: -91, hipOffsetY: 0, upperArmR: 96, forearmR: 26, upperArmL: 59, forearmL: 16, upperLegR: 84, lowerLegR: -15, upperLegL: 111, lowerLegL: -29),
        Pose(torso: -91, hipOffsetY: 0, upperArmR: 104, forearmR: 26, upperArmL: 56, forearmL: 16, upperLegR: 80, lowerLegR: -15, upperLegL: 120, lowerLegL: -29)
    ])

    // MARK: - Poses de acción (v3: combate y poderes)
    // Poses sueltas que el Animator interpola sobre la animación en curso
    // cuando el stickman ataca, carga, bloquea o se desplaza a supervelocidad.
    // Como el resto de la animación base, miran a la izquierda y se espejan
    // al mirar a la derecha.

    /// Puño extendido hacia delante, cuerpo inclinado al golpe.
    static let punchPose = Pose(torso: -78, hipOffsetY: 0, upperArmR: 168, forearmR: 6, upperArmL: 55, forearmL: 35, upperLegR: 102, lowerLegR: -12, upperLegL: 78, lowerLegL: -6)
    /// Carga del superpuñetazo: puño atrás, junto a la cadera, piernas flexionadas.
    static let chargePose = Pose(torso: -96, hipOffsetY: 0, upperArmR: 15, forearmR: -125, upperArmL: 120, forearmL: -20, upperLegR: 112, lowerLegR: -32, upperLegL: 72, lowerLegL: -18)
    /// Brazos hacia delante lanzando fuego o el láser.
    static let castPose = Pose(torso: -84, hipOffsetY: 0, upperArmR: 152, forearmR: 8, upperArmL: 138, forearmL: 18, upperLegR: 95, lowerLegR: -10, upperLegL: 85, lowerLegL: -8)
    /// Guardia: brazos cruzados delante del pecho, piernas firmes.
    static let blockPose = Pose(torso: -88, hipOffsetY: 0, upperArmR: 128, forearmR: -78, upperArmL: 122, forearmL: -88, upperLegR: 100, lowerLegR: -14, upperLegL: 80, lowerLegL: -10)
    /// Dash de supervelocidad: cuerpo inclinado hacia delante, brazos atrás.
    static let dashPose = Pose(torso: -58, hipOffsetY: 0, upperArmR: 40, forearmR: 20, upperArmL: 30, forearmL: 25, upperLegR: 130, lowerLegR: -15, upperLegL: 55, lowerLegL: -25)

    // MARK: - Poses y clips de la mente extendida (v4)

    /// Saludo: un brazo levantado, el otro caído.
    static let wavePose = Pose(torso: -88, hipOffsetY: 0, upperArmR: -95, forearmR: -35, upperArmL: 118, forearmL: 10, upperLegR: 95, lowerLegR: -10, upperLegL: 85, lowerLegL: -8)
    /// Alegría: los dos brazos en alto, piernas en semiflexión de salto.
    static let joyPose = Pose(torso: -92, hipOffsetY: 0, upperArmR: -55, forearmR: -25, upperArmL: -125, forearmL: 25, upperLegR: 100, lowerLegR: -18, upperLegL: 82, lowerLegL: -10)
    /// Asomarse a un borde: torso inclinado hacia delante y abajo,
    /// brazos hacia delante, mirando lo que hay debajo.
    static let peekPose = Pose(torso: -52, hipOffsetY: 0, upperArmR: 150, forearmR: 20, upperArmL: 140, forearmL: 26, upperLegR: 96, lowerLegR: -6, upperLegL: 86, lowerLegL: -4)

    /// Sentado en el borde de una ventana: muslos hacia delante, espinillas
    /// colgando y balanceándose (las fases de las dos piernas van desfasadas),
    /// brazos apoyados atrás. La FK no aplica el ajuste de pies al suelo en
    /// este estado: las piernas cuelgan por debajo de la caja.
    static let sit = Clip(defaultCycle: 1.6, frames: [
        Pose(torso: -86, hipOffsetY: 0, upperArmR: 118, forearmR: 42, upperArmL: 108, forearmL: 48, upperLegR: 168, lowerLegR: -78, upperLegL: 174, lowerLegL: -95),
        Pose(torso: -86, hipOffsetY: 0, upperArmR: 118, forearmR: 42, upperArmL: 108, forearmL: 48, upperLegR: 168, lowerLegR: -88, upperLegL: 174, lowerLegL: -85),
        Pose(torso: -86, hipOffsetY: 0, upperArmR: 118, forearmR: 42, upperArmL: 108, forearmL: 48, upperLegR: 168, lowerLegR: -98, upperLegL: 174, lowerLegL: -75),
        Pose(torso: -86, hipOffsetY: 0, upperArmR: 118, forearmR: 42, upperArmL: 108, forearmL: 48, upperLegR: 168, lowerLegR: -88, upperLegL: 174, lowerLegL: -85)
    ])

    /// Tumbado boca arriba descansando (también es la pose de «en el suelo
    /// tras una caída» durante la recuperación): cuerpo horizontal a ras
    /// de suelo, pero con volumen de cuerpo de verdad (v5): una rodilla
    /// flexionada con el pie apoyado, un brazo doblado sobre el cuerpo y
    /// el otro extendido, y un respiro que se nota entre fotogramas.
    /// Antes las dos piernas iban rectas y juntas y los dos fotogramas
    /// eran casi idénticos: se leía como una tabla rígida.
    static let rest = Clip(defaultCycle: 2.6, frames: [
        Pose(torso: 176, hipOffsetY: 0, upperArmR: 100, forearmR: 34, upperArmL: 76, forearmL: -10, upperLegR: 9, lowerLegR: -5, upperLegL: -7, lowerLegL: -30),
        Pose(torso: 173, hipOffsetY: 0, upperArmR: 100, forearmR: 40, upperArmL: 76, forearmL: -10, upperLegR: 9, lowerLegR: -5, upperLegL: -5, lowerLegL: -26),
        Pose(torso: 177, hipOffsetY: 0, upperArmR: 96, forearmR: 26, upperArmL: 82, forearmL: -4, upperLegR: 6, lowerLegR: -3, upperLegL: -9, lowerLegL: -33)
    ])

    static let idle = Clip(defaultCycle: 2.0, frames: [
        Pose(torso: -85, hipOffsetY: 0, upperArmR: 59, forearmR: 11, upperArmL: 121, forearmL: -11, upperLegR: 72, lowerLegR: 11, upperLegL: 108, lowerLegL: -11),
        Pose(torso: -85, hipOffsetY: 0, upperArmR: 54, forearmR: 11, upperArmL: 126, forearmL: -11, upperLegR: 72, lowerLegR: 11, upperLegL: 108, lowerLegL: -11),
        Pose(torso: -85, hipOffsetY: 0, upperArmR: 48, forearmR: 11, upperArmL: 132, forearmL: -11, upperLegR: 72, lowerLegR: 11, upperLegL: 108, lowerLegL: -11),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 59, forearmR: 11, upperArmL: 121, forearmL: -11, upperLegR: 72, lowerLegR: 11, upperLegL: 108, lowerLegL: -11),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 65, forearmR: 11, upperArmL: 115, forearmL: -11, upperLegR: 72, lowerLegR: 11, upperLegL: 108, lowerLegL: -11),
        Pose(torso: -90, hipOffsetY: 0, upperArmR: 65, forearmR: 11, upperArmL: 115, forearmL: -11, upperLegR: 72, lowerLegR: 11, upperLegL: 108, lowerLegL: -11)
    ])
}

/// Avanza la animación de un stickman interpolando entre poses clave.
/// Al caminar, la duración del ciclo se deriva de la velocidad para que
/// los pies no patinen sobre el suelo.
enum Animator {
    static func update(_ s: Stickman, dt: Double) {
        // Pose de acción (v3): mientras dura, la pose actual se interpola
        // rápidamente hacia ella y la animación normal queda en pausa. Al
        // terminar, la animación retoma desde la pose alcanzada.
        if let actionPose = s.actionPose {
            s.actionPoseTimer -= dt
            s.currentPose = Pose.lerp(s.currentPose, actionPose, min(1, dt / 0.07))
            if s.actionPoseTimer <= 0 {
                s.actionPose = nil
                s.basePose = s.currentPose
                s.animationFrameIndex = -1
                s.animationTimer = 0
            }
            return
        }

        // Clip según el estado (v4): en el suelo tras una caída y al
        // tumbarse se usa el clip de tumbado; sentado, el de sentado.
        let clip: Animations.Clip
        if s.downedTimer > 0 || s.state == .rest {
            clip = Animations.rest
        } else if s.state == .sit {
            clip = Animations.sit
        } else {
            clip = s.state == .walk ? Animations.walk : Animations.idle
        }

        if s.state == .walk && !s.holding && !s.flying && s.velocityX != 0 {
            s.animationCycleDuration = C.distancePerWalkCycle / abs(s.velocityX)
        } else {
            s.animationCycleDuration = clip.defaultCycle
        }

        let secondsPerFrame = s.animationCycleDuration / Double(clip.frames.count)
        s.currentPose = interpolate(s, frames: clip.frames, secondsPerFrame: secondsPerFrame)

        s.animationTimer += dt
        if s.animationTimer >= secondsPerFrame {
            s.animationTimer = 0
            s.animationFrameIndex = (s.animationFrameIndex + 1) % clip.frames.count
            s.basePose = clip.frames[s.animationFrameIndex]
        }
    }

    private static func interpolate(_ s: Stickman, frames: [Pose], secondsPerFrame: Double) -> Pose {
        let progress = min(s.animationTimer / secondsPerFrame, 1)
        let next = frames[(s.animationFrameIndex + 1) % frames.count]
        return Pose.lerp(s.basePose, next, progress)
    }
}
