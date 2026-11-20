import CoreGraphics
import UIKit

/// Una ventana flotante del escritorio. Es un sólido: su borde superior
/// sirve de suelo y su rectángulo repele al cuerpo físico en vuelo.
struct DesktopWindow: Identifiable {
    let id = UUID()
    var rect: CGRect
    var title: String
    var barColor: UIColor
}

/// El mundo: un escritorio dentro de la app con su barra inferior, sus
/// ventanas arrastrables y sus stickmen. Avanza a paso fijo, como el
/// bucle original, y concentra toda la física y las decisiones.
final class Simulation: ObservableObject {
    @Published var stickmen: [Stickman] = []

    /// Ventanas ordenadas de atrás hacia delante (la última es la frontal).
    var windows: [DesktopWindow] = []

    /// Límites completos de la vista.
    var bounds: CGRect = .zero
    private var didSetupWorld = false

    /// Reloj de la simulación (segundos de paso fijo acumulados).
    private(set) var time: Double = 0

    // Efectos visuales y proyectiles (v3)
    var particles: [Particle] = []
    var fireballs: [Fireball] = []
    var lasers: [Laser] = []
    var trailGhosts: [TrailGhost] = []

    // Dedos del usuario (v3): posiciones activas en pantalla y la última
    // conocida, para que un stickman irritado pueda contraatacar el punto.
    var activeFingerPoints: [CGPoint] = []
    private(set) var lastFingerPoint: CGPoint?
    private(set) var lastFingerTimestamp: Double = -100

    func stickman(byID id: UUID?) -> Stickman? {
        guard let id else { return nil }
        return stickmen.first { $0.id == id }
    }

    /// Área útil: la pantalla menos la barra inferior. Su borde inferior
    /// es el suelo base, igual que el área de trabajo del escritorio real.
    var workRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - C.taskbarHeight))
    }

    // MARK: - Escenario

    func setBounds(_ newBounds: CGRect) {
        guard newBounds.width > 0, newBounds.height > 0 else { return }
        let sizeChanged = newBounds.size != bounds.size
        bounds = newBounds
        if !didSetupWorld {
            didSetupWorld = true
            setupDefaultWindows()
            addStickman(name: "Polytes", color: .black, hollowHead: true)
        } else if sizeChanged {
            clampWindowsToWorld()
            for s in stickmen {
                s.x = clampValue(s.x, 0, max(0, workRect.width - s.width))
            }
        }
    }

    /// Reparto inicial pensado para el escritorio apaisado de la v2: las
    /// tres ventanas quedan separadas por huecos anchos, a alturas
    /// escalonadas en la mitad superior, y el suelo junto a la barra
    /// inferior queda libre de punta a punta para caminar.
    private func setupDefaultWindows() {
        let w = workRect.width
        let h = workRect.height
        let winW = min(260, max(200, w * 0.27))
        let winH = min(130, max(105, h * 0.34))
        windows = [
            DesktopWindow(
                // A la izquierda, dejando libres los iconos del escritorio.
                rect: CGRect(x: max(68, w * 0.06), y: max(56, h * 0.14), width: winW, height: winH),
                title: "Explorador",
                barColor: UIColor(red: 0.36, green: 0.55, blue: 0.85, alpha: 1)
            ),
            DesktopWindow(
                // A la derecha, un poco más pequeña y alta.
                rect: CGRect(x: w * 0.68, y: max(50, h * 0.11), width: winW * 0.92, height: winH * 0.92),
                title: "Notas",
                barColor: UIColor(red: 0.95, green: 0.75, blue: 0.30, alpha: 1)
            ),
            DesktopWindow(
                // En el centro, más baja: un peldaño entre las otras dos.
                rect: CGRect(x: w * 0.37, y: h * 0.46, width: winW, height: winH * 0.96),
                title: "Música",
                barColor: UIColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1)
            )
        ]
    }

    private func clampWindowsToWorld() {
        for i in windows.indices {
            windows[i].rect = clampedWindowRect(windows[i].rect)
        }
    }

    func clampedWindowRect(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = clampValue(Double(r.origin.x), 0, max(0, Double(workRect.width - r.width)))
        r.origin.y = clampValue(Double(r.origin.y), 0, max(0, Double(workRect.height - r.height)))
        return r
    }

    func bringWindowToFront(id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }), index != windows.count - 1 else { return }
        let window = windows.remove(at: index)
        windows.append(window)
    }

    func moveWindow(id: UUID, toOrigin origin: CGPoint) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let oldRect = windows[index].rect
        var rect = oldRect
        rect.origin = origin
        let newRect = clampedWindowRect(rect)
        windows[index].rect = newRect

        // La ventana es una plataforma: quien esté de pie sobre ella se
        // mueve con ella (antes el cuerpo se quedaba flotando en el aire
        // hasta salirse por completo del intervalo y caer de golpe).
        let deltaX = Double(newRect.minX - oldRect.minX)
        let deltaY = Double(newRect.minY - oldRect.minY)
        guard deltaX != 0 || deltaY != 0 else { return }
        for s in stickmen where !s.isRagdollActive {
            guard let groundY = s.groundY, abs(groundY - Double(oldRect.minY)) < 1.5 else { continue }
            let overlapsTop = s.x + s.width > Double(oldRect.minX) && s.x < Double(oldRect.maxX)
            guard overlapsTop else { continue }
            s.x += deltaX
            s.y += deltaY
            s.groundY = Double(newRect.minY)
            if let target = s.targetX {
                s.targetX = target + deltaX
            }
        }
    }

    // MARK: - Stickmen

    @discardableResult
    func addStickman(name: String, color: UIColor, hollowHead: Bool) -> Stickman {
        // Aparecen de pie sobre el suelo, repartidos por el ancho del
        // escritorio (30 %, 50 % y 70 %) para no amontonarse.
        let slot = Double(stickmen.count % 3)
        let centerX = Double(workRect.width) * (0.30 + 0.20 * slot)
        let spawnX = clampValue(centerX - C.stickmanWidth / 2, 0, max(0, Double(workRect.width) - C.stickmanWidth))
        let spawnY = Double(workRect.maxY) - C.stickmanHeight
        let stickman = Stickman(
            name: name,
            color: color,
            hollowHead: hollowHead,
            spawnX: spawnX,
            spawnY: spawnY,
            worldWidth: Double(workRect.width)
        )
        stickmen.append(stickman)
        return stickman
    }

    func removeStickman(id: UUID) {
        stickmen.removeAll { $0.id == id }
    }

    // MARK: - Bucle principal

    /// Un paso de simulación (dt = paso fijo). Orden: los cargados se
    /// colocan sobre su portador; después necesidades, combate (v3),
    /// cerebro, animación y física, como los sistemas del diseño original.
    func step(dt: Double) {
        guard didSetupWorld else { return }
        time += dt

        // Superfuerza: el cuerpo del cargado cuelga sobre la cabeza de
        // su portador, sin física propia mientras tanto.
        for s in stickmen where s.carriedByID != nil {
            if let carrier = stickman(byID: s.carriedByID), carrier.carryingID == s.id, !s.holding {
                positionCarried(s, carrier: carrier)
            } else {
                // El portador desapareció o lo soltó: cae.
                s.carriedByID = nil
                if !s.holding {
                    s.flying = true
                }
            }
        }

        for s in stickmen {
            Needs.update(s, dt: dt)
            Combat.update(s, sim: self, dt: dt)
            if !s.isInCombat && s.carriedByID == nil {
                Brain.update(s, worldWidth: Double(workRect.width), dt: dt)
            }
            Animator.update(s, dt: dt)
            if s.carriedByID != nil {
                continue
            }
            if s.isRagdollActive {
                stepRagdoll(s)
            } else {
                stepAnimated(s, dt: dt)
                checkGroundLost(s)
            }
        }

        updateEffects(dt: dt)
    }

    // MARK: - Dedos e irritación (v3)

    /// El usuario acaba de agarrar a un stickman: su irritación sube.
    func noteFingerGrab(_ s: Stickman, at point: CGPoint) {
        s.irritation = min(100, s.irritation + C.irritationGrabGain)
        lastFingerPoint = point
        lastFingerTimestamp = time
    }

    /// El usuario suelta a un stickman: un lanzamiento fuerte irrita
    /// mucho más que una suelta suave.
    func noteFingerRelease(_ s: Stickman, speed: Double, at point: CGPoint) {
        if speed > 500 {
            s.irritation = min(100, s.irritation + min(35, speed / 45))
        } else {
            s.irritation = min(100, s.irritation + 4)
        }
        lastFingerPoint = point
        lastFingerTimestamp = time
    }

    /// El punto del dedo al que apunta una represalia: el dedo activo
    /// más cercano, o el último conocido si es reciente.
    func fingerTargetPoint(for s: Stickman) -> CGPoint? {
        let center = s.centerPoint()
        if let nearest = activeFingerPoints.min(by: {
            hypot(Double($0.x - center.x), Double($0.y - center.y))
                < hypot(Double($1.x - center.x), Double($1.y - center.y))
        }) {
            return nearest
        }
        if let last = lastFingerPoint, time - lastFingerTimestamp < 4 {
            return last
        }
        return nil
    }

    // MARK: - Golpes y peleas (v3)

    enum HitOutcome {
        case landed, blocked, dodged, ignored
    }

    /// Aplica un golpe a un stickman: defensa (bloqueo o esquiva con
    /// supervelocidad) si está en pie y en combate, o impacto completo
    /// que lo siembra en ragdoll con el impulso y el giro dados
    /// (impulso en pt por paso). Un impacto completo da la pelea por
    /// terminada, con enfriamiento largo para ambos.
    @discardableResult
    func applyHit(to target: Stickman, impulse: CGPoint, spin: Double, from attacker: Stickman?) -> HitOutcome {
        // En manos del usuario o cargado por otro: intocable.
        if target.holding || target.carriedByID != nil {
            return .ignored
        }

        if let attacker, !target.isRagdollActive && target.opponentID != nil {
            let roll = Double.random(in: 0..<1)
            let dodgeChance = 0.16 + Double(target.energy) / 400
            let blockChance = 0.30 + (attacker.chargingPunch ? 0.15 : 0)
            if roll < dodgeChance {
                startDodge(target, awayFrom: attacker)
                return .dodged
            }
            if roll < dodgeChance + blockChance {
                target.blockingTimer = 0.35
                target.setActionPose(Animations.blockPose, duration: 0.3)
                target.externalPushX = Double(impulse.x) / C.frameDuration * 0.22
                spawnSparks(at: target.centerPoint(), count: 5, color: .white)
                return .blocked
            }
        }

        if !target.isRagdollActive {
            target.seedRagdoll()
        }
        target.cutPoweredFlight()
        target.flying = true
        target.chargingPunch = false
        for point in target.ragPoints.values {
            point.old.x = point.pos.x - impulse.x
            point.old.y = point.pos.y - impulse.y
        }
        BodyPhysics.applySpin(points: target.ragPoints, angularVelocity: spin)
        target.state = .idle
        target.targetX = nil
        spawnSparks(at: target.centerPoint(), count: 8, color: .orange)

        if let attacker, attacker.opponentID == target.id || target.opponentID == attacker.id {
            endFight(attacker, target)
        } else if target.opponentID != nil {
            if let other = stickman(byID: target.opponentID) {
                endFight(target, other)
            }
            target.opponentID = nil
        }
        return .landed
    }

    /// Esquiva con supervelocidad: dash lateral alejándose del atacante.
    func startDodge(_ s: Stickman, awayFrom attacker: Stickman?) {
        var dir = Double(s.direction)
        if let attacker {
            dir = s.centerPoint().x >= attacker.centerPoint().x ? 1 : -1
        }
        s.dashVelocityX = dir * C.dashSpeed * 0.9
        s.dashTimer = C.dashDuration
        s.dashHitTargetID = nil
        s.setActionPose(Animations.dashPose, duration: 0.2)
    }

    /// Cierra una pelea: sin rival, sin carga, y enfriamiento largo.
    func endFight(_ a: Stickman, _ b: Stickman) {
        for s in [a, b] {
            s.opponentID = nil
            s.fightTimer = 0
            s.chargingPunch = false
            s.fightCooldown = Double.random(in: C.fightCooldownMin...C.fightCooldownMax)
            if s.flightAttackTargetID != nil {
                s.cutPoweredFlight()
            }
        }
    }

    /// Coloca el cuerpo del cargado con la cadera sobre la cabeza del
    /// portador, conservando su pose sembrada y sin velocidad propia.
    private func positionCarried(_ s: Stickman, carrier: Stickman) {
        let anchor = carrier.displayJoints()[.neck] ?? carrier.centerPoint()
        let target = CGPoint(x: anchor.x, y: anchor.y - CGFloat(C.stickmanHeight) * 0.62)
        guard let hip = s.ragPoints[.hip] else { return }
        let dx = target.x - hip.pos.x
        let dy = target.y - hip.pos.y
        for point in s.ragPoints.values {
            point.pos.x += dx
            point.pos.y += dy
            point.old = point.pos
        }
        // La caja sigue al cuerpo para los cálculos de centro y dibujo.
        let b = ragdollBounds(s)
        s.x = Double(b.minX)
        s.y = Double(b.minY)
        s.width = Double(b.width)
        s.height = Double(b.height)
    }

    /// El lanzamiento del cargado: sale volando en la dirección a la que
    /// mira el portador, con giro, y la pelea se da por terminada.
    func throwCarried(_ carrier: Stickman, _ thrown: Stickman) {
        carrier.carryingID = nil
        thrown.carriedByID = nil
        thrown.flying = true
        let dir = Double(carrier.direction)
        for point in thrown.ragPoints.values {
            point.old.x = point.pos.x - CGFloat(dir * 15)
            point.old.y = point.pos.y + 11
        }
        BodyPhysics.applySpin(points: thrown.ragPoints, angularVelocity: dir * 0.12)
        endFight(carrier, thrown)
    }

    // MARK: - Efectos y proyectiles (v3)

    func emitParticle(pos: CGPoint, vel: CGPoint, life: Double, size: Double, color: UIColor, gravityScale: Double = 0, drag: Double = 0) {
        guard particles.count < C.maxParticles else { return }
        particles.append(Particle(pos: pos, vel: vel, life: life, maxLife: life, size: size, color: color, gravityScale: gravityScale, drag: drag))
    }

    /// Estallido de chispas en un punto (impactos, puñetazos al aire).
    func spawnSparks(at point: CGPoint, count: Int, color: UIColor) {
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(2 * Double.pi))
            let speed = Double.random(in: 60...260)
            emitParticle(
                pos: point,
                vel: cgPoint(cos(angle) * speed, sin(angle) * speed),
                life: Double.random(in: 0.25...0.5),
                size: Double.random(in: 2.5...5),
                color: color,
                gravityScale: 0.4,
                drag: 2
            )
        }
    }

    /// Lanza una bola de fuego desde las manos del stickman hacia un
    /// punto. Con `explodeAt` estalla al llegar (disparos contra el dedo);
    /// sin él, viaja hasta impactar con alguien o agotar su vida.
    func fireFireball(from s: Stickman, targetPoint: CGPoint, explodeAt: CGPoint?) {
        s.setActionPose(Animations.castPose, duration: 0.3)
        let joints = s.displayJoints()
        let neck = joints[.neck] ?? s.centerPoint()
        let start = CGPoint(x: neck.x + CGFloat(s.direction) * 18, y: neck.y + 4)
        let dx = Double(targetPoint.x - start.x)
        let dy = Double(targetPoint.y - start.y)
        let dist = hypot(dx, dy)
        var vel = cgPoint(Double(s.direction) * C.fireballSpeed, 0)
        if dist > 1 {
            vel = cgPoint(dx / dist * C.fireballSpeed, dy / dist * C.fireballSpeed)
        }
        fireballs.append(Fireball(ownerID: s.id, pos: start, vel: vel, targetPoint: explodeAt))
    }

    /// Dispara el láser desde los ojos: el haz es instantáneo y se
    /// dibuja desvaneciéndose; el efecto sobre el objetivo lo aplica
    /// quien dispara (o nadie, contra el dedo).
    func fireLaser(from s: Stickman, to point: CGPoint) {
        s.setActionPose(Animations.castPose, duration: 0.3)
        let start = s.displayJoints()[.head] ?? s.centerPoint()
        let color = s.color == .black ? UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1) : s.color
        lasers.append(Laser(from: start, to: point, life: 0.22, maxLife: 0.22, color: color))
        spawnSparks(at: point, count: 4, color: color)
    }

    private func burstFireball(at point: CGPoint) {
        for _ in 0..<12 {
            let angle = Double.random(in: 0..<(2 * Double.pi))
            let speed = Double.random(in: 50...300)
            let color = Bool.random()
                ? UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
                : UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
            emitParticle(
                pos: point,
                vel: cgPoint(cos(angle) * speed, sin(angle) * speed),
                life: Double.random(in: 0.25...0.55),
                size: Double.random(in: 3...7),
                color: color,
                gravityScale: 0.3,
                drag: 2.5
            )
        }
    }

    private func updateEffects(dt: Double) {
        // Partículas
        particles = particles.compactMap { particle in
            var p = particle
            p.life -= dt
            if p.life <= 0 { return nil }
            p.vel.y += CGFloat(C.gravityAcceleration * p.gravityScale * dt)
            if p.drag > 0 {
                let factor = max(0, 1 - p.drag * dt)
                p.vel.x *= CGFloat(factor)
                p.vel.y *= CGFloat(factor)
            }
            p.pos.x += p.vel.x * CGFloat(dt)
            p.pos.y += p.vel.y * CGFloat(dt)
            return p
        }

        // Bolas de fuego: avance, estela e impacto
        var remainingFireballs: [Fireball] = []
        for var fireball in fireballs {
            fireball.life -= dt
            fireball.pos.x += fireball.vel.x * CGFloat(dt)
            fireball.pos.y += fireball.vel.y * CGFloat(dt)
            emitParticle(
                pos: fireball.pos,
                vel: cgPoint(Double.random(in: -30...30), Double.random(in: -30...30)),
                life: 0.3,
                size: Double.random(in: 4...7),
                color: Bool.random()
                    ? UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
                    : UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
                gravityScale: -0.1,
                drag: 1
            )

            var exploded = fireball.life <= 0
            if let target = fireball.targetPoint,
               hypot(Double(fireball.pos.x - target.x), Double(fireball.pos.y - target.y)) < 26 {
                exploded = true
            }
            if !exploded {
                for s in stickmen where s.id != fireball.ownerID && !s.holding && s.carriedByID == nil {
                    let center = s.centerPoint()
                    if hypot(Double(fireball.pos.x - center.x), Double(fireball.pos.y - center.y)) < 34 {
                        let dir = fireball.vel.x >= 0 ? 1.0 : -1.0
                        applyHit(
                            to: s,
                            impulse: cgPoint(dir * 13, -5),
                            spin: dir * 0.06,
                            from: stickman(byID: fireball.ownerID)
                        )
                        exploded = true
                        break
                    }
                }
            }
            if exploded {
                burstFireball(at: fireball.pos)
            } else {
                remainingFireballs.append(fireball)
            }
        }
        fireballs = remainingFireballs

        // Láseres y estelas: solo se desvanecen
        lasers = lasers.compactMap { laser in
            var l = laser
            l.life -= dt
            return l.life > 0 ? l : nil
        }
        trailGhosts = trailGhosts.compactMap { ghost in
            var g = ghost
            g.life -= dt
            return g.life > 0 ? g : nil
        }
    }

    // MARK: - Suelo

    /// Intervalos visibles del borde superior de una ventana: el borde
    /// completo menos lo que tapan las ventanas que tiene delante.
    func visibleTopIntervals(of window: DesktopWindow) -> [(start: Double, end: Double)] {
        guard let index = windows.firstIndex(where: { $0.id == window.id }) else { return [] }
        var intervals: [(start: Double, end: Double)] = [(Double(window.rect.minX), Double(window.rect.maxX))]

        for other in windows[(index + 1)...] {
            let coversTopLine = other.rect.minY <= window.rect.minY && other.rect.maxY > window.rect.minY
            if !coversTopLine { continue }
            let cover = (start: Double(other.rect.minX), end: Double(other.rect.maxX))
            intervals = intervals.flatMap { subtractInterval($0, covering: cover) }
        }
        return intervals
    }

    private func subtractInterval(
        _ original: (start: Double, end: Double),
        covering: (start: Double, end: Double)
    ) -> [(start: Double, end: Double)] {
        if covering.end <= original.start || covering.start >= original.end {
            return [original]
        }
        var remaining: [(start: Double, end: Double)] = []
        if covering.start > original.start {
            remaining.append((original.start, covering.start))
        }
        if covering.end < original.end {
            remaining.append((covering.end, original.end))
        }
        return remaining
    }

    /// El suelo bajo una caja: el candidato más alto entre el suelo base y
    /// los bordes superiores visibles de las ventanas que la caja pisa y
    /// que no quedan por encima de sus pies más allá de la tolerancia.
    /// Devuelve también el intervalo horizontal de ese suelo: el tramo
    /// visible que realmente coincidió, no el ancho entero de la ventana
    /// (antes, la parte tapada por otra ventana también contaba como
    /// apoyo y el stickman caminaba flotando sobre ella).
    func computeGround(boxX: Double, boxWidth: Double, maxY: Double) -> (y: Double, left: Double, width: Double) {
        var best = (y: Double(workRect.maxY), left: 0.0, width: Double(workRect.width))

        for window in windows {
            let top = Double(window.rect.minY)
            if top < maxY - C.groundSnapTolerance { continue }
            for interval in visibleTopIntervals(of: window) {
                let overlaps = boxX < interval.end && boxX + boxWidth > interval.start
                if overlaps && top < best.y {
                    best = (top, interval.start, interval.end - interval.start)
                }
            }
        }
        return best
    }

    // MARK: - Física en modo animación

    private func stepAnimated(_ s: Stickman, dt: Double) {
        // Gravedad
        s.velocityY += C.gravityAcceleration * dt
        s.y += s.velocityY * dt

        // Suelo
        let feetY = s.y + s.height
        let ground = computeGround(boxX: s.x, boxWidth: s.width, maxY: feetY)

        let wasStanding = s.groundY != nil && feetY >= s.groundY! - C.groundSnapTolerance
        let groundVanished = wasStanding && ground.y > s.groundY! + C.groundSnapTolerance

        if groundVanished {
            // El suelo desapareció (ventana movida o cerrada): el cuerpo
            // pasa a físico desde la pose actual y cae.
            s.seedRagdoll()
            s.flying = true
            return
        }

        s.groundY = ground.y
        s.groundLimit = (ground.left, ground.width)

        if feetY >= ground.y {
            s.velocityY = 0
            s.y = ground.y - s.height
        }

        // Empuje externo (v3): resbalón al bloquear o abalanzamiento
        // fallido; se consume con caída exponencial.
        if s.externalPushX != 0 {
            s.x += s.externalPushX * dt
            s.externalPushX *= exp(-5 * dt)
            if abs(s.externalPushX) < 4 {
                s.externalPushX = 0
            }
        }

        // Movimiento horizontal: dash de supervelocidad o paseo normal.
        if s.dashTimer > 0 {
            s.dashTimer -= dt
            s.x += s.dashVelocityX * dt
            trailGhosts.append(TrailGhost(
                joints: s.displayJoints(),
                color: s.color,
                hollowHead: s.hollowHead,
                headRadius: s.headRadius,
                life: 0.22,
                maxLife: 0.22
            ))
            // Embestida: si el dash alcanza a su objetivo, el golpe conecta.
            if let targetID = s.dashHitTargetID, let target = stickman(byID: targetID) {
                let dx = abs(Double(target.centerPoint().x - s.centerPoint().x))
                let dy = abs(Double(target.centerPoint().y - s.centerPoint().y))
                if dx < 72 && dy < 90 && !target.isRagdollActive {
                    let dir = s.dashVelocityX >= 0 ? 1.0 : -1.0
                    applyHit(to: target, impulse: cgPoint(dir * 15, -7), spin: dir * 0.07, from: s)
                    s.dashHitTargetID = nil
                    s.dashTimer = 0
                }
            }
        } else if s.state == .walk, let target = s.targetX {
            s.direction = target > s.x ? 1 : -1
            s.velocityX = C.defaultWalkSpeed
            s.x += s.velocityX * Double(s.direction) * dt
        }

        // Bordes de la pantalla (después de moverse: un dash rápido no
        // debe asomar fuera ni un fotograma).
        if s.x <= 0 {
            s.x = 0
        } else if s.x + s.width >= Double(workRect.width) {
            s.x = Double(workRect.width) - s.width
        }
    }

    /// Si el stickman queda por completo fuera del intervalo de su suelo
    /// (por ejemplo, al caminar más allá del borde de una ventana),
    /// el suelo deja de sujetarlo y cae como cuerpo físico.
    private func checkGroundLost(_ s: Stickman) {
        if s.flying || s.holding { return }
        let (left, width) = s.groundLimit
        if s.x > left + width || s.x + s.width < left {
            s.seedRagdoll()
            s.flying = true
        }
    }

    // MARK: - Física ragdoll

    private func ragdollBounds(_ s: Stickman) -> CGRect {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for (joint, point) in s.ragPoints {
            let radius = joint == .head ? s.headRadius : C.ragPointRadius
            minX = min(minX, Double(point.pos.x) - radius)
            maxX = max(maxX, Double(point.pos.x) + radius)
            minY = min(minY, Double(point.pos.y) - radius)
            maxY = max(maxY, Double(point.pos.y) + radius)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func stepRagdoll(_ s: Stickman) {
        // Integración de los puntos (el agarrado queda fijo en el dedo)
        for (joint, point) in s.ragPoints where joint != s.grabPart {
            point.integrate()
        }

        // Vuelo con motor (v3): la velocidad media del cuerpo se orienta
        // hacia el objetivo y las manos echan llamas en sentido contrario.
        if s.poweredFlight, let target = s.flightTarget {
            steerFlight(s, target: target)
            emitFlightFlames(s)
        }

        // Solver de distancias
        for _ in 0..<C.ragdollSolverIterations {
            BodyPhysics.solveBody(points: s.ragPoints, headRadius: s.headRadius, grabPart: s.grabPart)
        }

        // En vuelo con motor, la amortiguación central no se aplica:
        // la dirección asistida ya gobierna la velocidad media.
        if s.flying && !s.poweredFlight {
            dampCenterVelocity(s)
        }

        updateOverlappedWindows(s)
        resolveFlyingEdgeCollision(s)
        resolveFlyingWindowCollisions(s)
        clampPointsToWorld(s)
        resolveFlyingLanding(s)

        if s.flying {
            let b = ragdollBounds(s)
            s.x = Double(b.minX)
            s.y = Double(b.minY)
            s.width = Double(b.width)
            s.height = Double(b.height)
        } else if !s.holding {
            // Acaba de aterrizar: la caja vuelve a su tamaño normal,
            // centrada en la cadera y apoyada en el suelo encontrado.
            s.width = C.stickmanWidth
            s.height = C.stickmanHeight
            let hipX = Double(s.ragPoints[.hip]?.pos.x ?? CGFloat(s.x))
            s.x = hipX - s.width / 2
            let ground = s.groundY ?? Double(workRect.maxY)
            s.y = ground - s.height
        }
    }

    /// Dirección asistida del vuelo con motor: ajusta la velocidad de
    /// todos los puntos hacia la velocidad deseada en dirección al
    /// objetivo, conservando la forma y el giro del cuerpo.
    private func steerFlight(_ s: Stickman, target: CGPoint) {
        let points = Array(s.ragPoints.values)
        guard !points.isEmpty else { return }
        let count = Double(points.count)
        let centerX = points.reduce(0) { $0 + Double($1.pos.x) } / count
        let centerY = points.reduce(0) { $0 + Double($1.pos.y) } / count
        let meanVX = points.reduce(0) { $0 + Double($1.velocity.x) } / count
        let meanVY = points.reduce(0) { $0 + Double($1.velocity.y) } / count

        let dx = Double(target.x) - centerX
        let dy = Double(target.y) - centerY
        let dist = hypot(dx, dy)
        var desiredX = 0.0
        var desiredY = 0.0
        if dist > 4 {
            let speedPerStep = C.flightSpeed * C.frameDuration
            desiredX = dx / dist * speedPerStep
            desiredY = dy / dist * speedPerStep
        }
        let k = 0.09
        for point in points {
            point.old.x -= CGFloat((desiredX - meanVX) * k)
            point.old.y -= CGFloat((desiredY - meanVY) * k)
        }
    }

    /// Llamas de propulsión desde las manos: salen hacia abajo y en
    /// sentido contrario al movimiento, como los chorros de
    /// The Second Coming.
    private func emitFlightFlames(_ s: Stickman) {
        for joint in [Joint.handR, Joint.handL] {
            guard let point = s.ragPoints[joint] else { continue }
            let vel = point.velocity
            emitParticle(
                pos: point.pos,
                vel: cgPoint(
                    -Double(vel.x) * 6 + Double.random(in: -25...25),
                    Double.random(in: 50...120)
                ),
                life: Double.random(in: 0.18...0.32),
                size: Double.random(in: 4...8),
                color: Bool.random()
                    ? UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
                    : UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
                gravityScale: -0.15,
                drag: 1
            )
        }
    }

    /// Amortigua solo la velocidad media del cuerpo (la traslación);
    /// la velocidad relativa de cada punto (el giro) se conserva.
    private func dampCenterVelocity(_ s: Stickman) {
        let points = Array(s.ragPoints.values)
        guard !points.isEmpty else { return }
        let meanVX = points.reduce(0) { $0 + $1.velocity.x } / Double(points.count)
        let meanVY = points.reduce(0) { $0 + $1.velocity.y } / Double(points.count)
        for point in points {
            point.old.x += CGFloat(meanVX * (1 - C.ragdollCenterDampingX))
            point.old.y += CGFloat(meanVY * (1 - C.ragdollCenterDampingY))
        }
    }

    /// Mantiene la lista de ventanas atravesadas: al agarrar se añaden las
    /// que toca la envolvente; en vuelo, las que contienen la cadera; una
    /// ventana sale de la lista cuando la envolvente deja de tocarla.
    private func updateOverlappedWindows(_ s: Stickman) {
        let b = ragdollBounds(s)

        if s.holding {
            for window in windows where !s.overlapWindowIDs.contains(window.id) {
                if b.intersects(window.rect) {
                    s.overlapWindowIDs.append(window.id)
                }
            }
        }

        if s.flying {
            guard let hip = s.ragPoints[.hip]?.pos else { return }
            for window in windows {
                if s.overlapWindowIDs.contains(window.id) {
                    if !b.intersects(window.rect) {
                        s.overlapWindowIDs.removeAll { $0 == window.id }
                    }
                    continue
                }
                if b.intersects(window.rect) && window.rect.contains(hip) {
                    s.overlapWindowIDs.append(window.id)
                }
            }
        }
    }

    private func moveAllPoints(_ s: Stickman, offsetX: Double, offsetY: Double) {
        for point in s.ragPoints.values {
            point.pos.x += CGFloat(offsetX)
            point.pos.y += CGFloat(offsetY)
        }
    }

    private func bounceAllPoints(_ s: Stickman, axisX: Bool, axisY: Bool) {
        for point in s.ragPoints.values {
            if axisX {
                let vx = point.pos.x - point.old.x
                point.old.x = point.pos.x + vx * CGFloat(C.ragdollBounceFactor)
            }
            if axisY {
                let vy = point.pos.y - point.old.y
                point.old.y = point.pos.y + vy * CGFloat(C.ragdollBounceFactor)
            }
        }
    }

    /// Choque contra los bordes izquierdo, derecho y superior del área útil:
    /// todo el cuerpo retrocede dentro y rebota.
    private func resolveFlyingEdgeCollision(_ s: Stickman) {
        guard s.flying else { return }
        let b = ragdollBounds(s)

        if Double(b.minX) < 0 {
            moveAllPoints(s, offsetX: -Double(b.minX), offsetY: 0)
            bounceAllPoints(s, axisX: true, axisY: false)
        } else if Double(b.maxX) > Double(workRect.width) {
            moveAllPoints(s, offsetX: Double(workRect.width) - Double(b.maxX), offsetY: 0)
            bounceAllPoints(s, axisX: true, axisY: false)
        }

        if Double(b.minY) < 0 {
            moveAllPoints(s, offsetX: 0, offsetY: -Double(b.minY))
            bounceAllPoints(s, axisX: false, axisY: true)
        }
    }

    /// Red de seguridad por punto: ningún punto del ragdoll puede hundirse
    /// bajo el suelo base ni salir del mundo por ningún borde, ni siquiera
    /// mientras el usuario lo arrastra con el dedo (antes un cuerpo
    /// agarrado podía quedar medio hundido en una esquina). Al recortar
    /// se anula la velocidad contra ese borde para que no vibre.
    private func clampPointsToWorld(_ s: Stickman) {
        let floorY = Double(workRect.maxY)
        let maxX = Double(workRect.width)
        for (joint, point) in s.ragPoints {
            let radius = joint == .head ? s.headRadius : C.ragPointRadius
            if Double(point.pos.x) < radius {
                point.pos.x = CGFloat(radius)
                point.old.x = point.pos.x
            } else if Double(point.pos.x) > maxX - radius {
                point.pos.x = CGFloat(maxX - radius)
                point.old.x = point.pos.x
            }
            if Double(point.pos.y) < radius {
                point.pos.y = CGFloat(radius)
                point.old.y = point.pos.y
            } else if Double(point.pos.y) > floorY - radius {
                point.pos.y = CGFloat(floorY - radius)
                point.old.y = point.pos.y
            }
        }
    }

    /// Choque de los puntos contra las ventanas que no está atravesando.
    /// La resolución desplaza el cuerpo entero hasta que su envolvente
    /// sale de la ventana por el lado del impacto, con rebote; un impacto
    /// por arriba intenta además el aterrizaje. Superfuerza (v3): un
    /// impacto muy rápido empuja la ventana en la dirección del golpe.
    private func resolveFlyingWindowCollisions(_ s: Stickman) {
        guard s.flying else { return }

        var nudgedWindowIDs = Set<UUID>()
        for windowIndex in windows.indices where !s.overlapWindowIDs.contains(windows[windowIndex].id) {
            let window = windows[windowIndex]
            let visibleIntervals = visibleTopIntervals(of: window)

            for joint in Joint.allCases {
                guard let point = s.ragPoints[joint] else { continue }
                let radius = joint == .head ? s.headRadius : C.ragPointRadius

                guard let hit = detectPointWindowCollision(point: point, radius: radius, window: window) else { continue }

                var xSide = hit.xSide
                var ySide = hit.ySide

                if ySide == .top {
                    let collisionX = Double(point.old.x + (point.pos.x - point.old.x) * CGFloat(hit.time))
                    let pointVisible = visibleIntervals.contains { $0.start <= collisionX && collisionX <= $0.end }
                    if !pointVisible {
                        ySide = nil
                    }
                }

                if xSide == nil && ySide == nil { continue }

                let b = ragdollBounds(s)

                if let side = xSide {
                    switch side {
                    case .left:
                        moveAllPoints(s, offsetX: Double(window.rect.minX) - Double(b.maxX), offsetY: 0)
                    case .right:
                        moveAllPoints(s, offsetX: Double(window.rect.maxX) - Double(b.minX), offsetY: 0)
                    default:
                        break
                    }
                    bounceAllPoints(s, axisX: true, axisY: false)
                }

                if let side = ySide {
                    switch side {
                    case .top:
                        moveAllPoints(s, offsetX: 0, offsetY: Double(window.rect.minY) - Double(b.maxY))
                        bounceAllPoints(s, axisX: false, axisY: true)
                        resolveFlyingLanding(s)
                    case .bottom:
                        moveAllPoints(s, offsetX: 0, offsetY: Double(window.rect.maxY) - Double(b.minY))
                        bounceAllPoints(s, axisX: false, axisY: true)
                    default:
                        break
                    }
                }

                // Superfuerza (v3): un cuerpo que llega muy rápido empuja
                // la ventana en la dirección del golpe (una vez por
                // ventana y paso, para que no salga disparada).
                if (xSide != nil || ySide != nil) && !nudgedWindowIDs.contains(window.id) {
                    let hipSpeed = s.ragPoints[.hip].map {
                        hypot(Double($0.velocity.x), Double($0.velocity.y))
                    } ?? 0
                    if hipSpeed > 16 {
                        nudgedWindowIDs.insert(window.id)
                        var rect = windows[windowIndex].rect
                        if let side = xSide {
                            let push = min(10, (hipSpeed - 16) * 0.35)
                            rect.origin.x += CGFloat(side == .left ? push : -push)
                        }
                        if let side = ySide {
                            let push = min(8, (hipSpeed - 16) * 0.3)
                            rect.origin.y += CGFloat(side == .top ? push : -push)
                        }
                        windows[windowIndex].rect = clampedWindowRect(rect)
                    }
                }
            }
        }
    }

    private enum CollisionSide {
        case left, right, top, bottom
    }

    private struct PointHit {
        var xSide: CollisionSide?
        var ySide: CollisionSide?
        var time: Double
    }

    /// Detección de choque de un punto (con su radio) contra una ventana.
    /// Si el punto ya está dentro, se clasifica el lado por la penetración
    /// y la dirección del movimiento; si viene de fuera, se calcula el
    /// instante de entrada del segmento viejo→nuevo en el rectángulo
    /// expandido por el radio (método de losas).
    private func detectPointWindowCollision(point: RagPoint, radius: Double, window: DesktopWindow) -> PointHit? {
        let rect = window.rect
        let expanded = rect.insetBy(dx: CGFloat(-radius), dy: CGFloat(-radius))

        let startX = Double(point.old.x)
        let startY = Double(point.old.y)
        let deltaX = Double(point.pos.x - point.old.x)
        let deltaY = Double(point.pos.y - point.old.y)

        let startsInside = startX > Double(expanded.minX) && startX < Double(expanded.maxX)
            && startY > Double(expanded.minY) && startY < Double(expanded.maxY)

        if !startsInside {
            // Método de losas sobre el segmento de movimiento.
            var entryX = -Double.infinity
            var exitX = Double.infinity
            var entryY = -Double.infinity
            var exitY = Double.infinity

            if deltaX == 0 {
                if !(Double(expanded.minX) <= startX && startX <= Double(expanded.maxX)) { return nil }
            } else {
                let t1 = (Double(expanded.minX) - startX) / deltaX
                let t2 = (Double(expanded.maxX) - startX) / deltaX
                entryX = min(t1, t2)
                exitX = max(t1, t2)
            }

            if deltaY == 0 {
                if !(Double(expanded.minY) <= startY && startY <= Double(expanded.maxY)) { return nil }
            } else {
                let t1 = (Double(expanded.minY) - startY) / deltaY
                let t2 = (Double(expanded.maxY) - startY) / deltaY
                entryY = min(t1, t2)
                exitY = max(t1, t2)
            }

            let collisionTime = max(entryX, entryY)
            let exitTime = min(exitX, exitY)
            if collisionTime > exitTime || collisionTime < 0 || collisionTime > 1 { return nil }

            let hitX = abs(entryX - collisionTime) < 1e-9
            let hitY = abs(entryY - collisionTime) < 1e-9

            return PointHit(
                xSide: hitX ? (deltaX > 0 ? .left : .right) : nil,
                ySide: hitY ? (deltaY > 0 ? .top : .bottom) : nil,
                time: collisionTime
            )
        }

        // El punto está dentro: clasificación por lados según posición y movimiento.
        let posX = Double(point.pos.x)
        let posY = Double(point.pos.y)
        let left = Double(rect.minX)
        let right = Double(rect.maxX)
        let top = Double(rect.minY)
        let bottom = Double(rect.maxY)

        var leftCollision = posX + radius > left && posX + radius < right && deltaX > 0
        var rightCollision = posX - radius < right && posX - radius > left && deltaX < 0
        var topCollision = posY + radius > top && posY + radius < bottom && deltaY > 0
        var bottomCollision = posY - radius < bottom && posY - radius > top && deltaY < 0

        let horizontal = leftCollision || rightCollision
        let vertical = topCollision || bottomCollision

        if horizontal && vertical {
            var horizontalPenetration = Double.greatestFiniteMagnitude
            if leftCollision { horizontalPenetration = min(horizontalPenetration, posX + radius - left) }
            if rightCollision { horizontalPenetration = min(horizontalPenetration, right - (posX - radius)) }
            var verticalPenetration = Double.greatestFiniteMagnitude
            if topCollision { verticalPenetration = min(verticalPenetration, posY + radius - top) }
            if bottomCollision { verticalPenetration = min(verticalPenetration, bottom - (posY - radius)) }

            if horizontalPenetration <= verticalPenetration {
                topCollision = false
                bottomCollision = false
            } else {
                leftCollision = false
                rightCollision = false
            }
        }

        if !leftCollision && !rightCollision && !topCollision && !bottomCollision {
            return nil
        }

        return PointHit(
            xSide: leftCollision ? .left : (rightCollision ? .right : nil),
            ySide: topCollision ? .top : (bottomCollision ? .bottom : nil),
            time: 1
        )
    }

    /// Aterrizaje en vuelo: si la parte baja de la envolvente alcanza el
    /// suelo que tiene debajo, el vuelo termina y empieza la recuperación.
    /// El suelo se busca con una caja del ancho del cuerpo centrada en la
    /// cadera, no con la envolvente entera: un cuerpo que cae girando es
    /// mucho más ancho que de pie, y con su envolvente aterrizaba
    /// «enganchado» de la esquina de una ventana que apenas rozaba.
    private func resolveFlyingLanding(_ s: Stickman) {
        guard s.flying else { return }
        let b = ragdollBounds(s)

        let hipX = Double(s.ragPoints[.hip]?.pos.x ?? b.midX)
        let ground = computeGround(
            boxX: hipX - C.stickmanWidth / 2,
            boxWidth: C.stickmanWidth,
            maxY: Double(b.maxY)
        )
        s.groundY = ground.y
        s.groundLimit = (ground.left, ground.width)

        if Double(b.maxY) >= ground.y {
            s.flying = false
            onLanded(s)
        }
    }

    /// Tras aterrizar, el stickman se queda quieto un tiempo de
    /// recuperación antes de que el cerebro vuelva a decidir.
    private func onLanded(_ s: Stickman) {
        s.state = .idle
        s.targetX = nil
        s.velocityX = 0
        s.decideCooldown = C.landingRecoveryTime
        s.animationFrameIndex = 0
        s.animationTimer = 0
    }
}
