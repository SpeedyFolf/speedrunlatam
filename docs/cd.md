# Continuous deployment (CD)

Este documento describe el deploy en caliente de Speedrun LATAM. El objetivo es
que un tag `v*` actualice los resources sin reiniciar la instancia de Pterodactyl
y sin correr un Reinstall completo.

## Resumen

```text
tag v*
  → workflow server-template
      → server-template.tar.gz   (instalación completa)
      → server-update.tar.gz     (delta desde el tag anterior)
      → update.json              (manifest)
  → job deploy (si CD_ENABLED=true)
      → API Client de Pterodactyl
      → .deploy/request.json
      → agente en el contenedor
      → panel envía stop/refresh/start/restart a MTA
```

El agente **no manda comandos a la consola**. Solo descarga, valida, hace backup
y aplica archivos. Los comandos MTA los manda GitHub Actions por la API del panel.

## Qué necesita GitHub Actions

Solo tres secretos:

| Secreto | Ejemplo | Descripción |
| --- | --- | --- |
| `PTERODACTYL_URL` | `https://panel.ejemplo.com` | URL pública del panel |
| `PTERODACTYL_API_KEY` | `ptlc_...` | API key Client de un usuario con acceso al server |
| `PTERODACTYL_SERVER_ID` | `abc12345` | Short UUID del server |

No se necesita acceso SSH/root al nodo, la ruta del volumen, el puerto interno
del daemon ni los puertos de juego. El panel se encarga de acceder al servidor.

### Permisos de la API key

Crear un usuario dedicado, agregarlo como subuser del server y crear la API key
con estos permisos:

- `control.console` → `say`, `stop`, `refresh`, `start`, `restart`
- `control.restart` → `power restart`
- `file.read-content` → leer `.deploy/status.json` (y `file.read` si querés listar archivos)
- `file.create` y `file.update` → escribir `.deploy/request.json` y el manifest
- opcional `settings.reinstall` → permitir `--allow-reinstall`

La API key y los permisos del subuser se combinan: ambos deben permitir la
operación.

## Variables de repositorio

En GitHub → Settings → Secrets and variables → Actions → Variables:

| Variable | Default | Uso |
| --- | --- | --- |
| `CD_ENABLED` | `false` | Habilita el job de deploy en tags |
| `CD_ANNOUNCE` | `0` | `1` manda un `say` y espera antes de recargar |
| `CD_DELAY_GAMEMODE` | `30` | Segundos si cambia un gamemode |
| `CD_DELAY_RESOURCE` | `10` | Segundos si solo cambian resources normales |
| `CD_DELAY_RESTART` | `30` | Segundos antes de un `power restart` |
| `CD_IMAGE_CURRENT` | `false` | `true` solo para el primer release posterior a un Reinstall: el diff incluye `docker/**` pero la imagen ya está actualizada |

Mientras no haya usuarios, dejar `CD_ANNOUNCE=0`. Cuando haya jugadores,
poner `1` y ajustar los delays.

## Primer rollout

El agente vive en la imagen. La primera vez hace falta **un Reinstall**:

1. Mergear los cambios del agente a `main`.
2. Esperar a que el workflow `docker` publique `ghcr.io/ferecece/speedrunlatam:latest`.
3. Reinstall del server en Pterodactyl. Es el único downtime grande.
4. Verificar en el panel que existe `/home/container/.deploy` y que
   `logs/update-agent.log` tiene el agente.
5. Crear los secretos y poner `CD_ENABLED=true`.
6. Crear los tags de prueba (`-rc1`, `-rc2`, …) antes que un tag estable. Así
   el primer RC tiene como `previous_tag` el último release estable instalado y
   se aplica como delta; si primero creás un estable, el RC puede necesitar el
   template completo.
7. El primer release posterior al Reinstall incluye en su diff los cambios de
   `docker/**` del rollout. Como la imagen ya se instaló, poné
   `CD_IMAGE_CURRENT=true` para ese tag. Después volvelo a `false`: los releases
   siguientes ya diffean contra el RC y no ven `docker/**`.

Después de eso, los cambios de resources se aplican en caliente.

## Flujo de un deploy en caliente

1. El workflow construye los assets y publica el release.
2. El job de deploy escribe `.deploy/download/update.json` y
   `.deploy/request.json` con `action=prepare`.
3. El agente:
   - valida tag, repo, SHA256 y rutas del tar,
   - descarga/extrae el delta,
   - hace un snapshot de DB, ghosts y autologin,
   - hace backup de los archivos que va a tocar,
   - calcula el plan de resources y escribe `status.json`.
4. El job verifica que MTA esté leyendo la consola y ejecuta:
   - `stop` de resources eliminados,
   - `apply` de archivos,
   - `refresh` si hubo altas/bajas,
   - `start` de resources nuevos,
   - `restart` de resources modificados, con el gamemode al final.
5. El agente verifica `mods/deathmatch/logs/server.log` y marca `done` o `failed`.
6. El job publica un resumen en GitHub Actions.

### Consola y locale

MTA lee la consola con `getwchar()`. Si el proceso corre con el locale `C`/POSIX
(contenedor sin `LANG`), un solo byte no-ASCII en un comando —por ejemplo la
`ó` de un `say`— hace que `getwchar()` falle con `EILSEQ` y deja `stdin` roto:
los comandos siguientes (`restart`, `stop`, `shutdown`) quedan encolados y no
se ejecutan hasta reiniciar el proceso.

La imagen fija `LANG=C.UTF-8` y el entrypoint lo fuerza si el panel manda
`LANG` vacío. Además, `scripts/deploy.py`:

- convierte todos los comandos de consola a ASCII (`console_command`), y
- hace un health check antes de aplicar: manda `say [deploy] console ok` y
  espera ver `CONSOLECHAT` en `server.log`. Si no aparece en 20s, falla antes
  de tocar archivos, en vez de esperar el timeout de verificación y el rollback.

El health check se saltea cuando el plan pide `requires_process_restart`,
porque el reinicio regenera la consola.

Si el plan pide `requires_process_restart` (cambió `mta-server64`, `x64/**` o
`mtaserver.conf.template`), el job hace `power restart`. El contenedor no se
recrea y el entrypoint regenera `mtaserver.conf`. El downtime es de segundos.

Si el plan pide `requires_container_recreate` (cambió `docker/**`), el job falla
con instrucción de Reinstall. También se puede correr con `--allow-reinstall`
desde el workflow manual si se acepta el downtime.

## Datos sensibles

El agente guarda un snapshot antes de cada deploy en:

```text
/home/container/.deploy/backups/<fecha>-<tag>/sensitive/
```

Incluye:

- `registry.db` → `maptimes` (toptimes), stats, leaderboards.
- `internal.db` → `accounts`, `userdata`, `serialusage` (autologin).
- `databases/` → por ejemplo `tuning.db`.
- `race_ghost/ghosts/` → ghosts locales del resource.
- `ghosts_server/ghosts/` → ghosts del server Python.
- `autologin/encryption_key.txt`.
- `server-id.keys` y `neon-identity.keys`.

Los `.db` se copian con `sqlite3 .backup`, no con `cp`, para que sean
consistentes mientras MTA los tiene abiertos. Los ghosts y la DB se guardan
juntos porque un toptime sin su ghost (o al revés) queda desincronizado.

El código que se reemplaza se guarda en `backups/<fecha>-<tag>/code/` con un
`journal.json`. El rollback automático restaura solo código, **no** la DB: una
restauración de DB perdería los tiempos/cuentas posteriores. La DB se restaura
a mano solo si el update corrompió datos.

## Operaciones manuales

Preflight (no modifica archivos ni reinicia):

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

Desde GitHub: workflow `cd-manual`, acción `rollback`.

Deploy manual de un tag:

```bash
python3 scripts/deploy.py --tag v1.7.0
```

## Pruebas en la única instancia

No hace falta una segunda instancia. Los tests automáticos corren en GitHub con
directorios temporales. Las pruebas reales se hacen con tags pre-release en el
server real, sin usuarios:

| Tag | Cambio | Valida |
| --- | --- | --- |
| `vX.Y.Z-rc1` | Comentario en `joinquit` | Hot de un resource normal |
| `vX.Y.Z-rc2` | Cambio inocuo en `resources/[gamemodes]/[race]/race` | Hot del gamemode `race`, que es el que carga por defecto |
| `vX.Y.Z-rc3` | Comentario en `mtaserver.conf.template` | `power restart` y regeneración de config |
| `vX.Y.Z-rc4` | Error de sintaxis temporal en un resource | `failed` + rollback |
| `vX.Y.Z-rc5` | Alta/baja de un resource temporal | `stop` + `refresh` + `start` |
| `vX.Y.Z` | Release estable | Cierre |

En cada RC verificar:

- `docker inspect` del contenedor: `StartedAt` no cambia en hot.
- PID de MTA: no cambia en hot.
- `mods/deathmatch/logs/server.log`: aparece el resource reiniciado.
- Conteos de `maptimes` y `accounts` contra el baseline.
- `.deploy/backups/<fecha>-<tag>/` contiene el snapshot.

## Tests automáticos

```bash
python3 -m unittest discover -s tests -t . -p 'test_*.py' -v
```

Cubren el parser de paths, el plan de resources, el snapshot de datos, la
extracción segura del tar, el flujo prepare/apply/verify/rollback, el builder de
releases y el cliente de la API.

## Troubleshooting

- **`E_RECREATE_REQUIRED`**: el release cambió `docker/**`. Hacer Reinstall.
- **`E_BASE_MISMATCH`**: el server está en un tag que no es el `previous_tag`
  del release. El agente intenta full template si existe; si no, Reinstall.
- **`E_VERIFY`**: el resource no arrancó. Mirar `mods/deathmatch/logs/server.log` y
  `logs/update-agent.log`; usar rollback.
- **La consola no responde**: el proceso quedó con `stdin` roto (locale `C` y
  un comando no-ASCII). Verificar que `LANG` sea UTF-8 y reiniciar el proceso.
  El deploy ahora lo detecta con el health check antes de aplicar.
- **El job no corre**: `CD_ENABLED` no está en `true` o faltan secretos.
- **El agente no está**: el contenedor es anterior al rollout; Reinstall una vez.
- **No se puede escribir `.deploy`**: revisar permisos del volumen; el agente
  corre con el usuario del server (999).
