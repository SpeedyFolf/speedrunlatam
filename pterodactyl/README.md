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

El servidor necesita dos allocations:

- juego: UDP/TCP
- HTTP: TCP

El HTTP se configura con `SERVER_HTTP_PORT`.
