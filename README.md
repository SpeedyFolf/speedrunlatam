# Speedrun LATAM

Repo del servidor **Speedrun LATAM**. Motor: San Andreas Online. Incluye el runtime Docker, los resources, los mapas y el egg de Pterodactyl.

La imagen del runtime se publica automáticamente en:

```text
ghcr.io/ferecece/speedrunlatam:latest
```

## Estructura

```text
docker/              Imagen runtime, entrypoint, instalador y agente de deploy
server/              Template del volumen del servidor
pterodactyl/         Egg de Speedrun LATAM
docs/                Desarrollo y despliegue
compose.yaml         Entorno local
```

La imagen no contiene resources ni mapas. Los datos del servidor viven en `server/` o en el volumen de Pterodactyl.

## Desarrollo local

```bash
cp .env.example .env
./scripts/console.sh
```

El servidor queda en:

- juego: `22003/udp` y `22003/tcp`
- descargas de resources: `22005/tcp` (nginx)

El HTTP interno de MTA usa `22007` y no se publica.

Los archivos que edites están en `server/`. Los mapas y resources nuevos van en:

```text
server/mods/deathmatch/resources/
```

Los archivos de runtime, DB, logs, cache y secretos están en `.gitignore`.

## Deploy en Pterodactyl

1. Importar `pterodactyl/egg-speedrun-latam.json`.
2. Crear el servidor con la imagen `ghcr.io/ferecece/speedrunlatam:latest`.
3. Asignar tres allocations: juego, descargas (nginx) y ASE (`puerto de juego + 123`).
4. Configurar `SERVER_DOWNLOAD_PORT`, `SERVER_NAME`, `SERVER_MAXPLAYERS`, `SERVER_FPSLIMIT`, `OWNER_EMAIL` y `HTTP_DOWNLOAD_URL`.
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
- `race_ghost/ghosts/`
- `ghosts_server/ghosts/`
- `.deploy/` (estado y backups del agente)

## Actualizaciones

Un tag `v*` solo publica los assets. El deploy es manual desde GitHub →
Actions → **cd-manual** (`action=deploy`, `tag=<tag>`).

- Resources/gamemodes: hot/restart sin reiniciar la instancia.
- Binario o `mtaserver.conf.template`: `power restart` corto.
- `docker/**`: Reinstall de imagen.
- Si el tag instalado no coincide con el `previous_tag` del release, el agente
  hace full template + `power restart`; evitá ese caso.

Guía completa: [docs/cd.md](docs/cd.md).

No se debe editar el volumen de producción para cambios permanentes. Los cambios van en `server/` y se publican con un tag. La guía de CD está en
[docs/cd.md](docs/cd.md).

## Primer uso

El ACL se publica sin cuentas de administrador. Después del primer arranque hay que agregar el admin desde la consola o el panel de MTA.
