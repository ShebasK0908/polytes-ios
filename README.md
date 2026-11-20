# Polytes para iPhone

Recreación propia para iOS del diseño de **Polytes** (la mascota de escritorio open-source de Foxcuukinho): un stickman que vive en un escritorio, camina sobre las ventanas, se deja agarrar de cualquier articulación y cae con física ragdoll. Es una implementación limpia escrita desde cero en Swift a partir del comportamiento y los valores del original; no contiene código del proyecto original.

- **Bundle id:** `dev.shebo.polytes` · **iOS 16+** · Interfaz en español.
- La `.ipa` se compila sin firmar: se instala con **SideStore** o AltStore.

## El escritorio

Como en iOS una app no puede vivir sobre las demás, el escritorio está dentro de la app: fondo con degradado e iconos, una barra inferior tipo taskbar (el suelo base), bordes de pantalla sólidos y tres ventanas flotantes (Explorador, Notas y Música) que se arrastran por su barra de título. Las ventanas son sólidos: su parte superior visible es suelo para los stickmen, y si una ventana se mueve o el stickman camina más allá de su borde, el suelo desaparece y el cuerpo cae.

Desde la v2 la app funciona solo en horizontal (apaisado, como un juego): las ventanas parten separadas por huecos anchos en la mitad superior y el suelo junto a la barra inferior queda libre de punta a punta.

## Los sistemas

- **Rig y animación FK** (`Rig.swift`, `Animations.swift`): esqueleto de 11 articulaciones (cadera, cuello, cabeza, codos, manos, rodillas, pies) con las proporciones del original (caja de 100×145, torso 37, brazos 24+23, piernas 28+27, trazo de 9), dibujadas a escala 0,6 desde la v2 (caja de 60×87) para que el escritorio se vea amplio. Las poses de reposo (6 fotogramas) y de caminar (12 fotogramas) se interpolan por ángulos; el ciclo de caminar se sincroniza con la velocidad para que los pies no patinen, y tras la cinemática el cuerpo se ajusta para que el pie más bajo toque el suelo. Las extremidades se dibujan como curvas que pasan cerca de la articulación intermedia. Cabeza hueca (Ø 38) o rellena (Ø 30).
- **Física híbrida** (`BodyPhysics.swift`, `Simulation.swift`): en el suelo el cuerpo se anima por FK con gravedad y detección de suelo; al agarrarlo o al perder el suelo, el ragdoll Verlet se siembra desde la pose animada actual — puntos con posición anterior, gravedad, amortiguación, solver de distancias (20 iteraciones, rigidez 0,85) y rebote en bordes y ventanas. Al soltar, el cuerpo sale con la velocidad del arrastre y giro proporcional a esa velocidad. Al aterrizar vuelve a IDLE con una pausa de recuperación de 3 s antes de que el cerebro retome el control.
- **Interacción**: se agarra de la articulación más cercana al dedo, el cuerpo cuelga del punto agarrado, y se puede lanzar. Varios dedos pueden agarrar a la vez, incluso a stickmen distintos.
- **Cerebro** (`Brain.swift`): necesidades de *stamina* y *aburrimiento* que suben y bajan según el estado (caminar cansa y entretiene; estar quieto recupera y aburre) y decisión por utilidad cada 3 s entre caminar a un objetivo aleatorio a ≥ 300 pt (el escritorio apaisado da para paseos más largos) o quedarse en reposo, con el mismo margen de decisión del original.
- **Personalidad** (`Brain.swift`): determinista a partir del nombre (semilla SHA-256 del nombre): energía y curiosidad entre 1 y 100. La cabeza hueca suma +20 % de energía; los colores fríos (tono 120–240°) potencian la curiosidad y los cálidos la energía; los colores acromáticos no dan bonus. El mismo nombre siempre produce el mismo stickman.
- **Creador**: nombre, color (con paleta rápida), cabeza hueca o rellena y vista previa en vivo con las barras de energía y curiosidad. Se pueden tener varios stickmen a la vez, cada uno con su personalidad, y eliminarlos desde la lista.

Paso de simulación fijo de 32 ms (como el original) acumulado desde el `CADisplayLink`; el dibujo va a la frecuencia de la pantalla.

> Nota de adaptación táctil: el radio de búsqueda al agarrar es más generoso que el del ratón en el original (30 pt frente a unos pocos píxeles) y no escala con el cuerpo, porque un dedo no tiene la precisión de un cursor. Todo lo demás sigue los valores del diseño original.

## Compilar

```bash
./build.sh          # compila Polytes.app sin firmar (requiere Xcode)
./package-ipa.sh    # genera build/Polytes.ipa
```

En GitHub, el workflow «Build iOS IPA (sin firmar)» hace lo mismo en un runner macOS y publica la `.ipa` en la release `app-v1`.
