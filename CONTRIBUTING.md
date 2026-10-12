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
