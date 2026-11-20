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
        var rect = windows[index].rect
        rect.origin = origin
        windows[index].rect = clampedWindowRect(rect)
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

    /// Un paso de simulación (dt = paso fijo). Orden: necesidades, cerebro,
    /// animación y física, como los sistemas del diseño original.
    func step(dt: Double) {
        guard didSetupWorld else { return }
        for s in stickmen {
            Needs.update(s, dt: dt)
            Brain.update(s, worldWidth: Double(workRect.width), dt: dt)
            Animator.update(s, dt: dt)
            if s.isRagdollActive {
                stepRagdoll(s)
            } else {
                stepAnimated(s, dt: dt)
                checkGroundLost(s)
            }
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
    /// Devuelve también el intervalo horizontal de ese suelo.
    func computeGround(boxX: Double, boxWidth: Double, maxY: Double) -> (y: Double, left: Double, width: Double) {
        var best = (y: Double(workRect.maxY), left: 0.0, width: Double(workRect.width))

        for window in windows {
            let top = Double(window.rect.minY)
            if top < maxY - C.groundSnapTolerance { continue }
            for interval in visibleTopIntervals(of: window) {
                let overlaps = boxX < interval.end && boxX + boxWidth > interval.start
                if overlaps && top < best.y {
                    best = (top, Double(window.rect.minX), Double(window.rect.width))
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

        // Bordes de la pantalla
        if s.x <= 0 {
            s.x = 0
        } else if s.x + s.width >= Double(workRect.width) {
            s.x = Double(workRect.width) - s.width
        }

        // Paseo
        if s.state == .walk, let target = s.targetX {
            s.direction = target > s.x ? 1 : -1
            s.velocityX = C.defaultWalkSpeed
            s.x += s.velocityX * Double(s.direction) * dt
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

        // Solver de distancias
        for _ in 0..<C.ragdollSolverIterations {
            BodyPhysics.solveBody(points: s.ragPoints, headRadius: s.headRadius, grabPart: s.grabPart)
        }

        if s.flying {
            dampCenterVelocity(s)
        }

        updateOverlappedWindows(s)
        resolveFlyingEdgeCollision(s)
        resolveFlyingWindowCollisions(s)
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

    /// Choque de los puntos contra las ventanas que no está atravesando.
    /// La resolución desplaza el cuerpo entero hasta que su envolvente
    /// sale de la ventana por el lado del impacto, con rebote; un impacto
    /// por arriba intenta además el aterrizaje.
    private func resolveFlyingWindowCollisions(_ s: Stickman) {
        guard s.flying else { return }

        for window in windows where !s.overlapWindowIDs.contains(window.id) {
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
    private func resolveFlyingLanding(_ s: Stickman) {
        guard s.flying else { return }
        let b = ragdollBounds(s)

        let ground = computeGround(boxX: Double(b.minX), boxWidth: Double(b.width), maxY: Double(b.maxY))
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
