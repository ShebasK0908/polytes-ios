import CoreGraphics
import Foundation
import UIKit

/// Inteligencia de combate (v3): represalia contra el dedo y peleas
/// entre stickmen. Se puntúa y se decide como el resto del cerebro
/// (utilidad + rasgos), no es un bucle constante: hay enfriamientos
/// largos tras cada enfrentamiento. La personalidad modula la
/// agresividad: a más energía, más peleón y antes explota contra el dedo.
enum Combat {
    static func update(_ s: Stickman, sim: Simulation, dt: Double) {
        // Temporizadores generales
        if s.retaliateCooldown > 0 { s.retaliateCooldown -= dt }
        if s.fightCooldown > 0 { s.fightCooldown -= dt }
        if s.blockingTimer > 0 { s.blockingTimer -= dt }
        if s.attackCooldown > 0 { s.attackCooldown -= dt }

        // Consistencia: si a quien llevaba ya no lo lleva él, se acabó.
        if let carriedID = s.carryingID, sim.stickman(byID: carriedID)?.carriedByID != s.id {
            s.carryingID = nil
        }

        // Vuelo con motor: cuenta atrás, y corte si la pelea que lo
        // motivó ya terminó (el vuelo de represalia se mantiene).
        if s.poweredFlight {
            s.flightTimer -= dt
            if s.flightTimer <= 0 {
                s.cutPoweredFlight()
            } else if s.flightAttackTargetID != nil && s.opponentID == nil && s.retaliateTimer <= 0 {
                s.cutPoweredFlight()
            }
        }

        // La irritación se enfría con el tiempo, más rápido en reposo.
        if s.retaliateTimer <= 0 && s.irritation > 0 {
            let rate = C.irritationDecayPerSecond * (s.state == .idle ? 1.6 : 1.0)
            s.irritation = max(0, s.irritation - rate * dt)
        }

        // A quien están cargando no decide nada: cuelga de su portador.
        if s.carriedByID != nil { return }

        // ¿Explota contra el dedo? El umbral baja con la energía.
        if s.retaliateTimer <= 0 && s.retaliateCooldown <= 0
            && s.opponentID == nil && s.carryingID == nil {
            let threshold = 58 + Double(100 - s.energy) * 0.3
            if s.irritation >= threshold {
                startRetaliation(s, sim: sim)
            }
        }

        if s.retaliateTimer > 0 {
            updateRetaliation(s, sim: sim, dt: dt)
            return
        }

        if s.chargingPunch {
            updateCharge(s, sim: sim, dt: dt)
            return
        }

        if let opponentID = s.opponentID {
            updateFight(s, sim: sim, opponentID: opponentID, dt: dt)
            return
        }

        // En calma: de vez en cuando valora buscar pelea. El asustado
        // no busca pelea (v4), ni quien está sentado, tumbado o en el
        // suelo tras una caída.
        if s.fightCooldown <= 0 && !s.isRagdollActive && !s.holding
            && s.mood != .scared && s.state != .sit && s.state != .rest && s.downedTimer <= 0 {
            s.fightThinkTimer -= dt
            if s.fightThinkTimer <= 0 {
                // (v4) Valora buscar pelea cada 2,5–4 s en vez de cada
                // segundo: con la cadencia anterior, en cuanto vencía el
                // enfriamiento un stickman peleón encadenaba otra pelea
                // y el escritorio vivía en guerra constante.
                s.fightThinkTimer = Double.random(in: 2.5...4.0)
                maybeStartFight(s, sim: sim)
            }
        }
    }

    // MARK: - Represalia contra el dedo

    static func startRetaliation(_ s: Stickman, sim: Simulation) {
        if s.holding {
            // Se zafa del agarre de un tirón hacia arriba.
            s.holding = false
            s.grabPart = nil
            s.flying = true
            for point in s.ragPoints.values {
                point.old.y = point.pos.y + 3.5
            }
        }
        s.retaliateTimer = C.retaliationDuration
        s.attackCooldown = 0.25
        s.state = .idle
        s.targetX = nil
        if let head = s.displayJoints()[.head] {
            sim.spawnSparks(at: head, count: 7, color: UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1))
        }
    }

    static func updateRetaliation(_ s: Stickman, sim: Simulation, dt: Double) {
        s.retaliateTimer -= dt
        if s.retaliateTimer <= 0 {
            s.irritation = 15
            s.retaliateCooldown = C.retaliationCooldown
            if s.poweredFlight { s.cutPoweredFlight() }
            s.state = .idle
            s.targetX = nil
            return
        }

        guard let point = sim.fingerTargetPoint(for: s) else {
            s.state = .idle
            return
        }

        let center = s.centerPoint()
        let dx = Double(point.x) - center.x
        let dy = Double(point.y) - center.y
        let dist = hypot(dx, dy)
        s.direction = dx >= 0 ? 1 : -1

        if s.poweredFlight {
            // Persigue el dedo por el aire y le pega cuando lo alcanza.
            s.flightTarget = point
            if dist < 85 && s.attackCooldown <= 0 {
                s.setActionPose(Animations.punchPose, duration: 0.25)
                sim.spawnSparks(at: point, count: 8, color: .orange)
                s.attackCooldown = 0.7
            }
            return
        }
        // Cayendo tras zafarse: espera a aterrizar para contraatacar.
        if s.isRagdollActive { return }

        // Si el dedo está alto y lejos, despega a por él.
        if dy < -110 && dist > 130 {
            s.beginPoweredFlight(target: point, duration: 2.4)
            return
        }

        if abs(dx) > 75 {
            s.state = .walk
            s.targetX = Double(point.x) - s.width / 2
        } else {
            s.state = .idle
            s.targetX = nil
        }

        if s.attackCooldown <= 0 {
            if dist < 125 {
                s.setActionPose(Animations.punchPose, duration: 0.25)
                sim.spawnSparks(at: point, count: 7, color: .orange)
            } else if Bool.random() {
                sim.fireFireball(from: s, targetPoint: point, explodeAt: point)
            } else {
                sim.fireLaser(from: s, to: point)
            }
            s.attackCooldown = 0.65
        }
    }

    // MARK: - Peleas entre stickmen

    static func maybeStartFight(_ s: Stickman, sim: Simulation) {
        let center = s.centerPoint()
        let candidates = sim.stickmen.filter {
            $0.id != s.id && $0.opponentID == nil && $0.retaliateTimer <= 0
                && !$0.isRagdollActive && !$0.holding && $0.carriedByID == nil
                && $0.fightCooldown <= 0 && $0.chargingPunch == false
                && $0.state != .sit && $0.state != .rest && $0.downedTimer <= 0
        }
        guard let opp = candidates.min(by: {
            hypot(Double($0.centerPoint().x - center.x), Double($0.centerPoint().y - center.y))
                < hypot(Double($1.centerPoint().x - center.x), Double($1.centerPoint().y - center.y))
        }) else { return }

        let dist = hypot(Double(opp.centerPoint().x - center.x), Double(opp.centerPoint().y - center.y))
        guard dist < 560 else { return }

        // Puntuación de agresión: la energía manda; el aburrimiento
        // empuja; la memoria también (v4): si el candidato es quien le
        // pegó hace poco y sigue irritado, hay ganas de revancha.
        var aggression = Double(s.energy) / 100 * 0.55 + s.boredom / 100 * 0.30 + Double.random(in: 0..<0.45)
        if s.mood == .irritated { aggression += 0.12 }
        if s.lastAttackerID == opp.id { aggression += 0.15 }
        guard aggression > 0.92 else { return }

        s.opponentID = opp.id
        opp.opponentID = s.id
        s.fightTimer = C.fightMaxDuration
        opp.fightTimer = C.fightMaxDuration
        s.attackCooldown = Double.random(in: 0.4...0.9)
        opp.attackCooldown = Double.random(in: 0.5...1.1)
        s.fightThinkTimer = 2
    }

    static func updateFight(_ s: Stickman, sim: Simulation, opponentID: UUID, dt: Double) {
        guard let opp = sim.stickman(byID: opponentID) else {
            s.opponentID = nil
            return
        }
        // Si a él lo agarra el usuario, o a su rival lo agarran o lo
        // cargan, la pelea se apaga.
        if s.holding || opp.holding || opp.carriedByID != nil {
            sim.endFight(s, opp)
            return
        }

        s.fightTimer -= dt
        if s.fightTimer <= 0 {
            sim.endFight(s, opp)
            return
        }

        let myCenter = s.centerPoint()
        let oppCenter = opp.centerPoint()
        let dx = Double(oppCenter.x - myCenter.x)
        let dy = Double(oppCenter.y - myCenter.y)
        let adx = abs(dx)
        let ady = abs(dy)
        s.direction = dx >= 0 ? 1 : -1

        // Lleva a su rival en alto: cuenta atrás y lo lanza.
        if s.carryingID == opp.id {
            s.state = .idle
            s.targetX = nil
            s.carryTimer -= dt
            if s.carryTimer <= 0 {
                sim.throwCarried(s, opp)
            }
            return
        }

        // Vuelo de ataque en curso: primero se coloca sobre el rival
        // y luego se deja caer sobre él.
        if s.poweredFlight && s.flightAttackTargetID == opp.id {
            if adx > 130 || s.flightTimer < 1.2 {
                s.flightTarget = CGPoint(x: oppCenter.x, y: oppCenter.y - 130)
            } else {
                s.flightTarget = oppCenter
            }
            if hypot(dx, dy) < 64 {
                let dir = dx >= 0 ? 1.0 : -1.0
                sim.applyHit(to: opp, impulse: cgPoint(dir * 12, 7), spin: dir * 0.08, from: s)
                s.cutPoweredFlight()
            }
            return
        }

        // En el aire por un golpe ajeno: no actúa hasta aterrizar.
        if s.isRagdollActive { return }

        // Acercarse hasta la distancia de golpeo y plantarse.
        if adx > 108 {
            s.state = .walk
            s.targetX = Double(oppCenter.x) - s.width / 2
        } else {
            s.state = .idle
            s.targetX = nil
        }

        guard s.attackCooldown <= 0 else { return }

        // Elección de ataque según la distancia.
        let roll = Double.random(in: 0..<1)
        if adx > 250 {
            if roll < 0.45 { castFireball(s, sim: sim, opp: opp) }
            else if roll < 0.75 { castLaser(s, sim: sim, opp: opp) }
            else { startFlightAttack(s, opp: opp) }
        } else if adx > 108 {
            if roll < 0.35 { castFireball(s, sim: sim, opp: opp) }
            else if roll < 0.60 { castLaser(s, sim: sim, opp: opp) }
            else if roll < 0.85 { startDashRam(s, opp: opp) }
            else { startFlightAttack(s, opp: opp) }
        } else if ady >= 90 {
            // Está encima en horizontal pero en otra planta (p. ej. sobre
            // una ventana): a esa altura no llegan ni el puño ni el
            // agarre, así que ataca a distancia o vuela a por él.
            if roll < 0.40 { castFireball(s, sim: sim, opp: opp) }
            else if roll < 0.70 { castLaser(s, sim: sim, opp: opp) }
            else { startFlightAttack(s, opp: opp) }
        } else {
            if roll < 0.35 { punch(s, sim: sim, opp: opp) }
            else if roll < 0.55 { startSuperPunch(s) }
            else if roll < 0.70 { startGrabThrow(s, sim: sim, opp: opp) }
            else if roll < 0.85 { castFireball(s, sim: sim, opp: opp) }
            else { castLaser(s, sim: sim, opp: opp) }
        }
    }

    // MARK: - Ataques

    static func punch(_ s: Stickman, sim: Simulation, opp: Stickman) {
        s.setActionPose(Animations.punchPose, duration: 0.28)
        let dx = Double(opp.centerPoint().x - s.centerPoint().x)
        let dy = Double(opp.centerPoint().y - s.centerPoint().y)
        if abs(dx) < 105 && abs(dy) < 90 {
            let dir = dx >= 0 ? 1.0 : -1.0
            sim.applyHit(to: opp, impulse: cgPoint(dir * 10.5, -6), spin: dir * 0.05, from: s)
        }
        s.attackCooldown = Double.random(in: 0.5...0.95)
    }

    static func startSuperPunch(_ s: Stickman) {
        s.chargingPunch = true
        s.chargeTimer = C.superPunchChargeTime
        s.setActionPose(Animations.chargePose, duration: 0.3)
        s.state = .idle
        s.targetX = nil
    }

    /// Al completar la carga, el superpuñetazo se suelta: si el rival
    /// sigue a distancia de golpeo sale volando; si no, el atacante se
    /// abalanza hacia delante y falla.
    static func updateCharge(_ s: Stickman, sim: Simulation, dt: Double) {
        // Si pierde el suelo a mitad de carga (la ventana se mueve o se
        // cae del borde), la carga se cancela: un cuerpo en ragdoll no
        // puede soltar el superpuñetazo desde el aire.
        if s.isRagdollActive {
            s.chargingPunch = false
            s.chargeTimer = 0
            return
        }
        if s.actionPoseTimer <= 0 {
            s.setActionPose(Animations.chargePose, duration: 0.2)
        }
        s.chargeTimer -= dt
        guard s.chargeTimer <= 0 else { return }
        s.chargingPunch = false
        s.setActionPose(Animations.punchPose, duration: 0.3)

        if let opponentID = s.opponentID, let opp = sim.stickman(byID: opponentID) {
            let dx = Double(opp.centerPoint().x - s.centerPoint().x)
            let dy = Double(opp.centerPoint().y - s.centerPoint().y)
            s.direction = dx >= 0 ? 1 : -1
            if abs(dx) < 118 && abs(dy) < 95 {
                let dir = Double(s.direction)
                sim.applyHit(to: opp, impulse: cgPoint(dir * 20, -11), spin: dir * 0.10, from: s)
            } else {
                s.externalPushX = Double(s.direction) * 520
            }
        }
        s.attackCooldown = 1.3
    }

    static func castFireball(_ s: Stickman, sim: Simulation, opp: Stickman) {
        sim.fireFireball(from: s, targetPoint: opp.centerPoint(), explodeAt: nil)
        s.attackCooldown = 0.95
    }

    static func castLaser(_ s: Stickman, sim: Simulation, opp: Stickman) {
        let target = opp.centerPoint()
        sim.fireLaser(from: s, to: target)
        let dir = Double(target.x - s.centerPoint().x) >= 0 ? 1.0 : -1.0
        sim.applyHit(to: opp, impulse: cgPoint(dir * 12, -4.5), spin: dir * 0.04, from: s)
        s.attackCooldown = 1.15
    }

    static func startDashRam(_ s: Stickman, opp: Stickman) {
        let dir = Double(opp.centerPoint().x - s.centerPoint().x) >= 0 ? 1.0 : -1.0
        s.dashVelocityX = dir * C.dashSpeed
        s.dashTimer = C.dashDuration
        s.dashHitTargetID = opp.id
        s.setActionPose(Animations.dashPose, duration: 0.2)
        s.attackCooldown = 1.0
    }

    static func startFlightAttack(_ s: Stickman, opp: Stickman) {
        let above = CGPoint(x: opp.centerPoint().x, y: opp.centerPoint().y - 140)
        s.beginPoweredFlight(target: above, duration: 2.8)
        s.flightAttackTargetID = opp.id
        s.attackCooldown = 1.4
    }

    /// Superfuerza: levanta al rival sobre su cabeza. El rival puede
    /// esquivarlo con supervelocidad justo antes del agarre.
    static func startGrabThrow(_ s: Stickman, sim: Simulation, opp: Stickman) {
        if opp.isRagdollActive {
            s.attackCooldown = 0.5
            return
        }
        // El agarre es cuerpo a cuerpo: si el rival está en otra planta
        // (sobre una ventana, muy por encima o por debajo), no hay
        // teletransporte — se renuncia y se ataca a distancia luego.
        let dy = Double(opp.centerPoint().y - s.centerPoint().y)
        if abs(dy) >= 90 {
            s.attackCooldown = 0.6
            return
        }
        let dodgeChance = 0.20 + Double(opp.energy) / 500
        if Double.random(in: 0..<1) < dodgeChance {
            sim.startDodge(opp, awayFrom: s)
            s.attackCooldown = 0.8
            return
        }
        opp.seedRagdoll()
        opp.flying = false
        opp.holding = false
        opp.grabPart = nil
        opp.carriedByID = s.id
        s.carryingID = opp.id
        s.carryTimer = 0.7
        s.state = .idle
        s.targetX = nil
        s.attackCooldown = 1.2
    }
}
