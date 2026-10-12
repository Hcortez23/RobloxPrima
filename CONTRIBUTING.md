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
- Fracture se suscribe al impacto desde su archivo de servidor:
  ```lua
  local Weapon = require(script.Parent.Weapon)
  Weapon.Hit:Connect(function(player, position, normal, instance)
      -- si instance tiene el tag "Fracturable", soltar celdas cerca de position
  end)
  ```

## Minerales
- **Mineral** = `Part` con tag `Mineral` y atributo `Rarity` (ver `Config/Minerals.luau`). Puede haber uno solo o varios juntos.
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
- Los jugadores aparecen cuando termina de generarse (el Output imprime tiempo y % de aire por capa, útil para afinar las cuevas).
- `server/Features/Ambience.luau`: ambiente **postapocalíptico sci-fi** (atardecer polvoriento, bruma ocre, colores apagados, bloom para el neón, nubes, colores de terreno). Se afina todo ahí.
- Sin plataformas: no hay Baseplate, `TestRoom` ni `GrappleTest`; el gancho se engancha al terreno.
- El rifle ya no sale de StarterPack: `Weapon` (servidor) lo entrega al aparecer cada personaje, y `Movement` evita duplicar el gancho. `Config/Weapon.Debug = true` imprime los disparos en el Output.
