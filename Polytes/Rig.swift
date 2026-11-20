import CoreGraphics

/// Las 11 articulaciones del cuerpo, en el orden del esqueleto original.
enum Joint: String, CaseIterable {
    case hip, neck, head
    case elbowR, handR, elbowL, handL
    case kneeR, footR, kneeL, footL
}

/// Un hueso: une una articulación con su padre a una distancia fija.
/// La cabeza es un caso especial: su distancia al cuello es el radio.
struct Bone {
    let joint: Joint
    let parent: Joint
    let length: Double
}

enum Rig {
    /// Huesos en orden de resolución (los padres van antes que los hijos).
    static let bones: [Bone] = [
        Bone(joint: .neck, parent: .hip, length: C.torsoLength),
        Bone(joint: .head, parent: .neck, length: 0), // se sustituye por el radio de la cabeza
        Bone(joint: .elbowR, parent: .neck, length: C.upperArmLength),
        Bone(joint: .handR, parent: .elbowR, length: C.forearmLength),
        Bone(joint: .elbowL, parent: .neck, length: C.upperArmLength),
        Bone(joint: .handL, parent: .elbowL, length: C.forearmLength),
        Bone(joint: .kneeR, parent: .hip, length: C.upperLegLength),
        Bone(joint: .footR, parent: .kneeR, length: C.lowerLegLength),
        Bone(joint: .kneeL, parent: .hip, length: C.upperLegLength),
        Bone(joint: .footL, parent: .kneeL, length: C.lowerLegLength)
    ]

    static func restLength(of bone: Bone, headRadius: Double) -> Double {
        bone.joint == .head ? headRadius : bone.length
    }

    /// Punto a una distancia y un ángulo (grados) desde un origen.
    static func polar(from origin: CGPoint, length: Double, angleDegrees: Double) -> CGPoint {
        let rad = angleDegrees * .pi / 180
        return CGPoint(x: origin.x + length * cos(rad), y: origin.y + length * sin(rad))
    }

    /// Cinemática directa: convierte una pose en posiciones de articulaciones.
    /// La caja del stickman tiene su esquina superior izquierda en (x, y).
    /// Al final se desplaza todo el cuerpo para que el pie más bajo toque
    /// exactamente la parte inferior de la caja, igual que en el original.
    /// Con `applyGrounding: false` ese desplazamiento no se aplica: es el
    /// caso de estar sentado en un borde, con las piernas colgando (v4).
    static func fkJoints(pose: Pose, x: Double, y: Double, headRadius: Double, applyGrounding: Bool = true) -> [Joint: CGPoint] {
        var joints: [Joint: CGPoint] = [:]

        let hip = CGPoint(x: x + C.stickmanWidth / 2, y: y + C.hipHeightFromTop)
        joints[.hip] = hip

        let neck = polar(from: hip, length: C.torsoLength, angleDegrees: pose.torso)
        joints[.neck] = neck
        joints[.head] = polar(from: neck, length: headRadius, angleDegrees: pose.torso)

        let elbowR = polar(from: neck, length: C.upperArmLength, angleDegrees: pose.upperArmR)
        joints[.elbowR] = elbowR
        joints[.handR] = polar(from: elbowR, length: C.forearmLength, angleDegrees: pose.upperArmR + pose.forearmR)

        let elbowL = polar(from: neck, length: C.upperArmLength, angleDegrees: pose.upperArmL)
        joints[.elbowL] = elbowL
        joints[.handL] = polar(from: elbowL, length: C.forearmLength, angleDegrees: pose.upperArmL + pose.forearmL)

        let kneeR = polar(from: hip, length: C.upperLegLength, angleDegrees: pose.upperLegR)
        joints[.kneeR] = kneeR
        joints[.footR] = polar(from: kneeR, length: C.lowerLegLength, angleDegrees: pose.upperLegR + pose.lowerLegR)

        let kneeL = polar(from: hip, length: C.upperLegLength, angleDegrees: pose.upperLegL)
        joints[.kneeL] = kneeL
        joints[.footL] = polar(from: kneeL, length: C.lowerLegLength, angleDegrees: pose.upperLegL + pose.lowerLegL)

        // Ajuste de pies al suelo: el pie más bajo marca la base de la caja.
        if applyGrounding {
            let lowestFootY = max(joints[.footR]?.y ?? 0, joints[.footL]?.y ?? 0)
            let offsetY = (y + C.stickmanHeight) - lowestFootY - C.stroke / 2
            for joint in Joint.allCases {
                if let p = joints[joint] {
                    joints[joint] = CGPoint(x: p.x, y: p.y + offsetY)
                }
            }
        }
        return joints
    }

    /// Refleja las articulaciones horizontalmente respecto a la caja.
    /// Es el espejo que el original aplica al dibujar cuando el stickman
    /// camina hacia la derecha (la animación base mira a la izquierda).
    static func mirrored(_ joints: [Joint: CGPoint], x: Double, width: Double) -> [Joint: CGPoint] {
        var result: [Joint: CGPoint] = [:]
        for (joint, p) in joints {
            result[joint] = CGPoint(x: 2 * x + width - p.x, y: p.y)
        }
        return result
    }
}
