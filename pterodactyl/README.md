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
- HTTP: TCP
- ASE: UDP en `puerto de juego + 123` (ej. `22003` → `22126`)

El HTTP se configura con `SERVER_HTTP_PORT`. El puerto ASE lo deriva MTA
automáticamente y solo hay que asignar la allocation.

## Variables

- `SERVER_NAME`: nombre visible en el navegador de servidores.
- `SERVER_MAXPLAYERS`: cantidad máxima de jugadores. Default `70`.
- `SERVER_FPSLIMIT`: FPS máximo de los clientes. Default `300`, `0` usa el ajuste del cliente.
- `SERVER_HTTP_PORT`: puerto HTTP asignado.
- `OWNER_EMAIL`: contacto del servidor. Opcional.
- `HTTP_DOWNLOAD_URL`: URL externa de resources. Opcional.
