# Polytes para iPhone

Recreación propia para iOS del diseño de **Polytes** (la mascota de escritorio open-source de Foxcuukinho): un stickman que vive en un escritorio, camina sobre las ventanas, se deja agarrar de cualquier articulación y cae con física ragdoll. Es una implementación limpia escrita desde cero en Swift a partir del comportamiento y los valores del original; no contiene código del proyecto original.

- **Bundle id:** `dev.shebo.polytes` · **iOS 16+** · Interfaz en español.
- La `.ipa` se compila sin firmar: se instala con **SideStore** o AltStore.

## El escritorio

Como en iOS una app no puede vivir sobre las demás, el escritorio está dentro de la app: fondo con degradado e iconos, una barra inferior tipo taskbar (el suelo base), bordes de pantalla sólidos y tres ventanas flotantes (Explorador, Notas y Música) que se arrastran por su barra de título. Las ventanas son sólidos: su parte superior visible es suelo para los stickmen, y si una ventana se mueve o el stickman camina más allá de su borde, el suelo desaparece y el cuerpo cae.

Desde la v2 la app funciona solo en horizontal (apaisado, como un juego): las ventanas parten separadas por huecos anchos en la mitad superior y el suelo junto a la barra inferior queda libre de punta a punta.

El suelo base es el borde superior de la barra de tareas: los stickmen pasean sobre la taskbar y sobre los bordes superiores de las ventanas, como en el escritorio de referencia. Desde la v4 el escritorio es **pantalla completa de verdad**: sin cabecera fija y sin barra de estado, el mundo ocupa toda la pantalla borde a borde, como un juego. El botón «Crear stickman» es una píldora flotante semitransparente en la esquina superior derecha — no es una superficie: ningún stickman puede subirse a él ni quedarse pegado; como mucho pasa por detrás un instante.

## Los sistemas

- **Rig y animación FK** (`Rig.swift`, `Animations.swift`): esqueleto de 11 articulaciones (cadera, cuello, cabeza, codos, manos, rodillas, pies) con las proporciones del original (caja de 100×145, torso 37, brazos 24+23, piernas 28+27, trazo de 9), dibujadas a escala 0,6 desde la v2 (caja de 60×87) para que el escritorio se vea amplio. Las poses de reposo (6 fotogramas) y de caminar (12 fotogramas) se interpolan por ángulos; el ciclo de caminar se sincroniza con la velocidad para que los pies no patinen, y tras la cinemática el cuerpo se ajusta para que el pie más bajo toque el suelo. Las extremidades se dibujan como curvas que pasan cerca de la articulación intermedia. Cabeza hueca (Ø 38) o rellena (Ø 30).
- **Física híbrida** (`BodyPhysics.swift`, `Simulation.swift`): en el suelo el cuerpo se anima por FK con gravedad y detección de suelo; al agarrarlo o al perder el suelo, el ragdoll Verlet se siembra desde la pose animada actual — puntos con posición anterior, gravedad, amortiguación, solver de distancias (20 iteraciones, rigidez 0,85) y rebote en bordes y ventanas. Al soltar, el cuerpo sale con la velocidad del arrastre y giro proporcional a esa velocidad. Al aterrizar vuelve a IDLE con una pausa de recuperación de 3 s antes de que el cerebro retome el control.
- **Interacción**: el dedo hace de cursor, como el ratón en el original. Se agarra de la articulación más cercana conservando el desplazamiento entre el dedo y la articulación (el cuerpo no salta al tocarlo), el punto agarrado sigue al dedo 1:1 sin suavizado (con las muestras coalescidas de los eventos táctiles) y la velocidad de lanzamiento se mide del movimiento real del dedo con marcas de tiempo: si el dedo se detiene antes de soltar, el lanzamiento sale sin fuerza. Varios dedos pueden agarrar a la vez, incluso a stickmen distintos (un stickman ya agarrado no admite un segundo agarre).
- **Cerebro** (`Brain.swift`): necesidades de *stamina* y *aburrimiento* que suben y bajan según el estado (caminar cansa y entretiene; estar quieto recupera y aburre) y decisión por utilidad cada 3 s entre caminar a un objetivo aleatorio a ≥ 300 pt (el escritorio apaisado da para paseos más largos) o quedarse en reposo, con el mismo margen de decisión del original.
- **Personalidad** (`Brain.swift`): determinista a partir del nombre (semilla SHA-256 del nombre): energía y curiosidad entre 1 y 100. La cabeza hueca suma +20 % de energía; los colores fríos (tono 120–240°) potencian la curiosidad y los cálidos la energía; los colores acromáticos no dan bonus. El mismo nombre siempre produce el mismo stickman.
- **Creador**: nombre, color (con paleta rápida), cabeza hueca o rellena y vista previa en vivo con las barras de energía y curiosidad. Se pueden tener varios stickmen a la vez, cada uno con su personalidad, y eliminarlos desde la lista.

Paso de simulación fijo de 32 ms (como el original) acumulado desde el `CADisplayLink`; el dibujo va a la frecuencia de la pantalla.

## Poderes e inteligencia de ataque (v3)

La v3 se aparta de la V1 fiel: los stickmen tienen poderes y saben pelear, integrados en la misma simulación (`Combat.swift`, `Effects.swift`).

- **Volar**: vuelo con motor sobre el ragdoll — dirección asistida hacia el objetivo y chorros de llama desde las manos en sentido contrario al movimiento, como The Second Coming. Al cortarse el vuelo (fin del temporizador o golpe recibido), el cuerpo cae en ragdoll.
- **Fuego**: bolas de fuego con estela de partículas que al impactar empujan al objetivo y lo siembran en ragdoll; estallan en chispas.
- **Láser**: haz instantáneo desde los ojos, con empuje y derribo.
- **Superpuñetazo**: carga visible de 0,55 s (brillo creciente en el puño) y golpe que lanza al objetivo volando con giro; si el rival se ha apartado, el atacante se abalanza y falla.
- **Superfuerza**: el atacante levanta a su rival sobre la cabeza y lo lanza; además, un cuerpo que impacta contra una ventana a gran velocidad la empuja en la dirección del golpe.
- **Supervelocidad**: dash casi instantáneo con estela de siluetas; sirve para embestir y para esquivar.
- **Defensa contra el dedo**: cada agarre y cada lanzamiento fuerte sube la «irritación»; al pasar un umbral (más bajo cuanto más energía tenga) el stickman se zafa del agarre y contraataca el punto del dedo durante unos segundos — puñetazos si está cerca, fuego o láser si está lejos, y vuelo si el dedo está alto — y luego se calma con un enfriamiento.
- **Peleas entre stickmen**: de vez en cuando, puntuado como las demás decisiones (la energía manda: los de poca energía nunca buscan pelea), un stickman reta al más cercano: se acerca, intercambian puñetazos, superpuñetazos, fuego, láser, embestidas, agarres con lanzamiento y ataques en vuelo; el defensor bloquea (pose de guardia y resbalón) o esquiva con supervelocidad. Un golpe fuerte que conecta termina la pelea y ambos quedan en enfriamiento largo (30–50 s desde la v4), sin bucles eternos. Pelear gasta stamina extra.

## Correcciones de la v3

- La cabecera de la app ya no es parte del mundo (ver arriba): el mundo jugable empieza debajo de ella.
- Clamp por punto del ragdoll: ningún punto puede hundirse bajo el suelo ni salir del mundo, ni siquiera arrastrado con el dedo (antes un cuerpo agarrado podía quedar medio hundido en una esquina, tapado por los iconos).
- Las ventanas arrastradas actúan como plataformas: quien esté de pie sobre una ventana se mueve con ella en vez de quedarse flotando hasta caer de golpe.
- `computeGround` devuelve el intervalo superior *visible* que realmente sujetó al stickman, no el ancho entero de la ventana: ya no se camina flotando sobre la parte tapada por otra ventana.
- El aterrizaje busca el suelo con una caja del ancho del cuerpo centrada en la cadera, no con la envolvente del cuerpo girando: menos aterrizajes «enganchados» de la esquina de una ventana.
- Un stickman ya agarrado por un dedo no puede ser agarrado por un segundo dedo (antes el primer dedo lo soltaba en falso a mitad de arrastre).
- La velocidad de lanzamiento sale del movimiento real del dedo (marcas de tiempo y muestras coalescidas), con topes de velocidad y de giro: antes salía del delta del último evento táctil, irregular según la tasa de eventos.
- El clamp de bordes en modo animación se aplica después del movimiento: un dash rápido no asoma fuera ni un fotograma.

> Nota de adaptación táctil: el radio de búsqueda al agarrar es más generoso que el del ratón en el original (30 pt frente a unos pocos píxeles) y no escala con el cuerpo, porque un dedo no tiene la precisión de un cursor. Todo lo demás sigue los valores del diseño original.

## Revisión y mejoras de la v4

Pasada completa de revisión del código de la v3, con correcciones, y una ronda de mejora:

**Correcciones de la revisión**

- Al terminar una pelea, si uno de los dos llevaba al otro en alto, el cargado quedaba pegado para siempre a la cabeza de su portador (nadie lo bajaba): `endFight` ahora suelta la carga entre ambos y el soltado cae.
- `removeStickman` dejaba referencias colgadas (rival, portador, objetivo de embestida o de vuelo) en los demás stickmen; ahora se limpian al eliminar, y sus bolas de fuego en vuelo se retiran.
- La aparición repartía huecos con el conteo de stickmen vivos: tras eliminar a alguien, dos podían aparecer exactamente en el mismo sitio. Ahora el reparto es persistente.
- Las bolas de fuego atravesaban las ventanas (que son sólidos para los cuerpos) y podían salir del mundo y seguir volando invisibles; ahora estallan contra las ventanas y se apagan en los bordes.
- La carga del superpuñetazo seguía corriendo si el stickman perdía el suelo a mitad de carga, y el golpe podía salir desde el aire en ragdoll; ahora la carga se cancela al perder el suelo.
- El agarre de superfuerza y los ataques cuerpo a cuerpo no comprobaban la diferencia de altura: se podía «agarrar» a un rival que estaba en otra planta (sobre una ventana). Ahora el combate cercano exige alturas parecidas; si el rival está en otra planta, se ataca a distancia o en vuelo.
- El reloj de la barra inferior construía un `DateFormatter` nuevo en cada fotograma; ahora se crea una sola vez.

**Mejoras**

- **Icono de app**: un stickman de cabeza hueca saludando ante su ventana, sobre la barra inferior (la app llevaba tres versiones con el icono vacío).
- **Escritorio más parecido al del vídeo**: cielo con degradado de cuatro paradas, sol suave con degradado radial y dos cordilleras de colinas sobre el horizonte.
- **Ventanas con contenido propio**: el Explorador muestra una rejilla de carpetas, Notas muestra una nota con título y una palabra resaltada, y Música muestra carátula con disco, pista y barra de progreso.
- **Personajes conocidos en el creador**: «The Second Coming» (naranja, cabeza hueca), «The Dark Lord» (rojo, cabeza rellena) y «Víctima» (amarillo) cargan sus datos en el formulario con un toque, además del personalizado.
- **Combate equilibrado**: valorar buscar pelea cada 2,5–4 s (antes cada 1 s) y enfriamiento tras pelea de 30–50 s; la irritación sube un poco más despacio por agarre (18) y se enfría más rápido (4/s), con el umbral de explosión algo más alto (58). El escritorio se siente vivo sin estar en guerra constante.
- **Vuelo suave**: despegue con impulso inicial menor y rampa de asistencia progresiva (0,5 s); la velocidad deseada se reduce al acercarse al objetivo, sin orbitar; y al cortarse el vuelo se frena la velocidad media del cuerpo (conservando el giro), de modo que la caída no empieza a velocidad de crucero.
- **Pantalla completa**: el escritorio llena la pantalla entera (ver «El escritorio»).
- **Cursor visible**: el dedo es el cursor y ahora se ve — una flecha blanca estilo PC en cada dedo activo, que se convierte en mano agarrando cuando ese dedo lleva a un stickman. La vista además mide la velocidad de cada dedo y la simulación la percibe.
- **Mente extendida** (`Mind.swift`): percepción (el cursor y su velocidad, los otros stickmen, las ventanas y los bordes de su suelo), memoria sencilla (quién le pegó por última vez y durante cuánto lo recuerda, su sitio favorito, las zonas del escritorio ya visitadas) y humor (contento, feliz, curioso, aburrido, irritado, asustado tras una caída grande) que tiñe las decisiones. Conductas nuevas puntuadas por utilidad, además de pasear/reposar/pelear: explorar zonas no visitadas, volver a su sitio, subirse a una ventana de un salto de trepada y **sentarse en su borde con las piernas colgando** (la FK no aplica el ajuste de pies en ese estado), tumbarse a descansar si la stamina está baja, seguir a otro por curiosidad, ayudar a levantarse a uno que está en el suelo tras una caída, asomarse al borde de una ventana y mirar abajo antes de decidir si sigue o da media vuelta, acercarse a mirar el cursor y estirar la mano a tocarlo, y huir de su agresor o de un cursor que llega demasiado rápido. Eventos sociales: saludos con la mano cuando otro pasa cerca (con posible saludo de vuelta) y saltos de alegría al ponerse contento. La personalidad suma un tercer rasgo de la misma semilla, la **sociabilidad**, que modula saludos, seguimientos y ayudas; el asustado no busca peleas y el irritado tiene ganas de revancha contra quien le pegó. Tras aterrizar, el stickman se queda tumbado en el suelo durante la recuperación (más rato, y asustado, si la caída fue grande).

## La v5: correcciones de la grabación y mejora general

El usuario grabó la v4 en su iPhone y señaló seis defectos; todos están corregidos:

- **El cuerpo caído se hacía un nudo.** La física de reposo del ragdoll se ha rehecho: contactos por punto estilo PBD intercalados en el solver (cada punto se apoya en su superficie — suelo base o borde visible de ventana — con fricción horizontal y rebote solo si el impacto es fuerte), restricciones anti-pliegue de distancia mínima entre articulaciones no adyacentes (la cabeza ya no puede acabar entre los pies) y amortiguación del reposo que también frena el giro. El aterrizaje ya no depende de la envolvente: un cuerpo apoyado en varios puntos y casi quieto durante un instante se da por aterrizado y pasa a la recuperación tumbado, también si quedó colgando sobre una ventana. Y la pose tumbada tiene volumen (una rodilla flexionada, un brazo sobre el cuerpo, respiro visible): ya no es una tabla recta ni un pretzel.
- **Tapado por la barra inferior.** El orden de dibujo ya ponía a los stickmen sobre la taskbar; lo que fallaba era que el cuerpo quedaba como una línea fina pegada a la costura y camuflada contra las colinas oscuras. Ahora el cuerpo pasa de forma fiable a la pose tumbada reconocible, lleva una **sombra de contacto** que lo despega del fondo (y que delata su altura al volar) y la cordillera cercana es más clara.
- **Textos fantasma en el creador.** El `Form` (celdas reutilizadas y materiales translúcidos) se ha sustituido por un ScrollView de tarjetas con fondos sólidos y barra de navegación opaca; además, el escritorio se pausa mientras el creador está abierto. Sin celdas ni translucidez, al hacer scroll ya no se duplica nada.
- **La ventana Música salía vacía.** Su contenido exigía más altura de la que la ventana tiene en el teléfono (reservaba 34 pt y pedía una carátula de más de 20 pt: la cuenta no salía y no dibujaba nada). Ahora la carátula, el disco y las líneas se adaptan a la altura real y la barra de progreso aparece cuando hay sitio.
- **Colgar estirado de una ventana en movimiento.** Las colisiones con ventanas ya no desplazan la envolvente entera del cuerpo: cada punto sale y rebota por su cuenta y el solver cose el resto. Y un cuerpo apoyado en una ventana que se arrastra recibe arrastre por fricción parcial: si la ventana se mueve despacio lo lleva consigo; si se mueve rápido, el cuerpo se escurre, pierde el apoyo y cae, como con un agarre real.
- **Golpes al aire sin objetivo.** La represalia contra el dedo solo ataca a dedos que están en la pantalla en ese momento (antes golpeaba con chispas el último punto conocido, ya vacío), y el puñetazo normal ni siquiera hace el gesto si el rival no está a distancia de golpeo. El único golpe al aire que queda es el de dentro de una pelea real: el superpuñetazo que falla porque el rival se apartó, con su abalanzamiento.

**Mejoras generales de la misma pasada**

- **Lanzamiento más coherente**: al soltar un agarre, la velocidad del dedo se reparte por todo el cuerpo (entera en el punto agarrado, un 55 % en los demás) en vez de salir solo del punto agarrado con un latigazo que estiraba el cuerpo.
- **Rendimiento**: los intervalos visibles de las ventanas se calculan una vez por paso y se reutilizan en suelo, contactos y colisiones (antes se recalculaban por llamada); el escritorio se pausa con el creador abierto.
- **IA que respira**: al terminar una conducta, el stickman espera un respiro antes de decidir otra; el escritorio se siente vivo sin encadenar actividades sin parar.
- **Pulido visual**: borde fino que define las ventanas sobre el cielo, colinas más legibles y la sombra de contacto ya mencionada.

## Compilar

```bash
./build.sh          # compila Polytes.app sin firmar (requiere Xcode)
./package-ipa.sh    # genera build/Polytes.ipa
```

En GitHub, el workflow «Build iOS IPA (sin firmar)» hace lo mismo en un runner macOS y publica la `.ipa` en la release `app-v5`.
