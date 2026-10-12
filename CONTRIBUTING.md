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
- `server/Features/Minerals.luau`: disparar a un mineral lo hace **explotar**: desaparece, suelta materiales nuevos (**Loot**, otro objeto distinto, tag `Loot`) y detona en cadena a los minerales dentro del radio. Números en `Config/MineralBehavior.luau`.
- `client/Features/Minerals.luau`: efectos de la explosión (destello, onda, chispas, luz, temblor de cámara).
- `server/Features/Capture.luau`: tocar un Loot lo captura y suma su valor al atributo `Carried` del jugador.
- Fracture puede suscribirse a `require(script.Parent.Minerals).Exploded:Connect(function(position, radius) end)` para romper el escenario cercano a la explosión.
- Cambiar el arte no toca esta lógica.
