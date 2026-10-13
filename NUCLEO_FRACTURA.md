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

- **Cueva de la base (spawn):** donde aparecen los jugadores; aquí van las bases y las tiendas. Es el punto de partida y de regreso.
- **Gran puerta de arco:** un pasaje une la cueva de la base con la cueva del foso.
- **Cueva del foso:** caverna enorme bajo el centro del mapa, con luces y máquinas industriales; es la entrada a la experiencia (de aquí se baja a las arenas).
- **El pozo al núcleo:** tubo vertical desde el piso de la cueva del foso hasta el núcleo, tapado por una rejilla con cristal. Se ve el brillo del núcleo pero no se puede bajar por ahí, y ninguna cueva lo cruza: no hay atajo a las capas profundas.
- **Capas hacia el núcleo (2,400 studs):** cuatro capas con roca, luz y minerales propios; cuanto más hondo, más raros.
- **Cavernas-arena:** cavernas grandes y verticales en cada capa (salientes, pilares, estalactitas) para perseguir fragmentos con gancho, dash y doble salto. Una cadena de túneles las une desde la base hasta la cámara del núcleo.
- **Cámara del núcleo:** al fondo, el último eslabón del recorrido.
- **Superficie:** meseta con montañas hacia los bordes, a la que se sube desde la base.

## Dirección artística

Estética base sci-fi/industrial, con posibilidad de integrar distintos biomas más adelante.

## Pendientes de definir

- ☐ Barra de "estabilidad del núcleo" que se degrada con el tiempo, para generar tensión creciente durante el run

- ☐ Si los biomas afectan la física de fractura o son solo estéticos

- ☐ Si los minerales únicos rotan de posición en cada evento o son fijos en el mapa


