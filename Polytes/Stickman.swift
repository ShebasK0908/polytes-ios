import CoreGraphics
import UIKit

enum StickmanState {
    case idle
    case walk
}

/// Un stickman completo: identidad, personalidad, necesidades, posición,
/// estado de animación y, cuando está en el aire o agarrado, su cuerpo
/// físico de puntos Verlet sobre el mismo esqueleto.
final class Stickman {
    let id = UUID()

    // Identidad y aspecto
    var name: String
    var color: UIColor
    var hollowHead: Bool
    var headRadius: Double {
        hollowHead ? C.hollowHeadDiameter / 2 : C.filledHeadDiameter / 2
    }

    // Personalidad y necesidades
    let energy: Int
    let curiosity: Int
    var stamina: Double = 100
    var boredom: Double = 45

    // Movimiento en modo animación. (x, y) es la esquina superior
    // izquierda de la caja; en vuelo la caja pasa a ser la envolvente
    // del cuerpo físico, como en el original.
    var x: Double
    var y: Double
    var width: Double = C.stickmanWidth
    var height: Double = C.stickmanHeight
    var velocityX: Double = 0
    var velocityY: Double = 0
    var direction: Int = 1
    var groundY: Double?
    var groundLimit: (left: Double, width: Double)

    // Cerebro
    var state: StickmanState = .idle
    var targetX: Double?
    var decideCooldown: Double = C.decideCooldownDefault

    // Cuerpo físico
    var holding = false
    var flying = false
    var grabPart: Joint?
    var ragPoints: [Joint: RagPoint] = [:]
    /// Ventanas que el cuerpo está atravesando y con las que no debe
    /// colisionar mientras tanto (al agarrar se vacía la lista).
    var overlapWindowIDs: [UUID] = []

    var isRagdollActive: Bool { holding || flying }

    // Animación
    var animationFrameIndex = 0
    var animationTimer: Double = 0
    var currentPose: Pose = Animations.idle.frames[0]
    var basePose: Pose = Animations.idle.frames[0]
    var animationCycleDuration: Double = C.defaultCycleDuration

    init(name: String, color: UIColor, hollowHead: Bool, spawnX: Double, spawnY: Double, worldWidth: Double) {
        self.name = name
        self.color = color
        self.hollowHead = hollowHead
        self.x = spawnX
        self.y = spawnY
        self.groundLimit = (0, worldWidth)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Sin saturación no hay tono: es el caso acromático del original.
        let hueDegrees: Double? = saturation < 0.05 ? nil : Double(hue) * 360

        let personality = Personality.generate(name: name, hollowHead: hollowHead, hueDegrees: hueDegrees)
        self.energy = personality.energy
        self.curiosity = personality.curiosity

        self.ragPoints = BodyPhysics.makeRagPoints(from: fkJoints())
    }

    /// Articulaciones según la animación (cinemática directa), sin espejo.
    func fkJoints() -> [Joint: CGPoint] {
        Rig.fkJoints(pose: currentPose, x: x, y: y, headRadius: headRadius)
    }

    /// Articulaciones tal y como se ven en pantalla: en modo físico son los
    /// puntos del ragdoll; en modo animación, la pose con el espejo aplicado
    /// cuando camina hacia la derecha.
    func displayJoints() -> [Joint: CGPoint] {
        if isRagdollActive {
            var joints: [Joint: CGPoint] = [:]
            for (joint, point) in ragPoints {
                joints[joint] = point.pos
            }
            return joints
        }
        let joints = fkJoints()
        if direction == 1 {
            return Rig.mirrored(joints, x: x, width: width)
        }
        return joints
    }

    /// Siembra el cuerpo físico desde la pose animada actual.
    /// Es el paso híbrido clave: el ragdoll nace de lo que se estaba viendo.
    func seedRagdoll() {
        ragPoints = BodyPhysics.makeRagPoints(from: displayJoints())
    }

    /// Empieza un agarre por una articulación concreta.
    func beginGrab(part: Joint) {
        overlapWindowIDs.removeAll()
        seedRagdoll()
        flying = false
        holding = true
        grabPart = part
    }

    /// Suelta el agarre: el cuerpo queda en vuelo con la velocidad del dedo
    /// aplicada a la parte agarrada y con el giro del arrastre horizontal.
    func releaseGrab(dragVelocity: CGPoint) {
        guard holding else { return }
        holding = false
        flying = true

        if let part = grabPart, let point = ragPoints[part] {
            point.old = CGPoint(x: point.pos.x - dragVelocity.x, y: point.pos.y - dragVelocity.y)
        }
        BodyPhysics.applySpin(points: ragPoints, angularVelocity: Double(dragVelocity.x) * C.ragdollSpinFactor)

        grabPart = nil
        velocityY = 0
        velocityX = 0
    }
}
