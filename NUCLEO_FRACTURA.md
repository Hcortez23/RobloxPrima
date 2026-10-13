# Núcleo: Fractura — Visión General

Oct 11, 2026

## Concepto

"Núcleo: Fractura" es un movement extraction shooter para Roblox: el jugador dispara para fracturar el escenario y captura los fragmentos en el aire usando mecánicas de movilidad, antes de extraer lo obtenido.

## Core loop

- Disparar para fracturar el escenario

- Los fragmentos quedan sueltos en el aire

- El jugador se mueve con gancho, dash y doble salto para capturarlos antes de que caigan

- Las capturas provocan reacciones en cadena con fragmentos cercanos

- El jugador decide seguir arriesgando o dirigirse al punto de extracción

Las sesiones están diseñadas para durar lo más posible dentro de un mismo run, buscando el efecto de "ya llevo mucho, no puedo parar ahora" (sunk cost) para maximizar tiempo de juego.

## Economía y riesgo

Los materiales recolectados se venden para comprar mejoras y progresión. Si el jugador muere sin protección, pierde todos sus materiales de forma global (no solo los del run actual).

La única forma de evitar esta pérdida es:

- Pagar con Robux en el momento, o

- Tener activo un pase de suscripción mensual que protege contra la pérdida al morir

## Mural de exhibición

Cada jugador tiene un mural tipo corral en su cueva-base para guardar y exhibir materiales raros.

- 5 espacios disponibles

- Los materiales exhibidos siguen siendo vendibles (no se bloquean)

- Visible para otros jugadores que visiten la base, con componente social/status
- Implementado (`server/Features/Mural`): 5 estands-vitrina a la derecha de la entrada de cada cueva-base, con el mineral girando adentro y una placa con nombre, cantidad y valor. El del centro, más grande, es el trofeo con el mineral más valioso. Se llenan solos con los tipos guardados, del más valioso al menos; el dueño puede cambiar cada uno con "Exhibir otro mineral"

## Progresión

- Nivel de Extractor: progresión principal del jugador

- Rareza dinámica: eventos de servidor que afectan la probabilidad de obtener recompensas raras

- Eventos de minerales únicos: además de los eventos de rareza, habrá eventos donde spawnean minerales únicos bien escondidos en el mapa

## Progresión por capas

El terreno (y los túneles que excavan otros) es el mismo para todos, pero cada jugador tiene **sus propias capas desbloqueadas** (`server/Features/Progression`, números en `shared/Config/Progression.luau`), así que nadie se salta la progresión siguiendo el túnel de otro:

- **Permiso de descenso:** en el hub de su capa más profunda compra el permiso para la siguiente. Se paga con el valor de lo guardado en su base (primero lo más barato; de 40 para la capa 2 a 40.000 para la capa 10) y además pide un arma con poder de excavación suficiente para la dureza de esa capa.
- **Excavar:** nadie excava más abajo del fondo de su última capa desbloqueada.
- **Presión:** si entra a una capa sin permiso (por un túnel ajeno), aparece un aviso rojo y, tras 3 segundos, daño creciente hasta que suba o muera (reaparece en su base).
- **Hubs y elevador:** para usar el elevador hacia un hub hay que haberlo descubierto (llegando hasta él) y tener permiso para su capa. La primera vez que se baja a una capa nueva, se baja excavando.
- Por ahora no se guarda entre sesiones (pendiente: DataStore).
## Competitivo

No hay PvP directo por el momento. Los jugadores compiten indirectamente a través de rankings y leaderboards (colecciones, rachas de fracturas, etc.). Se contempla agregar servidores anárquicos (con PvP) más adelante, como modo aparte.

## Mundo

Generado por código (`server/Features/World.luau`, números en `shared/Config/World.luau`); cambia cada día según la semilla. Para ahorrar memoria, solo existe lo que hace falta: la capa 1 cerca del centro al empezar, la columna del pozo completa y, del resto, lo que rodea a los jugadores (se genera a medida que exploran).

- **Cuevas-base (spawn de cada jugador):** 8 cuevas propias (radio 140, del tamaño de la antigua cueva de spawn) en anillo alrededor de la cueva del foso, cada una unida a ella por un pasaje con arcos que muestran el nombre del dueño. Cada jugador aparece en la suya. Dentro: andén de carritos con tolva, grúa y cinta; panel de estadísticas a la izquierda de la entrada (almacén, valor, tipos conseguidos, envíos, minerales capturados, capa más profunda); mural de exhibición de 5 espacios; y una nave de almacén con **un silo por cada tipo de mineral** (en filas de 10, pensada para ~100 tipos), cada uno con barra de llenado y placa con nombre y cantidad.
- **Cueva del foso = zona común (hub de la capa 1):** el spawn general, el portal DESCENSO, las bocas de los 8 pasajes, la estación de carritos, el elevador y el terminal del permiso para la capa 2.
- **Cueva del foso:** caverna enorme bajo el centro del mapa, con luces y máquinas industriales; es la entrada a la experiencia. Su única salida es el portal "DESCENSO".
- **El pozo al núcleo = eje del mundo:** tubo vertical desde la cueva del foso (tapada por una rejilla con cristal) hasta el núcleo, que se ve brillar desde todos los hubs. No se puede excavar hacia él desde la roca: se entra por los hubs.
- **Un hub por capa:** caverna alrededor del pozo (en la capa 1 es la cueva del foso; en las demás, a 180 studs bajo el techo de la capa), con el pozo abierto en medio tras una baranda de vidrio, letrero con la capa, **elevador** (cabina junto al pozo: lleva a los hubs descubiertos de capas desbloqueadas), **terminal del permiso de descenso** a la capa siguiente, **estación de carritos** y, de la capa 2 hacia abajo, 4 galerías entibadas con rieles hacia las minas de su capa. Un hub se descubre al entrar en él.
- **Zona de cuevas (capa 1):** cuevas naturales anchas e interconectadas hasta 560 studs alrededor del pozo, con 7 cavernas-arena grandes (salientes, pilares, estalactitas) para perseguir fragmentos con gancho, dash y doble salto. Es la única capa con cuevas naturales.
- **De la capa 2 hacia abajo, todo se excava:** roca maciza que se abre disparando; cuanto más hondo, más dura (`Hardness` por capa). Cada arma tiene un poder de excavación (`DigPower`): con un arma débil la roca profunda no cede, así que bajar exige mejores armas. Los minerales están incrustados en vetas dentro de la roca.
- **Minas abandonadas (capa 2 en adelante):** no hay cuevas naturales, pero sí minas talladas en la roca, muy seguidas (34 complejos y 40 campamentos por capa). Complejo: sala central con letrero "SECTOR capa-número", 3–5 galerías entibadas con faroles (pocos encendidos), rieles y carritos abandonados (algunos volcados), ramales, salas al final (almacén, taller con perforadora y generador, dormitorio con literas), derrumbes y a veces un pozo con escalera. Campamento: sala pequeña con tienda, fogata apagada, saco de dormir y mochila. La mitad de los minerales de las capas profundas aparece en el suelo de las minas; el resto, en vetas dentro de la roca. La utilería se arma solo cerca de los jugadores (`server/Features/Mines`).
- **Ruta (orientación):** rieles, cables y letreros ("▲ BASE" / "▲ DESCENSO") desde el portal por los túneles de la zona de cuevas.
- **Carritos (la extracción):** en la estación de cada hub el jugador envía lo que lleva. El carrito es solo visual: entra lleno por un túnel corto solo para carritos (una reja no deja pasar a los jugadores) y, apenas se pierde de vista, lo que lleva se suma al almacén de su base y el carrito desaparece; enseguida sale uno vacío para el siguiente envío. Lo que se lleva encima está en riesgo; lo que llega a la base, a salvo.
- **Cámara del núcleo:** al fondo; se llega excavando a través de todas las capas.
- **Superficie:** por ahora no se puede llegar (la salida está desactivada), así que es roca plana; el relieve con montañas se activa con `SurfaceRelief` cuando haga falta.

### Capas y biomas (10 capas de 800 studs; 8.000 de profundidad; mapa de 2.048 × 2.048; 4 biomas por capa)

Cada capa se reparte en 4 cuadrantes alrededor del pozo, con bordes ondulados, y el reparto gira de una capa a otra: bajando en línea recta se cruzan biomas distintos. Los biomas están siempre en el mismo sitio (no dependen de la semilla del día). La zona común de arriba (cuevas del foso y de las bases) es de roca neutra. Catálogo en `shared/Config/Biomes.luau`; reparto en `shared/BiomeMap.luau`.

Orden por dificultad: arriba, biomas que ayudan (impulsos, flotación, puntos de recolección); en medio, combos y reacciones en cadena; luego presión de tiempo y entornos hostiles; al fondo, reglas rotas y biomas letales. Cada capa mezcla temas distintos.

| Capa | Nombre | Biomas |
|---|---|---|
| 1 | Umbral vivo (zona de cuevas) | Cueva Fúngica Bioluminiscente · Gruta de Esporas Flotantes · Catarata Subterránea · Bolsillo de Microgravedad |
| 2 | Corrientes ascendentes | Chimenea Geotérmica · Cueva de Géiseres · Caverna de Raíces Vivas · Cueva de Vórtices |
| 3 | Ecos y cadenas | Cueva Armónica · Caverna de Eco Fractal · Cueva de Líquenes Eléctricos · Caverna Magnética |
| 4 | Redes quebradizas | Cueva de Cuarzo Resonante · Caverna Glacial · Gruta de Estalactitas Quebradizas · Caverna de Andamiaje Colapsado |
| 5 | Riesgo y reflejo | Gruta de Prismas · Caverna de Obsidiana · Jardín de Cristal Orgánico · Lago Subterráneo Congelado |
| 6 | Contrarreloj | Catedral de Sal Cristalina · Cueva de Escarcha Viva · Caverna de Permafrost · Túnel de Minado Automatizado |
| 7 | Elementos hostiles | Túneles de Magma Vivo · Caverna Inundada · Falla de Gravedad Pulsante · Cueva de Ceniza Ardiente |
| 8 | Suelo traicionero | Río de Lava Lenta · Caverna de Gravedad Invertida · Gruta de Niebla Ácida · Lago de Mercurio Líquido |
| 9 | Leyes rotas | Núcleo Reactor Abandonado · Cueva de Anomalía Temporal · Vacío de Antimateria Contenida · Pantano de Esporas Letales |
| 10 | Zona letal (endgame) | Caldera del Colapso Térmico · Fosa del Cero Absoluto · Cueva de Disonancia Cognitiva · Abismo de Rareza Inestable |

Hoy cada bioma tiene su roca (material y color), su luz ambiental y su tinte, y al entrar aparece su nombre en pantalla ("CAPA 3 · Caverna Magnética"). La mecánica propia de cada uno está descrita en `Effect` (Config/Biomes) y **falta implementarla**. Por capa crecen la dureza (×1.34 por capa: de 1 a ~14) y la rareza de los minerales, y baja su cantidad.
## Dirección artística

Estética base sci-fi/industrial, con posibilidad de integrar distintos biomas más adelante.

## Pendientes de definir

- ☐ Barra de "estabilidad del núcleo" que se degrada con el tiempo, para generar tensión creciente durante el run

- ☑ Biomas: 10 capas con 4 biomas cada una (40), ordenados por dificultad; visuales (roca, color, luz, tinte) y aviso en pantalla
- ☐ Mecánicas propias de cada bioma (gravedad alterada, calor, frío, esporas, agua, etc.; descritas en `Config/Biomes`)

- ☐ Guardar el almacén y las estadísticas de la base entre sesiones (DataStore)

- ☐ Cómo encaja la pérdida al morir con el almacén de la base (hoy solo se pierde lo que se lleva encima)

- ☐ Si los minerales únicos rotan de posición en cada evento o son fijos en el mapa


