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
        let clip = s.state == .walk ? Animations.walk : Animations.idle

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
