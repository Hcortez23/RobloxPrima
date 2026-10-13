# Flujo de trabajo

## Ramas
- `main`: estable, solo recibe merges desde `develop`.
- `develop`: rama de integración, **aquí se trabaja el día a día**.
- `features`: trabajo de funcionalidades nuevas.
- `fixes`: correcciones de bugs.
- `hotfix`: arreglos urgentes sobre `main`.

Siempre `git pull` antes de empezar y `git push` al terminar.

## Estructura (evita conflictos: un archivo por feature por lado)
```
src/
  server/  init.server.luau      <- loader, no tocar
           Features/<Feature>.luau
  client/  init.client.luau      <- loader, no tocar
           Features/<Feature>.luau
  shared/  Remotes.luau          <- Remotes.get("Nombre") crea/obtiene un RemoteEvent
           Config/<Feature>.luau <- números de balance, uno por feature
```
Cada `Features/X.luau` devuelve `{ Start = function() ... end }` y el loader lo ejecuta solo.
Si una feature crece, conviértela en carpeta con `init.luau` dentro (Rojo la trata igual).

## Reparto sugerido (cada quien su dueño, no editen el mismo archivo)
- Persona A: Movement, Fracture, Capture
- Persona B: Extraction, Economy, Progression, Mural, Events

## Reglas
- Nombra los remotes `Feature_Accion` (ej. `Fracture_Hit`).
- Valores de balance en `shared/Config/`, no en el código.
- Si necesitas tocar un archivo ajeno, avísale primero.
- Diseño del juego: `NUCLEO_FRACTURA.md`.

## Dónde va Movement (doble salto, dash, gancho)
Solo se toca esto:
- `src/client/Features/Movement.luau`: toda la lógica (input, física del personaje, gancho). Corre en el cliente, no hace falta servidor para el prototipo.
- `src/shared/Config/Movement.luau`: velocidades, cooldowns, alcance del gancho.
- Si más adelante se necesita validar en servidor (anti-trampas): `src/server/Features/Movement.luau` y remotes `Movement_*`. Se crea entonces, no antes.

Para que no choque con el resto:
- Movement **no importa ni llama** a Fracture, Capture, Extraction ni a nada de Economy. Es independiente.
- El gancho dispara un raycast contra `Workspace`; los fragmentos solo necesitan ser `BasePart`s, así Capture los detecta por su lado sin que Movement sepa que existen.
- Capture (otro archivo) detecta fragmentos por contacto con el personaje; Movement solo mueve al personaje.
- Si una feature necesita saber algo de Movement (ej. "está en dash"), se expone con un atributo en el personaje (`character:SetAttribute("Dashing", true)`) en vez de requerir el módulo.

## Armas y cámara
- `Camera` (client/Features/Camera.luau): 1ª persona por defecto, rueda del ratón para pasar a 3ª.
- `Weapon` (server + client + shared/Config/Weapon.luau): hitscan desde la boca del arma (Tool "Rifle" en la mano, placeholder de Parts), mira al centro, mantener clic para disparar. No conoce a Fracture.
- Más armas: cualquier Tool con atributo `Weapon` dispara igual, con su propio `Damage` y, si tiene `ShotEffect`, un proyectil con los efectos de `ReplicatedStorage.WeaponEffects.<ShotEffect>`. `server/Features/CustomWeapons.luau` convierte modelos del mapa en esas armas según `Config.Weapon.CustomWeapons`. `Weapon.Hit` pasa el daño como 5º argumento.
- Fracture se suscribe al impacto desde su archivo de servidor:
  ```lua
  local Weapon = require(script.Parent.Weapon)
  Weapon.Hit:Connect(function(player, position, normal, instance)
      -- si instance tiene el tag "Fracturable", soltar celdas cerca de position
  end)
  ```

## Minerales
- **Mineral** = `Part` o `Model` con tag `Mineral` y atributo `Rarity` (ver `Config/Minerals.luau`). Puede haber uno solo o varios juntos. Con atributo `MaxHealth` recibe `Weapon.Damage` por disparo y muestra barra de vida; sin él explota de un tiro.
- Modelos de mineral por rareza: `assets/models/Minerals/Mineral_<Rareza>.model.json` (en `ReplicatedStorage.Assets.Minerals`), generados con `tools/generate-mineral-models.ps1`. Son plantillas sin tag; TestRoom los clona y les pone el tag.
- `server/Features/Minerals.luau`: disparar a un mineral lo hace **explotar**: desaparece, suelta materiales nuevos (**Loot**, otro objeto distinto, tag `Loot`; flota 6 s, vive 5 min, tope de 300 en el mundo y se ancla al asentarse) y detona en cadena a los minerales dentro del radio. Números en `Config/MineralBehavior.luau`.
- `client/Features/Minerals.luau`: efectos de la explosión (destello, onda, chispas, luz, temblor de cámara).
- `server/Features/Capture.luau`: cada Loot lleva un ProximityPrompt (`E`); al activarlo pasa al inventario y desaparece del mundo.
- `server/Features/Inventory.luau`: mochila. Datos en atributos `Inv_<Rareza>` del jugador (fuente de verdad); la barra de Roblox es la vista: un Tool por material, apilado ("Raro x3"). API: `Inventory.Add(player, item, n)`, `Count`. Aún sin DataStore.
- Fracture puede suscribirse a `require(script.Parent.Minerals).Exploded:Connect(function(position, radius) end)` para romper el escenario cercano a la explosión.
- Cambiar el arte no toca esta lógica.

## Mundo
- `server/Features/World.luau` + `shared/Config/World.luau`: meseta de 768×768 con **un pozo estrecho y vertical** (radio 42) de 800 de profundidad hasta el núcleo, hecho con Terrain por código (no se guarda en el repo). Nadie debería bajar por el pozo: es un vistazo al **núcleo** (esfera incandescente `Core` con luz y brasas). Caerse por ahí matará más adelante (pendiente; `Core` tiene el atributo `Core`).
- **Capas de roca** bajo la meseta con cuevas naturales. **Entradas** repartidas: 10 rampas inclinadas que se caminan y 8 pozos verticales.
- **Iluminación:** cristales luminosos en las cuevas (un color por capa); los minerales también brillan.
- **Reinicio diario:** la semilla es la fecha UTC, así que cada servidor genera el mismo mundo ese día. `Seed = <número>` en el config fija un mundo para depurar.
- **Minerales:** pool por capas (más raros hacia el núcleo), en grupos de 1 a 4, repuestos cada 30 s hasta `MineralCount`; además unos cuantos a la vista en la meseta y cerca del spawn. Salud por rareza en `Config/Minerals.luau`.
- Las explosiones de minerales excavan el terreno (`CarveFactor`). Fracture puede añadir fragmentos al excavar, suscribiéndose a `Minerals.Exploded`.
- Los jugadores aparecen cuando está generada la capa 1 cerca del centro (el Output imprime el tiempo y el % de aire de la zona de cuevas, útil para afinar las cuevas).
- `server/Features/Ambience.luau`: ambiente **postapocalíptico sci-fi** (atardecer polvoriento, bruma ocre, colores apagados, bloom para el neón, nubes, colores de terreno). Se afina todo ahí.
- Sin plataformas: no hay Baseplate, `TestRoom` ni `GrappleTest`; el gancho se engancha al terreno.
- El rifle ya no sale de StarterPack: `Weapon` (servidor) lo entrega al aparecer cada personaje, y `Movement` evita duplicar el gancho. `Config/Weapon.Debug = true` imprime los disparos en el Output.

## Mundo, base y carritos
- `server/Features/World.luau` + `shared/Config/World.luau`: genera el terreno (cuevas solo en la capa 1; más abajo roca maciza por bloques), la cueva del foso con las 8 cuevas-base y sus pasajes alrededor (disposición en `shared/BaseLayout.luau`), el pozo, arenas, minas, hubs y minerales. Exporta `World.Route` (ruta principal), `World.CanDig(pos, radio)`, `World.Hardness(profundidad)`, `World.Mines` y `World.Hubs`.
- **Generación por celdas, bajo demanda** (para no llenar la memoria con un mundo de 2.048 × 2.048 × 8.000): el mundo son celdas de 128 × 128 × 200. Al inicio solo se genera la capa 1 cerca del centro; la columna del pozo se completa en segundo plano (tallada con formas, no voxel a voxel) y el resto se genera alrededor de cada jugador (`Config.Generation`), tallando ahí las minas y los hubs y sembrando vetas en la roca nueva. Los minerales profundos lejos de todos se reciclan cuando se llena el tope. Lo que no existe todavía no se puede excavar ni ver: si agregas algo que se talla en la roca profunda, llama antes a `ensureBox` con su caja (si no, la celda lo taparía al generarse).
- El bucle voxel a voxel (`generateChunk`) es lo más caro: sin crear tablas ni vectores por voxel, Enums y funciones en locales, y solo en las profundidades donde puede haber cuevas. El módulo usa `--!native`. Para medir fuera de Studio se puede correr World con un entorno simulado en el CLI de Luau.
- `shared/Config/Biomes.luau`: 10 capas con 4 biomas cada una (nombre, tema, material, luz, tinte y `Effect`, la mecánica por implementar) y el color de cada material. `Config/World` calcula cada capa (profundidad, dureza, rareza, cantidad) con curvas.
- `shared/BiomeMap.luau`: qué bioma hay en cada punto (cuadrantes alrededor del pozo, girados por capa). Lo usan World (material de la roca) y el cliente (ambiente); para una mecánica de bioma, pregunta aquí `BiomeMap.At(posición)`.
- `client/Features/Biomes.luau`: ambiente por bioma y aviso con la capa y el bioma al entrar.
- `server/Features/Hub.luau`: utilería de la cueva del foso (rejilla, máquinas, portal DESCENSO, puerta de arco).
- `server/Features/Route.luau`: rieles, cables y letreros de la ruta (los rieles y el cable se simplifican en tramos rectos largos: pocas piezas); exporta `Route.Paths` (puntos del suelo) y pone `workspace.RouteReady`.
- `server/Features/Bases.luau` + `Config/Bases.luau`: una cueva-base por jugador (spawn, arcos, andén, panel y un silo por cada tipo de `Config/Minerals`). Datos en atributos del jugador: `Stored_<Mineral>`, `Stat_Carts`, `Stat_Captured`, `Stat_DeepestLayer`. API: `Bases.Get`, `Bases.All`, `Bases.Deposit`, `Bases.TakeInventory`. Pone `workspace.BasesReady`.
- `server/Features/SignKit.luau`: **todos los carteles con texto** se hacen con `SignKit.Build(parent, nombre, cframe, ancho, alto, opciones)` (placa con marco, perfil de neón, tornillos, fondo con degradado, título con contorno y subtítulo; estilos `metal`, `rust` y `screen`; texto en las dos caras). Si agregas un cartel, úsalo para que se vean todos iguales. La excepción es el panel de estadísticas de la base, que tiene su propio diseño.
- `server/Features/BaseDecor.luau`: ambientación de cada cueva-base (paredes, techo con luces, pasarela, plataforma de mando, monumento, contenedores, estandartes). La llama `Bases.luau` con las medidas de lo que ya armó (`ctx`) para no taparlo; los estandartes se suman a los letreros con el nombre del dueño.
- `server/Features/Mural.luau` (+ cliente): estands del mural en cada base, sobre las marcas `MuralSlot` de Bases. Muestran los tipos guardados del dueño (centro = el más valioso) o el que eligió (atributo `Mural_<estand>`); el cliente hace girar los minerales (tag `MuralExhibit`) y muestra el aviso de cambiar solo al dueño (tag `MuralPrompt`).
- `server/Features/Mines.luau`: utilería de las minas abandonadas de `World.Mines` (entibado, rieles, carritos, máquinas, campamentos); se arma cerca de los jugadores y se quita al alejarse. La forma (galerías, salas, pozos) la talla World con `Config.Mines`.
- `shared/HubLayout.luau`: dónde está el hub de cada capa (y su elevador, terminal de permiso y estación). Lo usan World (los talla y exporta `World.Hubs[capa]` cuando están listos), LayerHubs, Carts y Progression.
- `server/Features/LayerHubs.luau`: utilería de los hubs (baranda del pozo, elevador, terminal del permiso, letrero, lámparas).
- `server/Features/Progression.luau` + `Config/Progression.luau`: capas desbloqueadas por jugador (`Progress_Unlocked`, `Hub_<capa>`), permiso de descenso (`Progression.BuyPermit`), límite de excavación (`Progression.CanDigDepth`, lo usa Excavation), presión (`Pressure`) y elevador (remotes `Elevator` y `Progress_Notify`; pantalla en `client/Features/Progression.luau`).
- `server/Features/Carts.luau` + `Config/Carts.luau`: estación de carritos en cada hub; el carrito es visual y entrega en la base (`Bases.Deposit`) en cuanto entra al túnel.
- `server/Features/Excavation.luau` (+ cliente) y `Config/Excavation.luau`: los disparos al terreno excavan según `DigPower` del arma y `Hardness` de la capa.
- Rendimiento: `StreamingEnabled` está activo (radio 384: bajo tierra no se ve más lejos), así que en el cliente no hay que suponer que todo el mapa existe. Y en el servidor tampoco: lo lejano de los jugadores no está generado.