import CoreGraphics

/// Punto de masa con memoria de su posición anterior (integración de Verlet).
/// La velocidad no se guarda: se deduce de la diferencia entre la posición
/// actual y la anterior, como en el cuerpo físico del diseño original.
final class RagPoint {
    var pos: CGPoint
    var old: CGPoint

    init(_ position: CGPoint) {
        pos = position
        old = position
    }

    var velocity: CGPoint {
        CGPoint(x: pos.x - old.x, y: pos.y - old.y)
    }

    /// Un paso de integración: conserva la inercia con amortiguación
    /// y recibe el empuje vertical de la gravedad del ragdoll.
    func integrate() {
        let newX = pos.x + (pos.x - old.x) * C.ragdollDamping
        old.x = pos.x
        pos.x = newX

        let newY = pos.y + (pos.y - old.y) * C.ragdollDamping + C.ragdollAcceleration * C.frameDuration
        old.y = pos.y
        pos.y = newY
    }
}

enum BodyPhysics {
    /// Crea los puntos físicos a partir de unas articulaciones ya calculadas.
    static func makeRagPoints(from joints: [Joint: CGPoint]) -> [Joint: RagPoint] {
        var points: [Joint: RagPoint] = [:]
        for (joint, position) in joints {
            points[joint] = RagPoint(position)
        }
        return points
    }

    /// Una pasada del solver: recorre los huesos en orden y corrige las
    /// distancias que no coinciden con su longitud de reposo.
    static func solveBody(points: [Joint: RagPoint], headRadius: Double, grabPart: Joint?) {
        for bone in Rig.bones {
            guard let origin = points[bone.parent], let end = points[bone.joint] else { continue }
            let rest = Rig.restLength(of: bone, headRadius: headRadius)
            if grabPart == bone.parent {
                solveBone(origin: origin, end: end, rest: rest, grabbedEnd: .origin)
            } else if grabPart == bone.joint {
                solveBone(origin: origin, end: end, rest: rest, grabbedEnd: .end)
            } else {
                solveBone(origin: origin, end: end, rest: rest, grabbedEnd: nil)
            }
        }
    }

    private enum GrabbedEnd { case origin, end }

    /// Corrección de un hueso. Si un extremo está agarrado, ese extremo no
    /// se mueve y el otro absorbe toda la corrección; si no, se reparte.
    private static func solveBone(origin: RagPoint, end: RagPoint, rest: Double, grabbedEnd: GrabbedEnd?) {
        let dx = origin.pos.x - end.pos.x
        let dy = origin.pos.y - end.pos.y
        let distance = sqrt(dx * dx + dy * dy)
        if distance == 0 { return }

        let error = distance - rest
        let dirX = dx / distance
        let dirY = dy / distance

        switch grabbedEnd {
        case nil:
            let adjustX = (error / 2) * dirX * C.ragdollStiffness
            let adjustY = (error / 2) * dirY * C.ragdollStiffness
            origin.pos.x -= adjustX
            origin.pos.y -= adjustY
            end.pos.x += adjustX
            end.pos.y += adjustY
        case .origin:
            end.pos.x += error * dirX * C.ragdollStiffness
            end.pos.y += error * dirY * C.ragdollStiffness
        case .end:
            origin.pos.x -= error * dirX * C.ragdollStiffness
            origin.pos.y -= error * dirY * C.ragdollStiffness
        }
    }

    /// Aplica un giro al cuerpo modificando las posiciones anteriores de los
    /// puntos con un desplazamiento tangencial alrededor del centro de masas.
    /// Es lo que hace que al lanzar el stickman salga girando.
    static func applySpin(points: [Joint: RagPoint], angularVelocity: Double) {
        let all = Array(points.values)
        guard !all.isEmpty else { return }
        let centerX = all.reduce(0) { $0 + $1.pos.x } / Double(all.count)
        let centerY = all.reduce(0) { $0 + $1.pos.y } / Double(all.count)

        for point in all {
            let radiusX = point.pos.x - centerX
            let radiusY = point.pos.y - centerY
            point.old.x += radiusY * angularVelocity
            point.old.y -= radiusX * angularVelocity
        }
    }

    /// La articulación más cercana a un punto, con su distancia.
    /// Devuelve nil si no hay ninguna articulación registrada.
    static func nearestJoint(in joints: [Joint: CGPoint], to point: CGPoint) -> (joint: Joint, distance: Double)? {
        var best: (joint: Joint, distance: Double)?
        for (joint, position) in joints {
            let dx = position.x - point.x
            let dy = position.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if best == nil || distance < best!.distance {
                best = (joint, distance)
            }
        }
        return best
    }
}
