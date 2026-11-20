import UIKit

/// La vista del escritorio: dibuja el fondo, las ventanas, la barra
/// inferior y los stickmen, y traduce los dedos en agarres y arrastres.
/// Un CADisplayLink alimenta la simulación a paso fijo y repinta a la
/// frecuencia de la pantalla.
///
/// El dedo hace de cursor, como el ratón en el original: al agarrar se
/// conserva el desplazamiento entre el dedo y la articulación (el cuerpo
/// no salta), el punto agarrado sigue al dedo sin suavizado, y la
/// velocidad de lanzamiento se mide del movimiento real del dedo con
/// las marcas de tiempo de los eventos táctiles.
final class DesktopView: UIView {
    var simulation: Simulation? {
        didSet { setNeedsDisplay() }
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var accumulator: Double = 0

    private enum TouchContext {
        /// velocity va en pt/s (suavizado exponencial de las muestras).
        case stickman(stickman: Stickman, part: Joint, offset: CGPoint, last: CGPoint, lastTime: CFTimeInterval, velocity: CGPoint)
        case window(id: UUID, offset: CGPoint)
    }
    private var touchContexts: [ObjectIdentifier: TouchContext] = [:]
    /// Posiciones de todos los dedos activos, para la IA de represalia.
    private var fingerPositions: [ObjectIdentifier: CGPoint] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .black
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        simulation?.setBounds(bounds)
    }

    // MARK: - Bucle de dibujo

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
        accumulator = 0
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let simulation else { return }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        var frameTime = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        frameTime = min(frameTime, 0.25)

        accumulator += frameTime
        while accumulator >= C.frameDuration {
            simulation.step(dt: C.frameDuration)
            accumulator -= C.frameDuration
        }
        setNeedsDisplay()
    }

    // MARK: - Dibujo

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let simulation else { return }
        drawWallpaper(ctx, simulation: simulation)
        drawDesktopIcons(ctx)
        for window in simulation.windows {
            drawWindow(ctx, window: window)
        }
        drawTaskbar(ctx, simulation: simulation)
        // Los stickmen se dibujan siempre por encima de los iconos y de
        // las ventanas; las estelas van justo debajo de su dueño.
        for ghost in simulation.trailGhosts {
            drawFigure(
                ctx,
                joints: ghost.joints,
                color: ghost.color,
                hollowHead: ghost.hollowHead,
                headRadius: ghost.headRadius,
                alpha: CGFloat(0.35 * ghost.life / ghost.maxLife)
            )
        }
        for stickman in simulation.stickmen {
            drawStickman(ctx, stickman: stickman)
        }
        drawLasers(ctx, simulation: simulation)
        drawFireballs(ctx, simulation: simulation)
        drawParticles(ctx, simulation: simulation)
        drawChargeGlows(ctx, simulation: simulation)
    }

    private func drawWallpaper(_ ctx: CGContext, simulation: Simulation) {
        let colors = [
            UIColor(red: 0.16, green: 0.35, blue: 0.55, alpha: 1).cgColor,
            UIColor(red: 0.10, green: 0.20, blue: 0.38, alpha: 1).cgColor
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: bounds.height), options: [])

        // Brillo suave en una esquina, como un fondo de escritorio.
        ctx.saveGState()
        ctx.setFillColor(UIColor(white: 1, alpha: 0.07).cgColor)
        let glow = CGRect(x: bounds.width * 0.55, y: -bounds.height * 0.25, width: bounds.width * 0.8, height: bounds.height * 0.7)
        ctx.fillEllipse(in: glow)
        ctx.restoreGState()
    }

    private func drawDesktopIcons(_ ctx: CGContext) {
        let icons: [(String, UIColor)] = [
            ("Documentos", UIColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1)),
            ("Fotos", UIColor(red: 0.55, green: 0.80, blue: 0.45, alpha: 1)),
            ("Papelera", UIColor(white: 0.85, alpha: 1))
        ]
        let iconSize: CGFloat = 40
        var y: CGFloat = 18
        for (label, color) in icons {
            let iconRect = CGRect(x: 16, y: y, width: iconSize, height: iconSize)
            ctx.setFillColor(color.withAlphaComponent(0.85).cgColor)
            fillPath(ctx, roundedRectPath(iconRect, radius: 9))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.white
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let textSize = text.size()
            text.draw(at: CGPoint(x: 16 + (iconSize - textSize.width) / 2, y: y + iconSize + 3))
            y += iconSize + 30
        }
    }

    private func drawWindow(_ ctx: CGContext, window: DesktopWindow) {
        let rect = window.rect

        // Sombra
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
        fillPath(ctx, roundedRectPath(rect, radius: 8))
        ctx.restoreGState()

        // Barra de título
        let barRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: CGFloat(C.windowTitleBarHeight))
        ctx.saveGState()
        ctx.addPath(roundedRectPath(rect, radius: 8))
        ctx.clip()
        ctx.setFillColor(window.barColor.cgColor)
        ctx.fill(barRect)
        ctx.restoreGState()

        // Botones de la barra
        let dotColors = [
            UIColor(red: 0.95, green: 0.35, blue: 0.32, alpha: 1),
            UIColor(red: 0.98, green: 0.75, blue: 0.25, alpha: 1),
            UIColor(red: 0.35, green: 0.80, blue: 0.38, alpha: 1)
        ]
        for (i, dotColor) in dotColors.enumerated() {
            let dot = CGRect(x: rect.minX + 9 + CGFloat(i) * 17, y: rect.minY + 9, width: 11, height: 11)
            ctx.setFillColor(dotColor.cgColor)
            ctx.fillEllipse(in: dot)
        }

        // Título
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let title = NSAttributedString(string: window.title, attributes: attributes)
        let titleSize = title.size()
        title.draw(at: CGPoint(x: rect.midX - titleSize.width / 2, y: rect.minY + (CGFloat(C.windowTitleBarHeight) - titleSize.height) / 2))

        // Líneas de contenido, como si hubiera texto dentro.
        ctx.setStrokeColor(UIColor(white: 0.82, alpha: 1).cgColor)
        ctx.setLineWidth(5)
        ctx.setLineCap(.round)
        var lineY = rect.minY + CGFloat(C.windowTitleBarHeight) + 20
        var index = 0
        while lineY < rect.maxY - 14 {
            let fraction: CGFloat = [0.86, 0.70, 0.78, 0.55][index % 4]
            ctx.beginPath()
            ctx.move(to: CGPoint(x: rect.minX + 14, y: lineY))
            ctx.addLine(to: CGPoint(x: rect.minX + 14 + (rect.width - 28) * fraction, y: lineY))
            ctx.strokePath()
            lineY += 17
            index += 1
        }
    }

    private func drawTaskbar(_ ctx: CGContext, simulation: Simulation) {
        let barRect = CGRect(x: 0, y: bounds.height - CGFloat(C.taskbarHeight), width: bounds.width, height: CGFloat(C.taskbarHeight))
        ctx.setFillColor(UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.92).cgColor)
        ctx.fill(barRect)

        // Botón de inicio
        let startRect = CGRect(x: 10, y: barRect.minY + 8, width: 92, height: CGFloat(C.taskbarHeight) - 16)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.14).cgColor)
        fillPath(ctx, roundedRectPath(startRect, radius: 7))
        let startAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let startText = NSAttributedString(string: "⊞ Inicio", attributes: startAttrs)
        let startSize = startText.size()
        startText.draw(at: CGPoint(x: startRect.midX - startSize.width / 2, y: startRect.midY - startSize.height / 2))

        // Reloj
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let clockAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor(white: 0.9, alpha: 1)
        ]
        let clock = NSAttributedString(string: formatter.string(from: Date()), attributes: clockAttrs)
        let clockSize = clock.size()
        clock.draw(at: CGPoint(x: bounds.width - clockSize.width - 14, y: barRect.midY - clockSize.height / 2))
    }

    // MARK: - Dibujo del stickman y los efectos (v3)

    private func drawStickman(_ ctx: CGContext, stickman: Stickman) {
        drawFigure(
            ctx,
            joints: stickman.displayJoints(),
            color: stickman.color,
            hollowHead: stickman.hollowHead,
            headRadius: stickman.headRadius,
            alpha: 1
        )
    }

    /// Dibuja una figura completa (torso, extremidades y cabeza) a partir
    /// de unas articulaciones. Sirve para los stickmen y para sus
    /// estelas de supervelocidad.
    private func drawFigure(_ ctx: CGContext, joints: [Joint: CGPoint], color: UIColor, hollowHead: Bool, headRadius: Double, alpha: CGFloat) {
        guard let hip = joints[.hip], let neck = joints[.neck], let head = joints[.head] else { return }

        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(CGFloat(C.stroke))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Torso
        ctx.beginPath()
        ctx.move(to: neck)
        ctx.addLine(to: hip)
        ctx.strokePath()

        // Brazos y piernas como curvas que pasan cerca de la articulación
        // intermedia, con el punto de control desplazado hacia ella.
        drawLimb(ctx, from: neck, mid: joints[.elbowR], to: joints[.handR])
        drawLimb(ctx, from: neck, mid: joints[.elbowL], to: joints[.handL])
        drawLimb(ctx, from: hip, mid: joints[.kneeR], to: joints[.footR])
        drawLimb(ctx, from: hip, mid: joints[.kneeL], to: joints[.footL])

        // Cabeza
        let radius = CGFloat(headRadius)
        let headRect = CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)
        if hollowHead {
            ctx.beginPath()
            ctx.addEllipse(in: headRect)
            ctx.strokePath()
        } else {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: headRect)
        }
        ctx.restoreGState()
    }

    private func drawLimb(_ ctx: CGContext, from origin: CGPoint?, mid: CGPoint?, to end: CGPoint?) {
        guard let origin, let mid, let end else { return }
        // Punto de control: a medio camino entre la articulación real y el
        // punto medio de la línea recta, como el trazo original.
        let straightMid = CGPoint(x: origin.x + (end.x - origin.x) / 2, y: origin.y + (end.y - origin.y) / 2)
        let control = CGPoint(x: mid.x + (straightMid.x - mid.x) * 0.5, y: mid.y + (straightMid.y - mid.y) * 0.5)
        ctx.beginPath()
        ctx.move(to: origin)
        ctx.addQuadCurve(to: end, control: control)
        ctx.strokePath()
    }

    private func drawLasers(_ ctx: CGContext, simulation: Simulation) {
        for laser in simulation.lasers {
            let fade = CGFloat(max(0, laser.life / laser.maxLife))
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setStrokeColor(laser.color.withAlphaComponent(0.35 * fade).cgColor)
            ctx.setLineWidth(7)
            ctx.beginPath()
            ctx.move(to: laser.from)
            ctx.addLine(to: laser.to)
            ctx.strokePath()
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9 * fade).cgColor)
            ctx.setLineWidth(2.2)
            ctx.beginPath()
            ctx.move(to: laser.from)
            ctx.addLine(to: laser.to)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private func drawFireballs(_ ctx: CGContext, simulation: Simulation) {
        for fireball in simulation.fireballs {
            ctx.saveGState()
            let outer = CGRect(x: fireball.pos.x - 11, y: fireball.pos.y - 11, width: 22, height: 22)
            ctx.setFillColor(UIColor(red: 1, green: 0.5, blue: 0.12, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: outer)
            let inner = CGRect(x: fireball.pos.x - 6, y: fireball.pos.y - 6, width: 12, height: 12)
            ctx.setFillColor(UIColor(red: 1, green: 0.88, blue: 0.4, alpha: 1).cgColor)
            ctx.fillEllipse(in: inner)
            ctx.restoreGState()
        }
    }

    private func drawParticles(_ ctx: CGContext, simulation: Simulation) {
        for particle in simulation.particles {
            let fraction = max(0, particle.life / particle.maxLife)
            let size = CGFloat(particle.size * (0.4 + 0.6 * fraction))
            ctx.setFillColor(particle.color.withAlphaComponent(CGFloat(min(1, fraction * 1.6))).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: particle.pos.x - size / 2,
                y: particle.pos.y - size / 2,
                width: size,
                height: size
            ))
        }
    }

    /// Brillo creciente en el puño mientras se carga el superpuñetazo.
    private func drawChargeGlows(_ ctx: CGContext, simulation: Simulation) {
        for stickman in simulation.stickmen where stickman.chargingPunch {
            let joints = stickman.displayJoints()
            let hands = [joints[.handR], joints[.handL]].compactMap { $0 }
            guard let fist = hands.max(by: {
                Double($0.x - stickman.centerPoint().x) * Double(stickman.direction)
                    < Double($1.x - stickman.centerPoint().x) * Double(stickman.direction)
            }) else { continue }
            let progress = clampValue(1 - stickman.chargeTimer / C.superPunchChargeTime, 0, 1)
            let radius = CGFloat(6 + progress * 15)
            ctx.saveGState()
            ctx.setFillColor(UIColor(red: 1, green: 0.55, blue: 0.15, alpha: CGFloat(0.30 + 0.30 * progress)).cgColor)
            ctx.fillEllipse(in: CGRect(x: fist.x - radius, y: fist.y - radius, width: radius * 2, height: radius * 2))
            let core = radius * 0.45
            ctx.setFillColor(UIColor(white: 1, alpha: 0.75).cgColor)
            ctx.fillEllipse(in: CGRect(x: fist.x - core, y: fist.y - core, width: core * 2, height: core * 2))
            ctx.restoreGState()
        }
    }

    private func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// Rellena el camino actual del contexto (atajo de addPath + fillPath).
    private func fillPath(_ ctx: CGContext, _ path: CGPath) {
        ctx.addPath(path)
        ctx.fillPath()
    }

    // MARK: - Tacto

    /// El área jugable dentro de la vista: todo menos la barra inferior.
    private var playableRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - CGFloat(C.taskbarHeight)))
    }

    private func syncFingerPoints() {
        simulation?.activeFingerPoints = Array(fingerPositions.values)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let simulation else { return }
        for touch in touches {
            let point = touch.location(in: self)
            let key = ObjectIdentifier(touch)
            fingerPositions[key] = point

            // Primero se intenta agarrar un stickman por su articulación
            // más cercana al dedo, entre los que están libres (uno ya
            // agarrado por otro dedo no puede agarrarse dos veces).
            var best: (stickman: Stickman, joint: Joint, distance: Double)?
            for stickman in simulation.stickmen where !stickman.holding {
                let joints = stickman.displayJoints()
                if let nearest = BodyPhysics.nearestJoint(in: joints, to: point) {
                    if best == nil || nearest.distance < best!.distance {
                        best = (stickman, nearest.joint, nearest.distance)
                    }
                }
            }

            if let found = best, found.distance <= C.grabSearchRadius, let jointPosition = found.stickman.displayJoints()[found.joint] {
                found.stickman.beginGrab(part: found.joint)
                // El desplazamiento dedo↔articulación se conserva durante
                // todo el arrastre: el cuerpo no salta al tocarlo.
                let offset = CGPoint(x: point.x - jointPosition.x, y: point.y - jointPosition.y)
                touchContexts[key] = .stickman(
                    stickman: found.stickman,
                    part: found.joint,
                    offset: offset,
                    last: point,
                    lastTime: touch.timestamp,
                    velocity: .zero
                )
                simulation.noteFingerGrab(found.stickman, at: point)
                continue
            }

            // Si no, se intenta arrastrar una ventana por su barra de título
            // (la frontal primero).
            for window in simulation.windows.reversed() {
                let titleBar = CGRect(x: window.rect.minX, y: window.rect.minY, width: window.rect.width, height: CGFloat(C.windowTitleBarHeight))
                if titleBar.contains(point) {
                    simulation.bringWindowToFront(id: window.id)
                    let offset = CGPoint(x: point.x - window.rect.minX, y: point.y - window.rect.minY)
                    touchContexts[key] = .window(id: window.id, offset: offset)
                    break
                }
            }
        }
        syncFingerPoints()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let simulation else { return }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            // Las muestras coalescidas dan el movimiento real del dedo
            // incluso en gestos rápidos.
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            let point = samples.last?.location(in: self) ?? touch.location(in: self)
            fingerPositions[key] = point
            guard let context = touchContexts[key] else { continue }

            switch context {
            case .stickman(let stickman, let part, let offset, var last, var lastTime, var velocity):
                // Si el stickman se zafó solo (represalia), el agarre
                // deja de existir: se suelta el contexto.
                guard stickman.holding, stickman.grabPart == part else {
                    touchContexts.removeValue(forKey: key)
                    continue
                }
                for sample in samples {
                    let samplePoint = sample.location(in: self)
                    let dt = sample.timestamp - lastTime
                    if dt > 0.001 {
                        let instant = CGPoint(
                            x: (samplePoint.x - last.x) / CGFloat(dt),
                            y: (samplePoint.y - last.y) / CGFloat(dt)
                        )
                        velocity = CGPoint(x: velocity.x * 0.45 + instant.x * 0.55, y: velocity.y * 0.45 + instant.y * 0.55)
                    }
                    last = samplePoint
                    lastTime = sample.timestamp
                }
                if let ragPoint = stickman.ragPoints[part] {
                    // El punto agarrado sigue al dedo 1:1, sin suavizado,
                    // pero nunca fuera del área jugable.
                    var target = CGPoint(x: last.x - offset.x, y: last.y - offset.y)
                    target.x = CGFloat(clampValue(Double(target.x), 4, max(4, Double(playableRect.maxX) - 4)))
                    target.y = CGFloat(clampValue(Double(target.y), 4, max(4, Double(playableRect.maxY) - 4)))
                    ragPoint.pos = target
                    ragPoint.old = target
                }
                touchContexts[key] = .stickman(
                    stickman: stickman,
                    part: part,
                    offset: offset,
                    last: last,
                    lastTime: lastTime,
                    velocity: velocity
                )
            case .window(let id, let offset):
                simulation.moveWindow(id: id, toOrigin: CGPoint(x: point.x - offset.x, y: point.y - offset.y))
            }
        }
        syncFingerPoints()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        guard let simulation else { return }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            fingerPositions.removeValue(forKey: key)
            guard let context = touchContexts.removeValue(forKey: key) else { continue }
            if case .stickman(let stickman, _, _, let last, let lastTime, var velocity) = context {
                // Si el dedo llevaba quieto un instante antes de soltar,
                // el lanzamiento sale sin fuerza: la velocidad es la del
                // movimiento real, no la de un gesto ya pasado.
                if touch.timestamp - lastTime > 0.08 {
                    velocity = .zero
                }
                if stickman.holding {
                    let speed = hypot(Double(velocity.x), Double(velocity.y))
                    simulation.noteFingerRelease(stickman, speed: speed, at: last)
                    stickman.releaseGrab(dragVelocity: velocity)
                }
            }
        }
        syncFingerPoints()
    }
}
