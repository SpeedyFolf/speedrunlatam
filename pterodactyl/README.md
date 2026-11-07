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
