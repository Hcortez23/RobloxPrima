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

Cada jugador tiene un mural tipo corral en su zona de spawn para guardar y exhibir materiales raros.

- 5 espacios disponibles

- Los materiales exhibidos siguen siendo vendibles (no se bloquean)

- Visible para otros jugadores que visiten el spawn, con componente social/status

## Progresión

- Nivel de Extractor: progresión principal del jugador

- Rareza dinámica: eventos de servidor que afectan la probabilidad de obtener recompensas raras

- Eventos de minerales únicos: además de los eventos de rareza, habrá eventos donde spawnean minerales únicos bien escondidos en el mapa

## Competitivo

No hay PvP directo por el momento. Los jugadores compiten indirectamente a través de rankings y leaderboards (colecciones, rachas de fracturas, etc.). Se contempla agregar servidores anárquicos (con PvP) más adelante, como modo aparte.

## Mundo

Generado por código (`server/Features/World.luau`, números en `shared/Config/World.luau`); cambia cada día según la semilla.

- **Cueva de la base (spawn):** cada jugador tiene su base, una bahía industrial en el anillo de la cueva, y aparece en ella. Tiene andén de carritos, tolva y cinta que llenan 4 silos (uno por rareza), panel de estadísticas (almacén, valor, envíos, minerales capturados, capa más profunda), mural de exhibición de 5 espacios, grúa y techo. El centro queda como plaza para las tiendas.
- **Gran puerta de arco:** un pasaje une la cueva de la base con la cueva del foso.
- **Cueva del foso:** caverna enorme bajo el centro del mapa, con luces y máquinas industriales; es la entrada a la experiencia. Su única salida es el portal "DESCENSO".
- **El pozo al núcleo:** tubo vertical desde el piso de la cueva del foso hasta el núcleo, tapado por una rejilla con cristal. Se ve el brillo del núcleo pero no se puede bajar por ahí, ni cavar hacia él: no hay atajo a las capas profundas.
- **Zona de cuevas (capas 1–2):** desde la entrada inicial se bifurcan cuevas naturales y 4 cavernas-arena (salientes, pilares, estalactitas) para perseguir fragmentos con gancho, dash y doble salto.
- **De la capa 3 hacia abajo, todo se excava:** roca maciza que se abre disparando; cuanto más hondo, más dura (`Hardness` por capa). Cada arma tiene un poder de excavación (`DigPower`): con un arma débil la roca profunda no cede, así que bajar exige mejores armas. Los minerales están incrustados en vetas dentro de la roca.
- **Ruta y carritos (la extracción):** rieles, cables y letreros ("▲ BASE" / "▲ DESCENSO") desde el portal por los túneles de la zona de cuevas. En las estaciones (cueva del foso, cámara de cruce y cada arena) el jugador envía lo que lleva y un carrito lo lleva por los rieles hasta el andén de su base, donde se suma al almacén. Lo que se lleva encima está en riesgo; lo que llega a la base, a salvo.
- **Cámara del núcleo:** al fondo; se llega excavando a través de todas las capas.
- **Superficie:** meseta con montañas hacia los bordes; por ahora no se puede llegar (la salida está desactivada).

### Capas (20, de 240 studs; 4.800 de profundidad)

| Bioma | Capas |
|---|---|
| **Corteza en ruinas** (roca gris y ceniza) | 1 Sótanos colapsados · 2 Galerías de escombro · 3 Vetas de ceniza · 4 Fosas de chatarra |
| **Salares de cristal** (sal blanca rosada, brillo frío) | 5 Llanuras de sal · 6 Geodas rosadas · 7 Bosque de prismas · 8 Cámara de ecos |
| **Criogrietas** (hielo azul) | 9 Grietas de escarcha · 10 Glaciar enterrado · 11 Lagos congelados · 12 Corazón de hielo |
| **Basalto ferroso** (roca oscura oxidada) | 13 Coladas de basalto · 14 Minas de hierro · 15 Forja olvidada · 16 Columnas negras |
| **Manto incandescente** (roca agrietada sobre lava) | 17 Brasas dormidas · 18 Ríos de magma · 19 Cámara de presión · 20 Umbral del núcleo |

Cada bioma tiene su roca, su color y su luz ambiental; al entrar en una capa aparece su nombre en pantalla. Por capa crecen la dureza (×1.15 por capa: de 1 a ~14) y la rareza de los minerales, y baja su cantidad.
## Dirección artística

Estética base sci-fi/industrial, con posibilidad de integrar distintos biomas más adelante.

## Pendientes de definir

- ☐ Barra de "estabilidad del núcleo" que se degrada con el tiempo, para generar tensión creciente durante el run

- ☑ Biomas: 5 biomas de 4 capas; visuales (roca, color, luz); la jugabilidad cambia por la dureza de cada capa

- ☐ Guardar el almacén y las estadísticas de la base entre sesiones (DataStore)

- ☐ Cómo encaja la pérdida al morir con el almacén de la base (hoy solo se pierde lo que se lleva encima)

- ☐ Si los minerales únicos rotan de posición en cada evento o son fijos en el mapa


