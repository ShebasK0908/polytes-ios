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

    /// Formateador del reloj de la barra: se crea una sola vez (antes se
    /// construía uno nuevo en cada fotograma, 60–120 veces por segundo).
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private enum TouchContext {
        /// velocity va en pt/s (suavizado exponencial de las muestras).
        case stickman(stickman: Stickman, part: Joint, offset: CGPoint, last: CGPoint, lastTime: CFTimeInterval, velocity: CGPoint)
        case window(id: UUID, offset: CGPoint)
    }
    private var touchContexts: [ObjectIdentifier: TouchContext] = [:]
    /// Posiciones de todos los dedos activos, para la IA de represalia.
    private var fingerPositions: [ObjectIdentifier: CGPoint] = [:]
    /// Velocidad suavizada de cada dedo (pt/s) y su última muestra:
    /// la mente (v4) percibe si el cursor se acerca rápido.
    private var fingerVelocities: [ObjectIdentifier: CGPoint] = [:]
    private var fingerSamples: [ObjectIdentifier: (point: CGPoint, time: CFTimeInterval)] = [:]

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

    /// Pausa externa (v5): mientras el creador está abierto, el
    /// escritorio deja de simular y de repintarse tras la hoja.
    func setPaused(_ paused: Bool) {
        if paused {
            stopDisplayLink()
        } else if window != nil {
            startDisplayLink()
        }
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
        // El cursor va por encima de todo: es el dedo del usuario.
        drawCursors(ctx)
    }

    // MARK: - Cursor visible (v4)

    /// En el original se ve la flecha del ratón y los stickmen
    /// interactúan con ella; aquí el dedo ES el cursor, así que se
    /// dibuja una flecha estilo PC en cada dedo activo — y una mano
    /// agarrando cuando ese dedo lleva a un stickman.
    private func drawCursors(_ ctx: CGContext) {
        for (key, point) in fingerPositions {
            var grabbing = false
            if let context = touchContexts[key], case .stickman = context {
                grabbing = true
            }
            if grabbing {
                drawGrabHand(ctx, at: point)
            } else {
                drawArrowCursor(ctx, at: point)
            }
        }
    }

    /// Flecha clásica de ratón: blanca con borde oscuro y su punta
    /// exactamente en la posición del dedo.
    private func drawArrowCursor(_ ctx: CGContext, at point: CGPoint) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 1, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        ctx.beginPath()
        ctx.move(to: point)
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + 34))
        ctx.addLine(to: CGPoint(x: point.x + 9, y: point.y + 25))
        ctx.addLine(to: CGPoint(x: point.x + 14, y: point.y + 37))
        ctx.addLine(to: CGPoint(x: point.x + 19.5, y: point.y + 34.5))
        ctx.addLine(to: CGPoint(x: point.x + 14.5, y: point.y + 22.5))
        ctx.addLine(to: CGPoint(x: point.x + 24, y: point.y + 22.5))
        ctx.closePath()
        ctx.setFillColor(UIColor(white: 1, alpha: 0.96).cgColor)
        ctx.setStrokeColor(UIColor(white: 0.12, alpha: 0.9).cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }

    /// Mano cerrada agarrando: palma redondeada, tres nudillos y pulgar,
    /// en el mismo estilo blanco con borde oscuro que la flecha.
    private func drawGrabHand(_ ctx: CGContext, at point: CGPoint) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 1, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.96).cgColor)
        // Palma
        let palm = CGRect(x: point.x - 13, y: point.y - 4, width: 27, height: 25)
        fillPath(ctx, roundedRectPath(palm, radius: 9))
        // Nudillos de los dedos cerrados y el pulgar
        for i in 0..<3 {
            let cx = point.x - 8 + CGFloat(i) * 8.5
            ctx.fillEllipse(in: CGRect(x: cx - 5.5, y: point.y - 12, width: 11, height: 11))
        }
        ctx.fillEllipse(in: CGRect(x: point.x + 9, y: point.y + 3, width: 11, height: 11))
        // Borde de la palma
        ctx.setStrokeColor(UIColor(white: 0.12, alpha: 0.9).cgColor)
        ctx.setLineWidth(1.6)
        ctx.addPath(roundedRectPath(palm, radius: 9))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawWallpaper(_ ctx: CGContext, simulation: Simulation) {
        // Cielo con degradado de cuatro paradas: azul profundo arriba,
        // horizonte claro y cálido justo sobre la barra inferior, como
        // los fondos de escritorio del vídeo de referencia.
        let colors = [
            UIColor(red: 0.07, green: 0.16, blue: 0.33, alpha: 1).cgColor,
            UIColor(red: 0.14, green: 0.33, blue: 0.56, alpha: 1).cgColor,
            UIColor(red: 0.33, green: 0.56, blue: 0.73, alpha: 1).cgColor,
            UIColor(red: 0.66, green: 0.79, blue: 0.85, alpha: 1).cgColor
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 0.75, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: bounds.height), options: [])

        // Sol suave en la esquina superior derecha (degradado radial).
        let floorY = bounds.height - CGFloat(C.taskbarHeight)
        let sunCenter = CGPoint(x: bounds.width * 0.79, y: bounds.height * 0.16)
        let sunColors = [
            UIColor(white: 1, alpha: 0.38).cgColor,
            UIColor(white: 1, alpha: 0).cgColor
        ] as CFArray
        let sunGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sunColors, locations: [0, 1])!
        ctx.drawRadialGradient(sunGradient, startCenter: sunCenter, startRadius: 0, endCenter: sunCenter, endRadius: bounds.width * 0.42, options: [])

        // Colinas lejanas: dos siluetas suaves sobre el horizonte. La
        // cordillera cercana es más clara que en la v4 (v5): un cuerpo
        // oscuro tumbado sobre el suelo se camuflaba contra ella y
        // parecía escondido tras la barra inferior.
        drawHills(ctx, floorY: floorY, width: bounds.width, baseHeight: bounds.height * 0.10, phase: 0, color: UIColor(red: 0.13, green: 0.30, blue: 0.45, alpha: 0.5))
        drawHills(ctx, floorY: floorY, width: bounds.width, baseHeight: bounds.height * 0.05, phase: 0.45, color: UIColor(red: 0.17, green: 0.34, blue: 0.48, alpha: 0.68))
    }

    /// Una cordillera de silueta: curvas cuadráticas encadenadas que
    /// suben y bajan sobre la línea del suelo.
    private func drawHills(_ ctx: CGContext, floorY: CGFloat, width: CGFloat, baseHeight: CGFloat, phase: CGFloat, color: UIColor) {
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: floorY))
        let segments = 4
        let segmentWidth = width / CGFloat(segments)
        for i in 0..<segments {
            let x0 = CGFloat(i) * segmentWidth
            let up = (i % 2 == 0)
            let peak = floorY - baseHeight * (up ? 1.0 : 0.45) - baseHeight * phase * (up ? 0.3 : 0)
            ctx.addQuadCurve(
                to: CGPoint(x: x0 + segmentWidth, y: floorY - baseHeight * 0.25),
                control: CGPoint(x: x0 + segmentWidth / 2, y: peak)
            )
        }
        ctx.addLine(to: CGPoint(x: width, y: floorY))
        ctx.closePath()
        ctx.fillPath()
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

        // Borde fino: define la ventana sobre el cielo claro (v5).
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.1, alpha: 0.16).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(roundedRectPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: 8))
        ctx.strokePath()
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

        // Contenido según la ventana: cada una sugiere su aplicación
        // (carpetas, una nota, un reproductor) en vez de líneas genéricas.
        let content = CGRect(
            x: rect.minX + 14,
            y: rect.minY + CGFloat(C.windowTitleBarHeight) + 12,
            width: rect.width - 28,
            height: rect.height - CGFloat(C.windowTitleBarHeight) - 24
        )
        switch window.title {
        case "Explorador":
            drawExplorerContent(ctx, content: content)
        case "Notas":
            drawNotesContent(ctx, content: content)
        case "Música":
            drawMusicContent(ctx, content: content)
        default:
            drawTextLines(ctx, content: content)
        }
    }

    /// Líneas de texto genéricas (reserva para ventanas sin contenido propio).
    private func drawTextLines(_ ctx: CGContext, content: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.82, alpha: 1).cgColor)
        ctx.setLineWidth(5)
        ctx.setLineCap(.round)
        var lineY = content.minY + 8
        var index = 0
        while lineY < content.maxY - 4 {
            let fraction: CGFloat = [0.86, 0.70, 0.78, 0.55][index % 4]
            ctx.beginPath()
            ctx.move(to: CGPoint(x: content.minX, y: lineY))
            ctx.addLine(to: CGPoint(x: content.minX + content.width * fraction, y: lineY))
            ctx.strokePath()
            lineY += 17
            index += 1
        }
        ctx.restoreGState()
    }

    /// Explorador: una rejilla de carpetas con su etiqueta.
    private func drawExplorerContent(_ ctx: CGContext, content: CGRect) {
        ctx.saveGState()
        let folderW: CGFloat = 46
        let folderH: CGFloat = 34
        let gapX: CGFloat = 20
        let gapY: CGFloat = 22
        var x = content.minX + 2
        var y = content.minY + 4
        var drawn = 0
        while y + folderH + 10 <= content.maxY && drawn < 6 {
            while x + folderW <= content.maxX && drawn < 6 {
                // Carpeta: pestaña + cuerpo.
                ctx.setFillColor(UIColor(red: 0.98, green: 0.78, blue: 0.30, alpha: 1).cgColor)
                fillPath(ctx, roundedRectPath(CGRect(x: x, y: y, width: folderW * 0.45, height: 10), radius: 4))
                fillPath(ctx, roundedRectPath(CGRect(x: x, y: y + 7, width: folderW, height: folderH - 7), radius: 5))
                // Etiqueta bajo la carpeta.
                ctx.setFillColor(UIColor(white: 0.75, alpha: 1).cgColor)
                fillPath(ctx, roundedRectPath(CGRect(x: x + 6, y: y + folderH + 4, width: folderW - 12, height: 5), radius: 2.5))
                x += folderW + gapX
                drawn += 1
            }
            x = content.minX + 2
            y += folderH + gapY + 6
        }
        ctx.restoreGState()
    }

    /// Notas: un título más marcado y líneas de texto, una con una
    /// palabra resaltada en amarillo.
    private func drawNotesContent(_ ctx: CGContext, content: CGRect) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        // Título
        ctx.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
        ctx.setLineWidth(7)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: content.minX, y: content.minY + 6))
        ctx.addLine(to: CGPoint(x: content.minX + content.width * 0.55, y: content.minY + 6))
        ctx.strokePath()
        // Cuerpo
        ctx.setStrokeColor(UIColor(white: 0.80, alpha: 1).cgColor)
        ctx.setLineWidth(5)
        var lineY = content.minY + 28
        var index = 0
        while lineY < content.maxY - 4 {
            let fraction: CGFloat = [0.92, 0.78, 0.85, 0.6][index % 4]
            if index == 1 {
                // Resaltado tras un tramo de la segunda línea.
                ctx.setFillColor(UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.55).cgColor)
                let hx = content.minX + content.width * 0.3
                ctx.fill(CGRect(x: hx, y: lineY - 5, width: content.width * 0.28, height: 10))
            }
            ctx.beginPath()
            ctx.move(to: CGPoint(x: content.minX, y: lineY))
            ctx.addLine(to: CGPoint(x: content.minX + content.width * fraction, y: lineY))
            ctx.strokePath()
            lineY += 17
            index += 1
        }
        ctx.restoreGState()
    }

    /// Música: carátula con su disco, título de la pista y barra de
    /// progreso con su botón de reproducción. El tamaño se adapta a la
    /// altura real del contenido (v5): antes se reservaban 34 pt para
    /// el progreso y se exigía una carátula de más de 20 pt, y con la
    /// altura que la ventana tiene en el teléfono la cuenta no salía y
    /// no se dibujaba NADA: la ventana salía blanca y vacía.
    private func drawMusicContent(_ ctx: CGContext, content: CGRect) {
        ctx.saveGState()
        let albumSize = clampValue(min(52, Double(content.height) * 0.74), 16, 52)
        let album = CGRect(x: content.minX, y: content.minY + 2, width: CGFloat(albumSize), height: CGFloat(albumSize))
        ctx.setFillColor(UIColor(red: 0.42, green: 0.30, blue: 0.68, alpha: 1).cgColor)
        fillPath(ctx, roundedRectPath(album, radius: 6))
        // El disco dentro de la carátula (proporcional a su tamaño).
        let disc = CGFloat(albumSize) * 0.48
        ctx.setFillColor(UIColor(white: 0.95, alpha: 0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: album.midX - disc / 2, y: album.midY - disc / 2, width: disc, height: disc))
        ctx.setFillColor(UIColor(red: 0.42, green: 0.30, blue: 0.68, alpha: 1).cgColor)
        let hub = disc * 0.32
        ctx.fillEllipse(in: CGRect(x: album.midX - hub / 2, y: album.midY - hub / 2, width: hub, height: hub))

        // Título y artista a la derecha de la carátula.
        let textX = album.maxX + 12
        ctx.setLineCap(.round)
        ctx.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
        ctx.setLineWidth(6)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: textX, y: album.minY + 11))
        ctx.addLine(to: CGPoint(x: min(content.maxX, textX + content.width * 0.34), y: album.minY + 11))
        ctx.strokePath()
        if albumSize > 30 {
            ctx.setStrokeColor(UIColor(white: 0.78, alpha: 1).cgColor)
            ctx.setLineWidth(5)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: textX, y: album.minY + 27))
            ctx.addLine(to: CGPoint(x: min(content.maxX, textX + content.width * 0.24), y: album.minY + 27))
            ctx.strokePath()
        }

        // Progreso: pista, parte escuchada y botón.
        let progressY = album.maxY + 16
        if progressY < content.maxY - 6 {
            ctx.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            ctx.setLineWidth(4)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: content.minX, y: progressY))
            ctx.addLine(to: CGPoint(x: content.maxX, y: progressY))
            ctx.strokePath()
            ctx.setStrokeColor(UIColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: content.minX, y: progressY))
            ctx.addLine(to: CGPoint(x: content.minX + content.width * 0.4, y: progressY))
            ctx.strokePath()
            ctx.setFillColor(UIColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: content.minX + content.width * 0.4 - 5, y: progressY - 5, width: 10, height: 10))
        }
        ctx.restoreGState()
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
        let clockAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor(white: 0.9, alpha: 1)
        ]
        let clock = NSAttributedString(string: DesktopView.clockFormatter.string(from: Date()), attributes: clockAttrs)
        let clockSize = clock.size()
        clock.draw(at: CGPoint(x: bounds.width - clockSize.width - 14, y: barRect.midY - clockSize.height / 2))
    }

    // MARK: - Dibujo del stickman y los efectos (v3)

    private func drawStickman(_ ctx: CGContext, stickman: Stickman) {
        drawContactShadow(ctx, stickman: stickman)
        drawFigure(
            ctx,
            joints: stickman.displayJoints(),
            color: stickman.color,
            hollowHead: stickman.hollowHead,
            headRadius: stickman.headRadius,
            alpha: 1
        )
    }

    /// Sombra de contacto bajo el cuerpo (v5): una elipse suave sobre su
    /// superficie de apoyo. Despega visualmente al stickman del fondo —
    /// sobre todo tumbado en el suelo, donde una línea fina se perdía
    /// contra las colinas — y da la pista de a qué altura está del suelo
    /// cuando vuela (más pequeña y tenue cuanto más alto).
    private func drawContactShadow(_ ctx: CGContext, stickman: Stickman) {
        guard let groundY = stickman.groundY else { return }
        let bodyBottom = stickman.y + stickman.height
        let gap = groundY - bodyBottom
        guard gap > -6 && gap < 190 else { return }
        let proximity = CGFloat(clampValue(1 - gap / 190, 0.25, 1))
        let width = CGFloat(max(stickman.width, 44)) * (0.55 + 0.45 * proximity)
        let rect = CGRect(
            x: CGFloat(stickman.x + stickman.width / 2) - width / 2,
            y: CGFloat(groundY) - 3.5,
            width: width,
            height: 7
        )
        ctx.saveGState()
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.10 + 0.16 * proximity).cgColor)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
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
        simulation?.cursorSpeed = fingerVelocities.values
            .map { hypot(Double($0.x), Double($0.y)) }
            .max() ?? 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let simulation else { return }
        for touch in touches {
            let point = touch.location(in: self)
            let key = ObjectIdentifier(touch)
            fingerPositions[key] = point
            fingerSamples[key] = (point, touch.timestamp)
            fingerVelocities[key] = .zero

            // Primero se intenta agarrar un stickman por su articulación
            // más cercana al dedo, entre los que están libres (uno ya
            // agarrado por otro dedo no puede agarrarse dos veces). A
            // quien otro stickman lleva en alto tampoco se le puede
            // agarrar (v6): está «en manos» de su portador, como ya lo
            // trataban los golpes, y el dedo y el portador se peleaban
            // por el mismo cuerpo.
            var best: (stickman: Stickman, joint: Joint, distance: Double)?
            for stickman in simulation.stickmen where !stickman.holding && stickman.carriedByID == nil {
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
            // Velocidad del dedo (todos, agarren o no): la mente la percibe.
            if var sample = fingerSamples[key] {
                var velocity = fingerVelocities[key] ?? .zero
                for s in samples {
                    let p = s.location(in: self)
                    let dt = s.timestamp - sample.time
                    if dt > 0.001 {
                        let instant = CGPoint(x: (p.x - sample.point.x) / CGFloat(dt), y: (p.y - sample.point.y) / CGFloat(dt))
                        velocity = CGPoint(x: velocity.x * 0.5 + instant.x * 0.5, y: velocity.y * 0.5 + instant.y * 0.5)
                    }
                    sample = (p, s.timestamp)
                }
                fingerSamples[key] = sample
                fingerVelocities[key] = velocity
            }
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
            fingerSamples.removeValue(forKey: key)
            fingerVelocities.removeValue(forKey: key)
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
