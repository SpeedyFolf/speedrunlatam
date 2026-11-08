# Speedrun LATAM

Egg para importar en cualquier instancia de Pterodactyl.

Archivo:

```text
egg-speedrun-latam.json
```

El egg usa la imagen pública:

```text
ghcr.io/ferecece/speedrunlatam:latest
```

El instalador descarga el template desde:

```text
https://github.com/ferecece/speedrunlatam/releases/latest/download/server-template.tar.gz
```

El servidor necesita tres allocations:

- juego: UDP/TCP
- descargas: TCP, servido por nginx
- ASE: UDP en `puerto de juego + 123` (ej. `22003` → `22126`)

Las descargas se configuran con `SERVER_DOWNLOAD_PORT`. El HTTP interno de MTA
queda en `22007` y no se asigna. El puerto ASE lo deriva MTA automáticamente y
solo hay que asignar la allocation.

## Variables

- `SERVER_NAME`: nombre visible en el navegador de servidores.
- `SERVER_MAXPLAYERS`: cantidad máxima de jugadores. Default `70`.
- `SERVER_FPSLIMIT`: FPS máximo de los clientes. Default `300`, `0` usa el ajuste del cliente.
- `SERVER_DOWNLOAD_PORT`: puerto público de descargas (nginx).
- `OWNER_EMAIL`: contacto del servidor. Opcional.
- `HTTP_DOWNLOAD_URL`: URL pública de descargas. Debe apuntar al puerto de descargas.
- `DEPLOY_AGENT`: `1` arranca el agente de actualización en caliente; `0` lo apaga. Default `1`.
- `DEPLOY_ALLOWED_REPO`: repo del que se aceptan releases. Default `ferecece/speedrunlatam`.
- `DEPLOY_BACKUP_KEEP`: snapshots de DB/ghosts/autologin y backups de código a conservar. Default `3`.
- `DEPLOY_MAX_ASSET_MB`: tamaño máximo del bundle de actualización. Default `160`.

## Actualizaciones en caliente

La imagen incluye `deploy_agent`, que corre en background y no hace nada hasta
que el panel escribe un pedido en `.deploy/request.json`. El agente no abre
puertos nuevos y no manda comandos a la consola: solo descarga, valida, hace
backup y aplica archivos. Los comandos MTA los manda GitHub Actions por la API
Client del panel.

Para usar el CD en una instancia propia:

1. Crear un usuario dedicado, agregarlo como subuser del server y crear una API
   key Client con `control.console`, `control.restart`, `file.read-content`,
   `file.create` y `file.update`.
2. Cargar `PTERODACTYL_URL`, `PTERODACTYL_API_KEY` y `PTERODACTYL_SERVER_ID`
   como secretos del repo de GitHub.
3. Poner `CD_ENABLED=true` como variable del repo.
4. Hacer un Reinstall inicial para que la imagen incluya el agente.

Los detalles están en `docs/cd.md` del repositorio.

El agente guarda los datos sensibles antes de cada deploy en
`.deploy/backups/<fecha>-<tag>/sensitive/`: `registry.db`, `internal.db`,
`databases/`, `race_ghost/ghosts/`, `ghosts_server/ghosts/` y la clave de
autologin.
