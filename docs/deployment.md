# Deploy en Pterodactyl

## Importar egg

Panel de Pterodactyl:

1. Nests.
2. Import Egg.
3. Seleccionar `pterodactyl/egg-speedrun-latam.json`.

## Crear servidor

- Imagen: `ghcr.io/ferecece/speedrunlatam:latest`
- Puerto de juego: allocation UDP/TCP.
- Puerto de descargas: allocation TCP. Lo sirve nginx.
- ASE: allocation UDP en `puerto de juego + 123` (ej. `22003` → `22126`).
- Variable `SERVER_DOWNLOAD_PORT`: mismo puerto de descargas asignado.
- Variables opcionales: `SERVER_MAXPLAYERS` (default `70`) y `SERVER_FPSLIMIT`
  (default `300`, `0` usa el ajuste del cliente).

El HTTP interno de MTA queda en `22007` y no debe asignarse como allocation.
Se usa solo para webadmin y web resources.

Pterodactyl no crea allocations automáticamente. Sin la allocation ASE, el server
funciona pero no aparece en el server browser.

El startup es:

```text
./mta-server64 --port {{SERVER_PORT}} --httpport 22007 -n
```

`HTTP_DOWNLOAD_URL` debe apuntar al puerto de descargas, por ejemplo la URL
pública configurada.

## Instalación

El install script:

1. Descarga `server-template.tar.gz` desde el último release.
2. Hace backup si ya existe un server.
3. Sincroniza archivos administrados.
4. Conserva DB, cuentas, toptimes, ghosts, admins, keys, autologin y el
   estado del agente en `.deploy/`.

## Actualizar

El camino normal es en caliente. Al pushear un tag `v*`:

1. GitHub Actions construye la imagen, `server-template.tar.gz`,
   `server-update.tar.gz` y `update.json`.
2. Si `CD_ENABLED=true`, el job de deploy llama a la API del panel.
3. El agente del contenedor valida y aplica el delta, y el panel recarga los
   resources con `stop`/`refresh`/`start`/`restart`.
4. El job verifica y publica el resumen.

No hace falta Reinstall para cambios de resources. Tampoco para cambios de
`mta-server64`, `x64/**` o `mtaserver.conf.template`: en esos casos el job hace
un `power restart` corto y el entrypoint regenera `mtaserver.conf`.

Sí hace falta Reinstall cuando cambia `docker/**` (imagen, entrypoint, servidor
de descargas, ghosts_server) o en el primer rollout del agente. El job falla con
`E_RECREATE_REQUIRED` en ese caso.

La configuración de la API key, secretos, variables y rollback está en
[cd.md](cd.md).

### Primera actualización con agente

1. Mergear el agente a `main` y esperar la imagen `latest`.
2. Reinstall una vez para que el contenedor tenga `/opt/deploy_agent`.
3. Crear los secretos `PTERODACTYL_URL`, `PTERODACTYL_API_KEY` y
   `PTERODACTYL_SERVER_ID`.
4. Poner `CD_ENABLED=true`.
5. Probar con un tag pre-release (`-rc1`) antes del estable.

### Backups

El install script sigue dejando el backup completo de un Reinstall en:

```text
/home/container/backups/pre-update-<fecha>/
```

El agente de hot update deja snapshots en:

```text
/home/container/.deploy/backups/<fecha>-<tag>/
```

Los snapshots incluyen `registry.db` (toptimes), `internal.db` (cuentas),
`databases/`, los dos directorios de ghosts y la clave de autologin.

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
