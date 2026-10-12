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
