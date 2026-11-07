# Desarrollo local

## Requisitos

- Docker y Docker Compose.
- Git.
- Acceso al repo.

## Primer arranque

```bash
cp .env.example .env
docker compose pull
docker compose up
```

Si estás trabajando sobre la imagen:

```bash
docker compose build
docker compose up
```

## Consola del server

`docker compose up` no reenvía stdin, solo logs. Para escribir comandos hay que
adjuntarse al contenedor.

Con el script del repo:

```bash
./scripts/console.sh
```

Equivale a:

```bash
docker compose up -d --wait
docker compose attach server
```

Escribí el comando en la terminal:

```text
say hola
start editor
shutdown
```

Para salir de la consola sin apagar el server: `Ctrl-P` y después `Ctrl-Q`.

Si `docker compose attach` no existe en tu versión:

```bash
docker attach $(docker compose ps -q server)
```

Si el attach no toma input, recreá el contenedor para que tome `stdin_open` y
`tty`:

```bash
docker compose up -d --force-recreate
```

## Editar mapas y resources

Todo lo que va al server vive en:

```text
server/mods/deathmatch/resources/
```

Los mapas nuevos van dentro de la carpeta de categoría correspondiente, por ejemplo:

```text
server/mods/deathmatch/resources/[maps]/[R]/MiMapa/
```

Después de agregar un resource o mapa:

```bash
git add server/mods/deathmatch/resources
git commit -m "Add map ..."
git push
```

El CI publica la imagen y el template del release.

## Archivos que no se commitean

- DB de runtime.
- logs.
- resource-cache.
- keys.
- encryption_key.txt de autologin.
- ghosts.
- backups.
- mtaserver.conf generado.

`mtaserver.conf` se genera al arrancar desde `mtaserver.conf.template` usando las variables de entorno.

## Variables

`SERVER_NAME`, `SERVER_MAXPLAYERS`, `SERVER_FPSLIMIT`, `OWNER_EMAIL` y
`HTTP_DOWNLOAD_URL` se aplican al generar `mtaserver.conf`.

Para producción, `HTTP_DOWNLOAD_URL` puede apuntar al CDN. Para local, dejarlo vacío usa el HTTP interno.
