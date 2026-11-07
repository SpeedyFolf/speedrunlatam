# Desarrollo local

## Requisitos

- Docker y Docker Compose.
- Git.
- Acceso al repo.

## Primer arranque

```bash
cp .env.example .env
docker compose pull
./scripts/console.sh
```

`console.sh` levanta el server y te deja escribir en la consola. No hace falta
correr `docker compose up` antes.

Si estás trabajando sobre la imagen:

```bash
docker compose build
./scripts/console.sh
```

## Comandos

| Quiero | Comando |
| --- | --- |
| Arrancar y escribir en la consola | `./scripts/console.sh` |
| Arrancar en segundo plano, sin consola | `docker compose up -d` |
| Entrar a la consola de un server ya corriendo | `./scripts/console.sh` |
| Ver logs en vivo | `docker compose logs -f server` |
| Apagar | `docker compose down` |

`docker compose up` sirve para ver logs, pero **no** deja escribir comandos.

## Consola del server

```bash
./scripts/console.sh
```

Si el server ya está corriendo, el script no lo reinicia: solo se adjunta.

Ejemplos:

```text
say hola
start editor
shutdown
```

Para salir de la consola sin apagar el server: `Ctrl-P` y después `Ctrl-Q`.
No uses `Ctrl-C`.

Fallback si `docker compose attach` no existe:

```bash
docker attach $(docker compose ps -q server)
```

Si el attach no toma input, recreá el contenedor:

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
