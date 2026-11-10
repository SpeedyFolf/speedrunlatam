# Deploy

## Regla

- Un tag `v*` **solo publica assets**:
  `server-template.tar.gz`, `server-update.tar.gz` y `update.json`.
- El deploy es **manual**: GitHub → Actions → **cd-manual**.
- La imagen `ghcr.io/ferecece/speedrunlatam:latest` solo se reconstruye si el
  diff contra el tag anterior toca `docker/**`.

## Deploy normal (sin downtime)

1. Mergeá a `main`.
2. Creá y pusheá el tag:
   ```bash
   git checkout main && git pull
   git tag -a v1.6.4 -m "v1.6.4"
   git push origin v1.6.4
   ```
3. GitHub → Actions → **server-template** → esperá `success`.
4. GitHub → Actions → **cd-manual**:
   ```text
   action: deploy
   tag: v1.6.4
   ```
   El workflow exige que el tag esté sobre `main`.
5. Verificá:
   - `.deploy/status.json`: `phase: done`.
   - `mods/deathmatch/logs/server.log`: el resource se reinició.
   - `.deploy/current.json`: `tag` nuevo.

## Qué produce downtime

| Cambio | Qué hace el deploy |
| --- | --- |
| Resources o gamemode | Hot deploy: `refresh` y `restart` del resource que estaba corriendo |
| Binario, `x64/**`, `mtaserver.conf.template` | `power restart` corto |
| `docker/**` | **Reinstall** de imagen |
| `current.json.tag != previous_tag` | Full template + `power restart` (evitalo) |

## Antes de deployar

Mirá `.deploy/current.json` y compará `tag` con el `previous_tag` del release:

```text
current.json.tag == previous_tag  → delta normal (hot/restart)
current.json.tag != previous_tag  → full template + power restart
```

Si no coinciden:

- Reinstallá **latest stable** para alinear el tag instalado, o
- Recompilá los assets con:
  ```text
  Actions → server-template → workflow_dispatch
  tag: v1.6.4
  previous_tag: <current.json.tag>
  ```

`allow_image_current` **no** evita un full por `previous_tag` distinto. Solo
saltea el chequeo de `docker/**`.

Un full apply **no es un Reinstall**: aplica el template del server y reinicia
el proceso; la imagen no cambia.

## Si el release toca `docker/**`

1. Esperá el workflow **docker** y la imagen `latest`.
2. Reinstallá el server en el panel.
3. Deployá desde **cd-manual** con:
   ```text
   action: deploy
   tag: vX.Y.Z
   allow_image_current: true
   ```

## Settings y ACL

`mods/deathmatch/settings.xml` y `acl.xml` no se aplican por CD. Se editan a
mano en el server.

## Errores comunes

- **`E_RECREATE_REQUIRED`**: el release incluye `docker/**`. Reinstallá y
  repetí con `allow_image_current=true`.
- **`E_BASE_MISMATCH`**: el release no coincide con el tag instalado. Recompilá
  con `previous_tag=<current.json.tag>`.
- **`E_STATE` / “no state available to verify”**: hubo un full apply con
  reinicio. Evitá el mismatch de `previous_tag`.
- **La consola no responde**: revisá `LANG`/UTF-8 y reiniciá el proceso.

## Rollback

GitHub → Actions → **cd-manual** → `action=rollback`.
El rollback restaura código, no la base de datos.

## Variables opcionales

En GitHub → Settings → Actions → Variables:

- `CD_ANNOUNCE=1`: avisa por chat antes de recargar.
- `CD_DELAY_GAMEMODE`, `CD_DELAY_RESOURCE`, `CD_DELAY_RESTART`: esperas.

No hay deploy automático; no hace falta `CD_ENABLED`.

## Cheat sheet

```text
Resources:
  tag → server-template termina → cd-manual deploy

Docker:
  tag → esperar imagen → Reinstall → cd-manual allow_image_current=true

Tag instalado distinto del previous_tag:
  server-template con previous_tag=<instalado> → cd-manual deploy

Settings / ACL:
  editar a mano en el server
```
