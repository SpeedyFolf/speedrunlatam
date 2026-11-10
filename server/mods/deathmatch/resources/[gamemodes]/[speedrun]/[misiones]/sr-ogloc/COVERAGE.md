# OG Loc (`SMOKE1`): speedrun

Mision adaptada del test-resource `og-loc` de `san-andreas-online` al gamemode
`speedrun`. Se conserva la mision completa, incluidas las cutscenes y las escenas
scripteadas; **todas se pueden skipear** para que el jugador optimice el tiempo.

## Dependencias

- `native-task-runtime`: cohorts nativas (Freddy/OG Loc, goons), grabaciones de
  vehiculos 30-40 y obstaculos 50-60, politica de vehiculos.
- `story-world-runtime`: `CREATE_CAR`/`CREATE_CHAR` SCM, ocupacion de vehiculos,
  teardown del mundo, modelo de jugador para las cutscenes.

Ambos se cargan desde `speedrun/meta.xml`:
```xml
<include resource="native-task-runtime" />
<include resource="story-world-runtime" />
```

## Flujo

| Etapa | Que pasa |
| --- | --- |
| `cutscene:SMOKE1A` | Cutscene de archivo en Grove; skip nativo. |
| `drive_police` | Glendale con Big Smoke/Sweet a la comisaria. |
| `cutscene:SMOKE1B` | Cutscene de archivo en la comisaria; skip nativo. |
| `drive_house` | Glendale con Big Smoke/Sweet/OG Loc a la casa de Freddy. |
| `scene:freddys_house_arrival` | Llegada a la casa; camara/audio; skip con tecla. |
| `doorbell` | Bajar y llegar al timbre a pie. |
| `scene:doorbell` | Escena del timbre/ventana; skip con tecla. |
| `chase_recording:30..40` | PCJ-600 con OG Loc; Freddy; 11 grabaciones; obstaculos. |
| `basketball_combat` | Pelea en la cancha; Freddy/goons con cohortes nativas. |
| `scene:freddy_dead` | Escena de Freddy muerto; skip con tecla. |
| `return_burger_shot` | Volver a Burger Shot con OG Loc. |
| `scene:burger_shot` | Escena final; skip con tecla. |
| `passed` | `reportCompleted` + `M_PASSR`/tune. |

## Skip

- **Cutscenes de archivo**: `isFileCutsceneSkipInputPressed` (skip nativo) →
  `ogl:skipRequest` → `skipFileCutscene`. El jugador puede saltear
  `SMOKE1A`/`SMOKE1B` con el botón de skip de GTA.
- **Escenas scripteadas**: `onClientKey`/`onClientClick` en la escena; `space`,
  `return`, `f` o click izquierdo llaman a `finishScene`, cortan audio/camara/
  animaciones y reportan el barrier.
- El timer empieza en el `go` de la base; las cutscenes/escenas cuentan para el
  run y el skip es una decision del jugador.

## Datos

- `SMOKE1` GXT; audio de mision 35000-35075; modelos `glendale=466`, `pcj600=461`,
  `smoke=269`, `sweet=270`, `ogloc=293`, `freddy=109`, `goon=110`.
- `playerState`: Grove `2072.9,-1690.6,13.5` rot `33.0`; Uzi (Micro SMG 28) +
  pistola; vida 80; dinero 410; `populationStage=postCleaningTheHood`.
- Una copia por jugador; la dimension viene de `speedrun` (`inst.dim`); los
  eventos `ogl:*` usan el token de la copia y se envian solo a `inst.player`.

## Transiciones

- Fades alineados con `main.scm`: cutscene de archivo 1.0 s de fade-in; fade-out
  corto al terminar y negro hasta que el server arma el gameplay; escenas 0.5 s.
- `freddys_house_arrival` y `burger_shot` funden a negro antes del cambio de
  camara/actores; `doorbell` y `freddy_dead` arrancan desde el negro del teardown.
- El warp de salida del Glendale espera ~150 ms antes de mover/descongelar para
  que el cliente no quede con la animacion del vehiculo. En `doorbell` se hace
  ground-snap de la Z y se limpia el estado de vehiculo. El warp a la PCJ espera
  a que el cliente este sentado antes del fade-in.
- Checkpoints 3D: cilindro rojo; tamano tomado de los radios de `locate` del SCM
  (4.0 comisaria/casa/burger, 1.2 timbre). El blip del radar queda amarillo.

## Estado

- `implemented`: viajes, timbre, chase, combate, retorno, cutscenes/escenas,
  skip de cutscenes, skip de escenas, fail/pass, fades y warps.
- `adapted`: `playerState` y armas para el speedrun; cohortes/playbacks con
  `native-task-runtime`; SCM Z/ocupacion con `story-world-runtime`.
- `pending`: drive-by custom del jugador (input por `vehicle_fire`, SFX nativos y
  descuento de ammo); **el dano y la animacion todavia no estan implementados**.
  Validar en juego los tiempos/framing de las escenas y la dificultad de la
  chase; el fail "Freddy escapo" depende de la visibilidad del cliente.
- `source`: adaptado de `Dryxio/san-andreas-online`, `test-resources/og-loc`
  (commit `54d4054`), con las dependencias `official-resources/native-task-runtime`
  y `official-resources/story-world-runtime`.
