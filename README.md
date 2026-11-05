# Speedrun LATAM

Repo del servidor **Speedrun LATAM**. Motor: San Andreas Online. Incluye el runtime Docker, los resources, los mapas y el egg de Pterodactyl.

La imagen del runtime se publica automáticamente en:

```text
ghcr.io/ferecece/speedrunlatam:latest
```

## Estructura

```text
docker/              Imagen runtime, entrypoint e instalador
server/              Template del volumen del servidor
pterodactyl/         Egg de Speedrun LATAM
docs/                Desarrollo y despliegue
compose.yaml         Entorno local
```

La imagen no contiene resources ni mapas. Los datos del servidor viven en `server/` o en el volumen de Pterodactyl.

## Desarrollo local

```bash
cp .env.example .env
docker compose up
```

El servidor queda en:

- juego: `22003/udp` y `22003/tcp`
- HTTP: `22005/tcp`

Los archivos que edites están en `server/`. Los mapas y resources nuevos van en:

```text
server/mods/deathmatch/resources/
```

Los archivos de runtime, DB, logs, cache y secretos están en `.gitignore`.

## Deploy en Pterodactyl

1. Importar `pterodactyl/egg-speedrun-latam.json`.
2. Crear el servidor con la imagen `ghcr.io/ferecece/speedrunlatam:latest`.
3. Asignar tres allocations: juego, HTTP y ASE (`puerto de juego + 123`).
4. Configurar `SERVER_HTTP_PORT`, `SERVER_NAME`, `OWNER_EMAIL` y `HTTP_DOWNLOAD_URL`.
5. Instalar o reinstalar el server.

El instalador descarga el template desde GitHub Releases y conserva:

- `registry.db`
- `internal.db`
- `settings.xml`
- `acl.xml`
- `banlist.xml`
- `server-id.keys`
- `neon-identity.keys`
- `databases/`
- `autologin/encryption_key.txt`
- `ghosts_server/ghosts/`

## Actualizaciones

Cada tag `v*`:

1. GitHub Actions construye la imagen.
2. GitHub Actions publica `server-template.tar.gz` en el release.
3. En Pterodactyl, Reinstall ejecuta el instalador.
4. El instalador hace backup y sincroniza los archivos administrados.
5. Las cuentas, toptimes y ghosts quedan intactos.

No se debe editar el volumen de producción para cambios permanentes. Los cambios van en `server/` y se publican con un tag.

## Primer uso

El ACL se publica sin cuentas de administrador. Después del primer arranque hay que agregar el admin desde la consola o el panel de MTA.
