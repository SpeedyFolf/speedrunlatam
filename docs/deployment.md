# Deploy en Pterodactyl

## Importar egg

Panel de Pterodactyl:

1. Nests.
2. Import Egg.
3. Seleccionar `pterodactyl/egg-speedrun-latam.json`.

## Crear servidor

- Imagen: `ghcr.io/ferecece/speedrunlatam:latest`
- Puerto de juego: allocation UDP/TCP.
- Puerto HTTP: allocation TCP.
- Variable `SERVER_HTTP_PORT`: mismo puerto HTTP asignado.

El startup es:

```text
./mta-server64 --port {{SERVER_PORT}} --httpport {{SERVER_HTTP_PORT}} -n
```

## Instalación

El install script:

1. Descarga `server-template.tar.gz` desde el último release.
2. Hace backup si ya existe un server.
3. Sincroniza archivos administrados.
4. Conserva DB, cuentas, toptimes, ghosts, admins, keys y autologin.

## Actualizar

1. Crear y pushear un tag `v*`.
2. Esperar que GitHub Actions termine.
3. En Pterodactyl, Reinstall.
4. Confirmar en consola que el server arrancó.

Los backups quedan en:

```text
/home/container/backups/pre-update-<fecha>/
```

## Repositorio y GHCR públicos

Para que cualquier Pterodactyl pueda instalar sin credenciales:

1. GitHub repo Settings, cambiar la visibilidad del repositorio a Public.
2. Packages, `speedrunlatam`, Package settings, cambiar la visibilidad a Public.

El install script descarga `server-template.tar.gz` desde el release. Si el repo es privado, ese asset también es privado. En ese caso se puede configurar `GITHUB_TOKEN` en el egg, pero la imagen de GHCR sigue necesitando autenticación en el nodo.

Para instalar en cualquier instancia sin configuración extra, el repo y el paquete deben ser públicos.

## ACL

El template no incluye cuentas de administrador. Después del primer arranque hay que agregar el admin desde la consola de MTA o el panel.

## Persistencia

No editar el volumen de producción para cambios permanentes. Los cambios permanentes van en `server/` y se publican con un tag.
