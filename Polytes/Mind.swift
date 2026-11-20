import CoreGraphics
import Foundation

/// La mente extendida (v4): percepción, memoria sencilla, humor y un
/// repertorio de conductas puntuadas por utilidad, por encima del
/// cerebro base de caminar/idle (Brain) y conviviendo con el combate
/// (Combat). La personalidad — energía, curiosidad y sociabilidad —
/// modula todas las puntuaciones.
///
/// Percepción: el cursor/dedo (posición y velocidad, vía Simulation),
/// los otros stickmen, las ventanas y los bordes de su suelo.
/// Memoria: quién le pegó por última vez, su sitio favorito y las
/// zonas del escritorio que ya ha visitado.
/// Humor: contento, feliz, curioso, aburrido, irritado o asustado;
/// tiñe las decisiones (el asustado huye y no pelea; el aburrido
/// explora o se sienta; el curioso sigue al cursor y a los demás).
enum Mind {
    /// Número de franjas en que se divide el escritorio para «explorar».
    private static let zoneCount = 6

    static func update(_ s: Stickman, sim: Simulation, dt: Double) {
        // Temporizadores de humor y memoria
        if s.happyTimer > 0 { s.happyTimer -= dt }
        if s.scaredTimer > 0 { s.scaredTimer -= dt }
        if s.lastAttackerTimer > 0 {
            s.lastAttackerTimer -= dt
            if s.lastAttackerTimer <= 0 { s.lastAttackerID = nil }
        }
        if s.greetCooldown > 0 { s.greetCooldown -= dt }
        if s.startleCooldown > 0 { s.startleCooldown -= dt }
        if s.peekCooldown > 0 { s.peekCooldown -= dt }
        if s.peekTimer > 0 {
            s.peekTimer -= dt
            if s.peekTimer <= 0, let turnBack = s.peekPendingTurnBack {
                // Tras mirar abajo, decide: media vuelta o seguir y caer.
                if turnBack {
                    let (left, width) = s.groundLimit
                    s.targetX = clampValue(left + width / 2 - s.width / 2, 0, Double(sim.workRect.width) - s.width)
                }
                s.peekPendingTurnBack = nil
            }
        }

        updateMood(s, sim: sim)

        // Salto de alegría al ponerse contento (si está de pie y en calma).
        if s.mood == .happy && s.prevMood != .happy && isStanding(s)
            && s.behavior == .none && Double.random(in: 0..<1) < 0.65 {
            s.velocityY = -360
            s.setActionPose(Animations.joyPose, duration: 0.5)
        }
        s.prevMood = s.mood

        // Memoria de zonas visitadas y de su sitio favorito.
        s.visitedZones.insert(currentZone(of: s, sim: sim))
        if s.state == .idle && s.behavior == .none && !s.isRagdollActive {
            s.calmTimer += dt
            if s.calmTimer > 6 {
                s.favoriteX = s.x
                s.calmTimer = 0
            }
        } else {
            s.calmTimer = 0
        }

        // Agarrado o cargado: suelta cualquier conducta (y se levanta
        // si estaba sentado o tumbado: el cuerpo pasa a ragdoll).
        if s.holding || s.carriedByID != nil {
            endBehavior(s)
            return
        }
        // En el suelo tras una caída: no decide hasta recuperarse.
        if s.downedTimer > 0 { return }
        // Cayendo en ragdoll: nada que decidir.
        if s.isRagdollActive { return }
        // Sentado: solo corre la conducta de estar sentado.
        if s.state == .sit {
            executeBehavior(s, sim: sim, dt: dt)
            return
        }

        // Reacción inmediata: un cursor que llega muy rápido lo asusta.
        if cursorStartle(s, sim: sim) { return }

        // Saludos por proximidad (evento social, no conducta).
        checkGreeting(s, sim: sim)

        // Conducta en curso o decisión nueva.
        if s.behavior != .none {
            executeBehavior(s, sim: sim, dt: dt)
            return
        }
        s.decideCooldown -= dt
        if s.decideCooldown <= 0 {
            decide(s, sim: sim)
            s.decideCooldown = 2.5
        }
        // Llegada del paseo base y asomarse a los bordes de las ventanas
        // (solo si la decisión no acaba de arrancar una conducta).
        if s.behavior == .none && s.state == .walk {
            if let target = s.targetX, abs(s.x - target) < 10 {
                s.state = .idle
                s.targetX = nil
            }
            maybePeek(s, sim: sim)
        }
    }

    // MARK: - Humor

    private static func updateMood(_ s: Stickman, sim: Simulation) {
        if s.retaliateTimer > 0 || s.irritation >= 45 {
            s.mood = .irritated
        } else if s.scaredTimer > 0 {
            s.mood = .scared
        } else if s.happyTimer > 0 {
            s.mood = .happy
        } else if s.boredom >= 70 {
            s.mood = .bored
        } else if cursorNear(s, sim: sim, radius: 240) || (s.curiosity >= 65 && s.boredom >= 35) {
            s.mood = .curious
        } else {
            s.mood = .content
        }
    }

    private static func cursorNear(_ s: Stickman, sim: Simulation, radius: Double) -> Bool {
        guard let point = sim.fingerTargetPoint(for: s) else { return false }
        let center = s.centerPoint()
        return hypot(Double(point.x - center.x), Double(point.y - center.y)) < radius
    }

    // MARK: - Percepción del cursor

    /// Un dedo que se acerca muy rápido y de cerca: saltito hacia atrás,
    /// susto breve y huida corta. Si ya está muy irritado, encima le
    /// sienta mal (la represalia la gestiona Combat con la irritación).
    private static func cursorStartle(_ s: Stickman, sim: Simulation) -> Bool {
        guard s.startleCooldown <= 0 else { return false }
        guard sim.cursorSpeed > 950, let point = sim.fingerTargetPoint(for: s) else { return false }
        let center = s.centerPoint()
        guard hypot(Double(point.x - center.x), Double(point.y - center.y)) < 135 else { return false }

        s.startleCooldown = 3
        s.scaredTimer = max(s.scaredTimer, 1.6)
        if s.irritation > 55 {
            s.irritation = min(100, s.irritation + 5)
        }
        if isStanding(s) {
            s.velocityY = -310
        }
        startFlee(s, threatX: Double(point.x), threatID: nil, duration: 1.4)
        return true
    }

    // MARK: - Saludos

    /// Si otro stickman pasa cerca, los sociables saludan con la mano;
    /// el otro puede devolver el saludo. Ambos se alegran un rato.
    private static func checkGreeting(_ s: Stickman, sim: Simulation) {
        guard s.greetCooldown <= 0, s.behavior == .none else { return }
        guard s.state == .idle || s.state == .walk else { return }
        let center = s.centerPoint()
        for other in sim.stickmen where other.id != s.id
            && !other.isRagdollActive && other.downedTimer <= 0 && other.opponentID == nil {
            let oc = other.centerPoint()
            guard hypot(Double(oc.x - center.x), Double(oc.y - center.y)) < 100 else { continue }
            let chance = Double(s.sociability) / 100 * 0.5 + Double(other.sociability) / 100 * 0.2
            guard Double.random(in: 0..<1) < chance else { continue }
            s.setActionPose(Animations.wavePose, duration: 0.7)
            s.happyTimer = max(s.happyTimer, 5)
            s.greetCooldown = 14
            other.greetCooldown = max(other.greetCooldown, 10)
            if Double.random(in: 0..<1) < 0.3 + Double(other.sociability) / 100 * 0.5 {
                other.setActionPose(Animations.wavePose, duration: 0.7)
                other.happyTimer = max(other.happyTimer, 5)
            }
            break
        }
    }

    // MARK: - Asomarse al borde

    /// Caminando sobre una ventana, a veces se para en el borde, se
    /// inclina a mirar abajo y decide si sigue (y cae) o da media vuelta.
    private static func maybePeek(_ s: Stickman, sim: Simulation) {
        guard s.peekCooldown <= 0, s.peekTimer <= 0 else { return }
        let floorY = Double(sim.workRect.maxY)
        guard let groundY = s.groundY, groundY < floorY - 2 else { return }
        guard s.curiosity >= 30 else { return }
        let (left, width) = s.groundLimit
        let edgeDistance = s.direction == 1
            ? (left + width) - (s.x + s.width)
            : s.x - left
        guard edgeDistance < 30, edgeDistance > -10 else { return }
        guard Double.random(in: 0..<1) < 0.55 else { return }
        s.peekTimer = 1.15
        s.peekCooldown = 18
        s.peekPendingTurnBack = Double.random(in: 0..<1) < 0.55
        s.setActionPose(Animations.peekPose, duration: 1.15)
    }

    // MARK: - Decisión por utilidad

    private static func decide(_ s: Stickman, sim: Simulation) {
        let worldW = Double(sim.workRect.width)
        let floorY = Double(sim.workRect.maxY)

        // Ayudar a un caído cercano es casi un reflejo si es sociable.
        if s.sociability >= 35, let downed = nearestDowned(s, sim: sim, radius: 330) {
            startHelpUp(s, target: downed)
            return
        }
        // Asustado y con su agresor reciente cerca: huye, sin puntuar.
        if s.mood == .scared, let attackerID = s.lastAttackerID,
           let attacker = sim.stickman(byID: attackerID),
           centerDistance(s, attacker) < 220 {
            startFlee(s, threatX: Double(attacker.centerPoint().x), threatID: attacker.id, duration: 2.6)
            return
        }

        // Puntuaciones especiales (misma escala 0–4 que Brain.score).
        var best: (behavior: Behavior, score: Double, target: Stickman?, window: DesktopWindow?) =
            (.none, -Double.greatestFiniteMagnitude, nil, nil)
        func consider(_ behavior: Behavior, _ score: Double, target: Stickman? = nil, window: DesktopWindow? = nil) {
            if score > best.score { best = (behavior, score, target, window) }
        }

        // Explorar una zona no visitada.
        let unvisited = (0..<zoneCount).filter { !s.visitedZones.contains($0) }
        if !unvisited.isEmpty {
            var score = 0.9 + Double(s.curiosity) / 100 * 2.0 + s.boredom / 100 * 1.2
            if s.mood == .bored { score += 0.5 }
            if s.mood == .curious { score += 0.3 }
            consider(.explore, score)
        }
        // Volver a su sitio.
        if abs(s.x - s.favoriteX) > 60 {
            var score = 1.2
            if s.mood == .scared { score += 1.4 }
            if s.stamina < 45 { score += 0.6 }
            consider(.goHome, score)
        }
        // Subirse a una ventana y sentarse en el borde.
        if s.stamina > 30, s.mood != .scared,
           let window = nearestSittableWindow(s, sim: sim, floorY: floorY) {
            let score = 1.1 + s.boredom / 100 * 1.2 + Double(s.energy) / 100 * 0.4
            consider(.sitWindow, score, window: window)
        }
        // Tumbarse a descansar si la stamina está baja.
        if s.stamina < 38 {
            consider(.restUp, 2.2 + (38 - s.stamina) * 0.04)
        }
        // Seguir a otro por curiosidad y sociabilidad.
        if s.sociability >= 45, let other = nearestCompanion(s, sim: sim, radius: 460) {
            let score = 0.9 + Double(s.sociability) / 100 * 1.6 + Double(s.curiosity) / 100 * 0.6
            consider(.follow, score, target: other)
        }
        // Acercarse a mirar el cursor (y tocarlo). Exige un dedo
        // ACTIVO (v6): con el último punto conocido, el stickman
        // caminaba hasta un punto vacío y estiraba la mano hacia la
        // nada — el mismo defecto de «al aire» que la v5 corrigió en
        // la represalia, pero que aquí había quedado.
        if s.mood != .irritated && s.mood != .scared,
           sim.activeFingerPoint(for: s) != nil,
           cursorNear(s, sim: sim, radius: 340) {
            consider(.watchCursor, Double(s.curiosity) / 100 * 2.6 + 0.4)
        }

        // La conducta especial debe superar a pasear/quedarse con margen.
        let baseBest = max(Brain.score(s, inverted: false), Brain.score(s, inverted: true))
        if best.score > baseBest + C.scoreMargin {
            switch best.behavior {
            case .explore:
                let zone = unvisited.randomElement() ?? currentZone(of: s, sim: sim)
                s.behaviorTargetX = clampValue((Double(zone) + 0.5) * worldW / Double(zoneCount) - s.width / 2, 0, worldW - s.width)
                startBehavior(s, .explore, timer: 30)
            case .goHome:
                s.behaviorTargetX = s.favoriteX
                startBehavior(s, .goHome, timer: 25)
            case .sitWindow:
                if let window = best.window {
                    s.behaviorTargetID = window.id
                    s.behaviorPhase = 0
                    s.behaviorRetries = 0
                    startBehavior(s, .sitWindow, timer: 40)
                }
            case .restUp:
                s.state = .rest
                s.targetX = nil
                startBehavior(s, .restUp, timer: 24)
            case .follow:
                if let other = best.target {
                    s.behaviorTargetID = other.id
                    startBehavior(s, .follow, timer: Double.random(in: 9...16))
                }
            case .watchCursor:
                s.behaviorPhase = 0
                startBehavior(s, .watchCursor, timer: 12)
            default:
                break
            }
            if s.behavior != .none { return }
        }

        // Base (como siempre): pasear o quedarse, por utilidad.
        let scoreWalk = Brain.score(s, inverted: false)
        let scoreIdle = Brain.score(s, inverted: true)
        if scoreWalk > scoreIdle + C.scoreMargin {
            s.state = .walk
            s.targetX = Brain.chooseTargetX(s, worldWidth: worldW)
        } else if scoreIdle > scoreWalk {
            s.state = .idle
            s.targetX = nil
        }
    }

    // MARK: - Ejecución de conductas

    private static func executeBehavior(_ s: Stickman, sim: Simulation, dt: Double) {
        s.behaviorTimer -= dt
        let worldW = Double(sim.workRect.width)

        switch s.behavior {
        case .none:
            return

        case .explore, .goHome:
            s.state = .walk
            s.targetX = s.behaviorTargetX
            if abs(s.x - s.behaviorTargetX) < 14 || s.behaviorTimer <= 0 {
                endBehavior(s)
            }

        case .follow:
            guard let other = sim.stickman(byID: s.behaviorTargetID),
                  !other.isRagdollActive, other.opponentID == nil, other.downedTimer <= 0,
                  s.behaviorTimer > 0 else {
                endBehavior(s)
                return
            }
            // Se coloca a un lado del otro y lo acompaña.
            let target = Double(s.centerPoint().x) < Double(other.centerPoint().x)
                ? other.x - 20 - s.width
                : other.x + other.width + 20
            let targetX = clampValue(target, 0, worldW - s.width)
            if abs(s.x - targetX) < 12 {
                s.state = .idle
                s.targetX = nil
            } else {
                s.state = .walk
                s.targetX = targetX
            }

        case .flee:
            var threatX = s.behaviorTargetX
            if let id = s.behaviorTargetID, let threat = sim.stickman(byID: id) {
                threatX = Double(threat.centerPoint().x)
            }
            let away = clampValue(s.x + (Double(s.centerPoint().x) < threatX ? -300 : 300), 0, worldW - s.width)
            s.state = .walk
            s.targetX = away
            if s.behaviorTimer <= 0 {
                endBehavior(s)
            }

        case .restUp:
            s.state = .rest
            s.targetX = nil
            if s.stamina >= 78 || s.behaviorTimer <= 0 {
                s.state = .idle
                endBehavior(s)
            }

        case .helpUp:
            guard let other = sim.stickman(byID: s.behaviorTargetID),
                  other.downedTimer > 0, s.behaviorTimer > 0 else {
                endBehavior(s)
                return
            }
            if centerDistance(s, other) < 74 {
                // Lo ayuda a levantarse: se acaban su recuperación y el
                // susto, y ambos se alegran.
                other.downedTimer = 0
                other.scaredTimer = 0
                other.decideCooldown = 0.5
                other.setActionPose(Animations.wavePose, duration: 0.7)
                other.happyTimer = max(other.happyTimer, 6)
                s.setActionPose(Animations.wavePose, duration: 0.7)
                s.happyTimer = max(s.happyTimer, 6)
                s.greetCooldown = 8
                endBehavior(s)
            } else {
                s.state = .walk
                s.targetX = other.x
            }

        case .watchCursor:
            // Solo dedos activos (v6): si el usuario levanta el dedo,
            // la conducta termina en vez de perseguir su recuerdo.
            guard let point = sim.activeFingerPoint(for: s), s.behaviorTimer > 0 else {
                endBehavior(s)
                return
            }
            let center = s.centerPoint()
            let dist = hypot(Double(point.x - center.x), Double(point.y - center.y))
            if s.behaviorPhase == 0 {
                if dist < 82 {
                    // Ha llegado: se queda mirando y estira la mano a tocarlo.
                    s.behaviorPhase = 1
                    s.behaviorTimer = 2.4
                    s.state = .idle
                    s.targetX = nil
                    s.setActionPose(Animations.castPose, duration: 0.45)
                } else {
                    let side = Double(center.x) < Double(point.x) ? -58.0 : 58.0
                    s.state = .walk
                    s.targetX = clampValue(Double(point.x) + side - s.width / 2, 0, worldW - s.width)
                }
            } else if dist > 170 {
                // El cursor se ha ido lejos: vuelve a acercarse.
                s.behaviorPhase = 0
            }

        case .sitWindow:
            executeSit(s, sim: sim, dt: dt)
        }
    }

    /// Subirse a una ventana y sentarse en su borde, por fases:
    /// 0 = colocarse debajo y saltar; 1 = en el aire o recién caído;
    /// 2 = caminar hasta el borde cercano; 3 = sentado.
    private static func executeSit(_ s: Stickman, sim: Simulation, dt: Double) {
        guard let window = sim.windows.first(where: { $0.id == s.behaviorTargetID }) else {
            endBehavior(s)
            return
        }
        let floorY = Double(sim.workRect.maxY)
        let top = Double(window.rect.minY)

        switch s.behaviorPhase {
        case 0:
            if let groundY = s.groundY, abs(groundY - top) < 1.5 {
                s.behaviorPhase = 2
                return
            }
            // Camina hasta quedar bajo la ventana y salta a su borde.
            s.state = .walk
            s.targetX = Double(window.rect.midX) - s.width / 2
            let centerX = s.x + s.width / 2
            let underSpan = centerX > Double(window.rect.minX) + 4 && centerX < Double(window.rect.maxX) - 4
            if underSpan && isStanding(s) && s.groundY == floorY {
                // Salto de trepada: la velocidad justa para superar el
                // borde con un margen (son stickmen con poderes: saltan alto).
                let needed = floorY - top + 34
                let jumpVelocity = clampValue(sqrt(2 * C.gravityAcceleration * needed), 560, 900)
                s.velocityY = -jumpVelocity
                s.behaviorPhase = 1
                s.behaviorTimer = 2.4
            }
            if s.behaviorTimer <= 0 { endBehavior(s) }

        case 1:
            if isStanding(s) {
                if let groundY = s.groundY, abs(groundY - top) < 1.5 {
                    s.behaviorPhase = 2
                } else if s.groundY == floorY {
                    // Cayó de vuelta al suelo: un reintento y se rinde.
                    s.behaviorRetries += 1
                    if s.behaviorRetries > 1 {
                        endBehavior(s)
                    } else {
                        s.behaviorPhase = 0
                        s.behaviorTimer = 20
                    }
                }
            } else if s.behaviorTimer < -2 {
                endBehavior(s)
            }

        case 2:
            // Camina hasta el borde más cercano y se sienta mirando fuera.
            let centerX = s.x + s.width / 2
            let edgeIsLeft = centerX <= Double(window.rect.midX)
            let hipTarget = edgeIsLeft ? Double(window.rect.minX) + 8 : Double(window.rect.maxX) - 8
            s.state = .walk
            s.targetX = hipTarget - s.width / 2
            if abs(centerX - hipTarget) < 7 {
                s.direction = edgeIsLeft ? -1 : 1
                s.state = .sit
                s.sitWindowID = window.id
                s.sitGroundY = top
                s.groundY = top
                // La cadera queda sobre el borde; la caja baja lo justo
                // para que las piernas cuelguen por fuera de la ventana.
                s.y = top - C.hipHeightFromTop + 2
                s.targetX = nil
                s.behaviorPhase = 3
                s.behaviorTimer = Double.random(in: 7...15)
            }
            if s.behaviorTimer <= 0 { endBehavior(s) }

        default:
            // Sentado: se queda hasta que vence el tiempo o se asusta/
            // se irrita (entonces se levanta de un brinco).
            if s.behaviorTimer <= 0 || s.mood == .scared || s.mood == .irritated {
                standUp(s)
                endBehavior(s)
            }
        }
    }

    // MARK: - Utilidades

    private static func startBehavior(_ s: Stickman, _ behavior: Behavior, timer: Double) {
        s.behavior = behavior
        s.behaviorTimer = timer
    }

    private static func startFlee(_ s: Stickman, threatX: Double, threatID: UUID?, duration: Double) {
        s.behaviorTargetX = threatX
        s.behaviorTargetID = threatID
        startBehavior(s, .flee, timer: duration)
    }

    private static func startHelpUp(_ s: Stickman, target: Stickman) {
        s.behaviorTargetID = target.id
        startBehavior(s, .helpUp, timer: 12)
    }

    /// Termina la conducta en curso; si estaba sentado, se levanta
    /// (la caja vuelve a su sitio sobre el borde) y si estaba tumbado,
    /// vuelve a reposo normal. Al terminar impone un respiro antes de
    /// la próxima decisión (v5): sin él, en cuanto una conducta larga
    /// acababa, el stickman encadenaba otra y el escritorio se sentía
    /// hiperactivo en vez de vivo.
    static func endBehavior(_ s: Stickman) {
        if s.state == .sit {
            standUp(s)
        } else if s.state == .rest {
            s.state = .idle
        }
        s.behavior = .none
        s.behaviorTimer = 0
        s.behaviorTargetID = nil
        s.behaviorPhase = 0
        s.decideCooldown = max(s.decideCooldown, 2.2)
    }

    /// Levantarse de estar sentado: la caja vuelve a apoyarse sobre el
    /// borde de la ventana, de pie.
    private static func standUp(_ s: Stickman) {
        s.y = s.sitGroundY - s.height
        s.state = .idle
        s.sitWindowID = nil
        s.targetX = nil
    }

    private static func isStanding(_ s: Stickman) -> Bool {
        guard let groundY = s.groundY, !s.isRagdollActive else { return false }
        return abs(s.y + s.height - groundY) < 2.5
    }

    private static func centerDistance(_ a: Stickman, _ b: Stickman) -> Double {
        let ac = a.centerPoint()
        let bc = b.centerPoint()
        return hypot(Double(ac.x - bc.x), Double(ac.y - bc.y))
    }

    private static func currentZone(of s: Stickman, sim: Simulation) -> Int {
        let worldW = max(1, Double(sim.workRect.width))
        let zone = Int(Double(s.centerPoint().x) / worldW * Double(zoneCount))
        return Int(clampValue(Double(zone), 0, Double(zoneCount - 1)))
    }

    /// El caído más cercano: en el suelo tras una caída, en recuperación.
    private static func nearestDowned(_ s: Stickman, sim: Simulation, radius: Double) -> Stickman? {
        sim.stickmen
            .filter { $0.id != s.id && $0.downedTimer > 0 && !$0.isRagdollActive }
            .min(by: { centerDistance(s, $0) < centerDistance(s, $1) })
            .flatMap { centerDistance(s, $0) < radius ? $0 : nil }
    }

    /// El compañero más cercano al que seguir: en pie, sin pelear.
    private static func nearestCompanion(_ s: Stickman, sim: Simulation, radius: Double) -> Stickman? {
        sim.stickmen
            .filter {
                $0.id != s.id && !$0.isRagdollActive && $0.downedTimer <= 0
                    && $0.opponentID == nil && $0.state != .sit && $0.state != .rest
            }
            .min(by: { centerDistance(s, $0) < centerDistance(s, $1) })
            .flatMap { centerDistance(s, $0) < radius ? $0 : nil }
    }

    /// La ventana «sittable» más cercana: su borde superior debe estar
    /// al alcance de un salto de trepada desde el suelo (≤ 330 pt).
    private static func nearestSittableWindow(_ s: Stickman, sim: Simulation, floorY: Double) -> DesktopWindow? {
        sim.windows
            .filter { floorY - Double($0.rect.minY) <= 330 }
            .min(by: {
                abs(Double($0.rect.midX) - Double(s.centerPoint().x))
                    < abs(Double($1.rect.midX) - Double(s.centerPoint().x))
            })
    }
}
