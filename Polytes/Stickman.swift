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

    var isRagdollActive: Bool { holding || flying || carriedByID != nil }

    // Combate y poderes (v3). La lógica vive en Combat.swift; aquí solo
    // está el estado. Los impulsos de golpe se expresan en pt por paso
    // de simulación (la unidad natural del ragdoll Verlet).
    /// Irritación contra el dedo (0–100): sube con agarres y lanzamientos.
    var irritation: Double = 0
    /// Segundos de represalia activa contra el dedo.
    var retaliateTimer: Double = 0
    var retaliateCooldown: Double = 0
    /// Rival actual de pelea, si lo hay.
    var opponentID: UUID?
    var fightTimer: Double = 0
    var fightCooldown: Double = 0
    var attackCooldown: Double = 0
    var fightThinkTimer: Double = Double.random(in: 0.5...1.5)
    /// Superpuñetazo cargándose: la carga es visible (brillo en el puño).
    var chargingPunch = false
    var chargeTimer: Double = 0
    /// Pose de acción que el Animator interpola sobre la animación normal.
    var actionPose: Pose?
    var actionPoseTimer: Double = 0
    var blockingTimer: Double = 0
    /// Empuje horizontal externo (pt/s) que se consume en modo animación:
    /// resbalón al bloquear, abalanzamiento al fallar un superpuñetazo.
    var externalPushX: Double = 0
    /// Dash de supervelocidad en curso (modo animación).
    var dashTimer: Double = 0
    var dashVelocityX: Double = 0
    var dashHitTargetID: UUID?
    /// Vuelo con motor sobre el ragdoll: dirección asistida hacia el objetivo.
    var poweredFlight = false
    var flightTarget: CGPoint?
    var flightTimer: Double = 0
    var flightAttackTargetID: UUID?
    /// Superfuerza: a quién lleva en alto y quién lo lleva a él.
    var carryingID: UUID?
    var carriedByID: UUID?
    var carryTimer: Double = 0

    /// ¿Está ocupado en algo de combate? El cerebro normal se pausa.
    var isInCombat: Bool {
        opponentID != nil || retaliateTimer > 0 || carryingID != nil
            || carriedByID != nil || chargingPunch
    }

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
        // Agarrarlo corta el vuelo con motor y cancela la carga del puño.
        cutPoweredFlight()
        chargingPunch = false
        seedRagdoll()
        flying = false
        holding = true
        grabPart = part
    }

    /// Suelta el agarre: el cuerpo queda en vuelo con la velocidad del dedo
    /// aplicada a la parte agarrada y con el giro del arrastre horizontal.
    /// `dragVelocity` viene en pt/s (medida con marcas de tiempo táctiles);
    /// se convierte a desplazamiento por paso y se acota para que un
    /// latigazo extremo no produzca velocidades imposibles.
    func releaseGrab(dragVelocity: CGPoint) {
        guard holding else { return }
        holding = false
        flying = true

        let stepVX = clampValue(Double(dragVelocity.x) * C.frameDuration, -80, 80)
        let stepVY = clampValue(Double(dragVelocity.y) * C.frameDuration, -80, 80)
        if let part = grabPart, let point = ragPoints[part] {
            point.old = CGPoint(x: point.pos.x - CGFloat(stepVX), y: point.pos.y - CGFloat(stepVY))
        }
        let spin = clampValue(stepVX * C.ragdollSpinFactor, -0.3, 0.3)
        BodyPhysics.applySpin(points: ragPoints, angularVelocity: spin)

        grabPart = nil
        velocityY = 0
        velocityX = 0
    }

    // MARK: - Poderes (v3)

    /// Centro actual del cuerpo (la caja en modo animación; la envolvente
    /// del ragdoll en modo físico, que la simulación mantiene en x/y).
    func centerPoint() -> CGPoint {
        cgPoint(x + width / 2, y + height / 2)
    }

    /// Fija la pose de acción que se verá durante unos segundos.
    func setActionPose(_ pose: Pose, duration: Double) {
        actionPose = pose
        actionPoseTimer = duration
    }

    /// Despega con vuelo con motor: el ragdoll se siembra desde la pose
    /// actual, recibe un impulso inicial hacia arriba y queda dirigido
    /// hacia `target` hasta que el temporizador corte el vuelo.
    func beginPoweredFlight(target: CGPoint, duration: Double) {
        if !isRagdollActive {
            seedRagdoll()
        }
        holding = false
        grabPart = nil
        flying = true
        poweredFlight = true
        flightTarget = target
        flightTimer = duration
        for point in ragPoints.values {
            point.old.y = point.pos.y + 4
        }
    }

    /// Corta el vuelo con motor: el cuerpo sigue en ragdoll y cae.
    func cutPoweredFlight() {
        poweredFlight = false
        flightTarget = nil
        flightTimer = 0
        flightAttackTargetID = nil
    }
}
