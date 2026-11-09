# Deploy continuo (CD)

Esta guía es para cualquiera que toque el server. La idea es que sepas **qué
pasa cuando creás un tag** y qué tenés que hacer (o no hacer) según el tipo de
cambio.

Regla corta:

- Tocaste **`server/`** (resources, configs): tag + automático, sin Reinstall.
- Tocaste **`docker/`** (imagen): hace falta **un Reinstall**. No hay forma de
  actualizar la imagen del contenedor por archivos.

## Lo primero: ¿qué toqué?

| Cambio | Qué hace el CD | Downtime |
| --- | --- | --- |
| `server/mods/deathmatch/resources/**` (resource normal) | Aplica el delta y hace `restart <resource>` | No |
| Gamemode (`speedrun`, `race`) | `restart` del gamemode al final del plan | No |
| Resource protegido (`resourcebrowser`, `resourcemanager`) | `power restart` | Segundos |
| `mta-server64`, `x64/**`, `mtaserver.conf.template` | `power restart` (regenera `mtaserver.conf`) | Segundos |
| `docker/**` (Dockerfile, entrypoint, deploy_agent, install) | **Requiere Reinstall** | Reinstall |
| `mods/deathmatch/settings.xml` o `acl.xml` | **No los toca**: se aplican a mano | — |
| `docs/`, `scripts/`, `tests/`, workflows | No genera deploy (el manifest queda `noop`) | — |

Los archivos de `docker/**` no se pueden actualizar en caliente porque el agente
que hace el deploy vive **dentro de la imagen**. Para estrenar una imagen nueva
hay que recrear el contenedor (Reinstall), una vez.

## Qué hace el CD (y qué no)

Hace:

1. En cada tag `v*` construye tres assets:
   - `server-template.tar.gz`: el server completo (instalación desde cero).
   - `server-update.tar.gz`: solo los archivos que cambiaron desde el tag
     anterior.
   - `update.json`: el manifest que le dice al agente qué hacer.
2. Si `CD_ENABLED=true`, el job de deploy escribe el pedido en `.deploy/` por la
   API del panel y manda los comandos MTA (`stop`, `refresh`, `start`,
   `restart`) también por la API.
3. El agente del contenedor descarga el delta, valida SHA256 y rutas, hace
   snapshot de datos, backup del código y aplica los archivos.
4. Verifica `mods/deathmatch/logs/server.log` y marca `done` o `failed`.
5. Si falla la verificación, hace rollback del **código** (no de la DB).

No hace:

- El agente **no** manda comandos a la consola. Eso lo hace GitHub Actions por
  la API del panel (`/command`).
- No actualiza la imagen del contenedor (para eso, Reinstall).
- No pisa `settings.xml` ni `acl.xml`.
- El rollback no restaura la DB: solo el código. Restaurar la DB perdería los
  tiempos y cuentas posteriores al deploy.

## Los modos del manifest

`update.json` trae un `mode` que explica qué va a pasar:

| `mode` | Cuándo | Qué hace el deploy |
| --- | --- | --- |
| `hot` | Solo cambiaron resources normales | Aplica y reinicia el resource |
| `restart` | Cambió un archivo que no es resource (`mta-server64`, `x64/**`, `mtaserver.conf.template`) o un resource protegido | `power restart` (segundos) |
| `recreate` | Cambió `docker/**` | Falla y pide Reinstall |
| `full` | No hay tag anterior | Instala el template completo |
| `noop` | No hay nada que aplicar | No hace nada |
| `manual` | Solo cambió `settings.xml`/`acl.xml` | Lo lista y no lo aplica |

Otros campos útiles: `previous_tag` (tag contra el que se calculó el delta),
`changes` (archivos), `resources` (altas/bajas/cambios), y
`requires_process_restart` / `requires_container_recreate`.

## Variables de GitHub

No van en el `.env` del server. Van en **GitHub → Settings → Secrets and
variables → Actions → Variables**:

| Variable | Default | Para qué |
| --- | --- | --- |
| `CD_ENABLED` | `false` | Habilita el job de deploy automático en tags |
| `CD_ANNOUNCE` | `0` | `1` manda un `say` y espera antes de recargar |
| `CD_DELAY_GAMEMODE` | `30` | Segundos de espera si cambia un gamemode |
| `CD_DELAY_RESOURCE` | `10` | Segundos de espera si solo cambian resources |
| `CD_DELAY_RESTART` | `30` | Segundos de espera antes de un `power restart` |
| `CD_IMAGE_CURRENT` | `false` | Ver abajo. Solo para releases que cambian `docker/**` |

`CD_IMAGE_CURRENT=true` significa: **“ya reinstalé la imagen de este release,
no me pidas otro Reinstall”**. El deploy reescribe el manifest a `hot`/`restart`
y aplica solo los archivos del server.

Dejarla en `true` permanentemente es peligroso: un release futuro con
`docker/**` se aplicaría contra la imagen vieja y quedarías con el agente o el
entrypoint desactualizados sin darte cuenta. Por eso está en `false`.

Estado actual del repo: `CD_ENABLED=true`, `CD_ANNOUNCE=1`,
`CD_IMAGE_CURRENT=false`.

## El caso normal: cambio de resources

1. Mergeá a `main`.
2. Creá y pusheá el tag:
   ```bash
   git checkout main && git pull
   git tag -a v1.7.0 -m "v1.7.0"
   git push origin v1.7.0
   ```
   El tag tiene que estar sobre `main`; el job de deploy lo verifica y se niega
   si no.
3. GitHub → Actions → workflow **server-template**. El job `build` publica los
   assets y el job `deploy` aplica el cambio.
4. En el log del deploy vas a ver algo así:
   ```text
   [agent] prepare: prepared v1.7.0 prepared
   [console] input ok
   [deploy] announced 10s before reload
   [agent] apply: applied
   [mta] restart joinquit
   [agent] verify: done Deployment verified
   ## Deployed v1.7.0
   - process restart: no
   ```
5. Si querés confirmar en el server: `mods/deathmatch/logs/server.log` muestra
   el resource reiniciado y `/.deploy/current.json` queda con el tag nuevo.

No hay que tocar ninguna variable para un release de resources.

## Cambios de imagen (`docker/**`)

El agente vive en la imagen, así que este caso tiene dos fases:

1. Mergeá y creá el tag como siempre.
2. Esperá a que el workflow **docker** termine de publicar
   `ghcr.io/ferecece/speedrunlatam:latest`.
3. El job de deploy va a fallar con:
   ```text
   this release changed docker/** and requires a Reinstall
   ```
   Es lo esperado: no puede aplicar la imagen por archivos.
4. Hacé **Reinstall** del server en el panel. Es el único downtime grande.
5. Volvé a correr el deploy con `allow_image_current`:
   - Manual: workflow **cd-manual** → `action=deploy`, `tag=<tag>`,
     `allow_image_current=true`.
   - O poné `CD_IMAGE_CURRENT=true` justo para ese release y volvelo a `false`
     después.
6. Verificá que el contenedor arrancó con la imagen nueva y que
   `logs/update-agent.log` tiene el agente.

### Cuidado con `previous_tag`

El delta se calcula contra el tag anterior (`git describe`). Si ese tag fue
rollback o el server está instalado en otro tag, el delta queda vacío y el
agente cae al **template completo** (59 MB). Peor: si el agente de la imagen es
viejo, puede rechazar el template con `directory is not managed: mods`.

Para evitarlo, corré el workflow **server-template** a mano
(`workflow_dispatch`) con:

```text
tag:          v1.7.0
previous_tag: <el tag que tiene realmente el server>
```

Así el delta se calcula contra lo instalado y se aplica en caliente.

## Qué pasa dentro de un deploy en caliente

1. El job escribe `.deploy/download/update.json` y `.deploy/request.json` con
   `action=prepare`.
2. El agente:
   - valida tag, repo, SHA256 y rutas,
   - descarga y extrae el delta,
   - hace snapshot de DB, ghosts y autologin,
   - hace backup de los archivos que va a tocar,
   - calcula el plan y escribe `status.json`.
3. El job verifica que MTA lea la consola y ejecuta:
   - `stop` de resources eliminados,
   - `apply` de archivos,
   - `refresh` si hubo altas/bajas,
   - `start` de resources nuevos,
   - `restart` de los modificados (el gamemode al final).
4. El agente verifica el log y marca `done` o `failed`.
5. El job publica el resumen en Actions.

### Consola y locale

MTA lee la consola con `getwchar()`. Con locale `C`/POSIX, un solo byte
no-ASCII (por ejemplo la `ó` de un `say`) hace que `getwchar()` falle y deja
`stdin` roto: los comandos siguientes (`restart`, `stop`, `shutdown`) quedan
encolados hasta reiniciar el proceso.

La imagen fija `LANG=C.UTF-8` y el entrypoint lo fuerza si el panel manda
`LANG` vacío. Además, `scripts/deploy.py`:

- convierte los comandos de consola a ASCII, y
- hace un health check antes de aplicar: manda `say [deploy] console ok` y
  espera `CONSOLECHAT` en `server.log`. Si no aparece en ~20s, falla antes de
  tocar archivos.

El health check se saltea cuando el plan pide `power restart`, porque el
reinicio regenera la consola. Es **un** mensaje por deploy en caliente, no algo
periódico.

## Datos sensibles y rollback

Antes de cada deploy el agente guarda:

```text
/home/container/.deploy/backups/<fecha>-<tag>/sensitive/
/home/container/.deploy/backups/<fecha>-<tag>/code/
```

- `sensitive/`: `registry.db`, `internal.db`, `databases/`, ghosts, autologin,
  claves de identidad. Los `.db` se copian con `sqlite3 .backup` para que sean
  consistentes con MTA abierto.
- `code/`: copia de los archivos reemplazados + `journal.json`.

El rollback restaura **solo código**. La DB no se toca: restaurarla perdería
datos posteriores. Solo se restaura a mano si el update corrompió algo.

## Operaciones manuales

Preflight (no escribe ni reinicia nada):

```bash
PTERODACTYL_URL=... \
PTERODACTYL_API_KEY=... \
PTERODACTYL_SERVER_ID=... \
python3 scripts/deploy.py --action preflight --preflight-console
```

Rollback del último deploy:

```bash
python3 scripts/deploy.py --action rollback
```

Deploy manual de un tag:

```bash
python3 scripts/deploy.py --tag v1.7.0
```

Desde GitHub: workflow **cd-manual**, acciones `preflight`, `deploy` o
`rollback`.

## Pruebas en la única instancia

No hace falta una segunda instancia. Los tests automáticos usan directorios
temporales. Las pruebas reales se hacen con tags pre-release en el server real,
sin usuarios:

| Tag | Cambio | Valida |
| --- | --- | --- |
| `vX.Y.Z-rc1` | Comentario en `joinquit` | Hot de un resource normal |
| `vX.Y.Z-rc2` | Cambio inocuo en `resources/[gamemodes]/[race]/race` | Hot del gamemode `race` |
| `vX.Y.Z-rc3` | Comentario en `mtaserver.conf.template` | `power restart` y regeneración de config |
| `vX.Y.Z-rc4` | Error de sintaxis temporal en un resource | `failed` + rollback |
| `vX.Y.Z-rc5` | Alta/baja de un resource temporal | `stop` + `refresh` + `start` |
| `vX.Y.Z` | Release estable | Cierre |

En cada RC verificá:

- `docker inspect`: `StartedAt` no cambia en hot.
- PID de MTA: no cambia en hot.
- `mods/deathmatch/logs/server.log`: aparece el resource reiniciado.
- Conteos de `maptimes` y `accounts` contra el baseline.
- `.deploy/backups/<fecha>-<tag>/` tiene el snapshot.

## Tests automáticos

```bash
python3 -m unittest discover -s tests -t . -p 'test_*.py' -v
```

Cubren parser de paths, plan de resources, snapshot de datos, extracción segura
del tar, prepare/apply/verify/rollback, builder de releases y cliente de la API.

## Troubleshooting

- **`E_RECREATE_REQUIRED` / “this release changed docker/**”**: el release trae
  imagen nueva. Esperá el workflow `docker`, hacé Reinstall y reintentá con
  `allow_image_current`.
- **`E_BASE_MISMATCH`**: el server no está en el `previous_tag` del release.
  Reconstruí el release con `previous_tag=<tag instalado>` o hacé Reinstall.
- **`directory is not managed: mods`**: el agente viejo rechazó un template
  completo. Usá un delta con el `previous_tag` correcto, o actualizá la imagen.
- **`E_VERIFY`**: el resource no arrancó. Mirá `mods/deathmatch/logs/server.log`
  y `logs/update-agent.log`; después `rollback`.
- **“console input is not reaching MTA”**: la consola quedó sorda. Verificá que
  `LANG` sea UTF-8 y reiniciá el proceso. El deploy lo detecta en ~20s.
- **El deploy tarda ~5 minutos y falla**: son los dos timeouts de verificación
  (120s + rollback 120s). Con el health check actual no debería pasar: si la
  consola no responde, falla en ~20s.
- **El job de deploy no corre**: `CD_ENABLED` no está en `true` o faltan los
  secretos `PTERODACTYL_*`.
- **“update agent is not running”**: el contenedor es anterior al agente.
  Reinstall una vez.
- **No se puede escribir `.deploy`**: revisá permisos del volumen; el agente
  corre con el usuario del server (999).

## Cheat sheet

```text
Cambio de resource:
  merge → tag vX.Y.Z → push tag → listo (hot, sin downtime)

Cambio de gamemode o protegido:
  merge → tag → push tag → power restart automático (segundos)

Cambio en docker/**:
  merge → tag → push tag → esperar workflow docker → Reinstall
  → cd-manual deploy con allow_image_current=true

Solo settings.xml/acl.xml:
  merge → tag → el CD los lista y NO los aplica; aplicalos a mano

Server en un tag distinto al anterior:
  server-template (workflow_dispatch) con previous_tag=<tag instalado>
```
