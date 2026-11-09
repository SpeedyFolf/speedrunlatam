# Contribuir

Guía para proponer mapas, features y correcciones.

- Desarrollo local con Docker: [development.md](development.md).
- Publicación y deploy: [deployment.md](deployment.md).

## Antes de empezar

Hay dos caminos. Elige el que corresponda.

### Solo vas a enviar un mapa (Windows, sin Docker)

No hace falta Docker ni WSL2. Necesitas San Andreas Online y su server para
Windows.

1. Instala San Andreas Online con el instalador del release:
   https://github.com/Dryxio/san-andreas-online/releases/latest
   Requiere Windows 10 o superior.
2. Descarga `MTA-Neon-Server-Windows-x64.zip` del mismo release y extráelo en
   `C:\sao-server`. Queda la carpeta `C:\sao-server\MTA-Neon-Server-Windows-x64`.
3. Descarga el template del último release:
   https://github.com/ferecece/speedrunlatam/releases/latest/download/server-template.tar.gz
   Guárdalo en `C:\sao-server` y extráelo:

   ```bat
   cd C:\sao-server
   mkdir template
   tar -xzf server-template.tar.gz -C template
   ```

   Ignora `mta-server64` y `x64`: son para Linux.

4. Borra `C:\sao-server\MTA-Neon-Server-Windows-x64\mods\deathmatch\resources`
   y copia ahí `C:\sao-server\template\mods\deathmatch\resources`.
   No mezcles las dos carpetas: hay resources con el mismo nombre y el server falla.
5. Arranca el editor:

   ```bat
   cd C:\sao-server\MTA-Neon-Server-Windows-x64
   "MTA Server64.exe" --config editor.conf
   ```

6. En el cliente de San Andreas Online agregá el server a mano con
   `127.0.0.1:22010` y conectate. La UI de SA:O no tiene pestaña LAN ni lista
   sola los servers locales: hay que ingresar IP y puerto manualmente.
7. Crea el mapa y usa **Test** para probarlo con el `race` del template.

El template solo aporta los resources del server. El cliente se instala aparte
con San Andreas Online. El template sale de cada tag `v*` y trae los mismos
resources que producción. Si necesitas un cambio que todavía no salió en un
release, usa el repo.

Usa siempre `MTA Server64.exe` y la misma build de cliente y server.

No hace falta saber Git: puedes adjuntar el `.zip` de tu mapa en el issue.

### Vas a tocar código, resources o el server

Requisitos:

- Docker y Docker Compose.
- Git.
- Opcional: editor de mapas de San Andreas Online.

```bash
cp .env.example .env
docker compose pull
docker compose up
```

Todo el contenido del server vive en:

```text
server/mods/deathmatch/resources/
```

Reglas:

- Los cambios permanentes van en el repo, no en el volumen de producción.
- No commitear runtime, DB, logs, cache, keys ni backups. `.gitignore` ya los excluye.
- Probar en local antes de abrir el PR.

## Mapas de carrera

### Tipos

| Carpeta | `racetype` | Contenido |
| --- | --- | --- |
| `[maps]/[R]` | `R` | Carreras normales. |
| `[maps]/[F2F]` | `F2F` | Cara a cara, con colisiones y mínimo de jugadores. |
| `[maps]/[SR]` | `SR` | Misiones de GTA portadas al modo race. |
| `[maps]/[RANDOM]` | `RANDOM` | Carrera con randomizer de vehículo en los checkpoints. |

### Crear el mapa

1. Abrir el editor de mapas.
2. Armar ruta, spawn, vehículos y checkpoints.
3. Exportar el resource.
4. Copiar la carpeta a `server/mods/deathmatch/resources/[maps]/[R]/NombreMapa/`.

El nombre de la carpeta es el nombre del resource. Sin espacios, sin acentos
y sin símbolos. Usar CamelCase: `ElegantKLK`, `EnCaravana`, `CaraACara`.

### meta.xml

```xml
<meta>
    <oop>true</oop>
    <info gamemodes="race" type="map" racetype="R" name="Mi Mapa" author="TuNombre" version="1.0.0" />
    <map src="MiMapa.map" dimension="0" />
    <settings>
        <setting name="#maxplayers" value="[ 128 ]" />
        <setting name="#minplayers" value="[ 0 ]" />
        <setting name="#ghostmode" value="[ &quot;true&quot; ]" />
        <setting name="#time" value="12:0" />
        <setting name="#weather" value="[ 0 ]" />
        <setting name="#duration" value="[ 1800 ]" />
        <setting name="#skins" value="[ &quot;random&quot; ]" />
    </settings>
    <script src="mapEditorScriptingExtension_s.lua" type="server" />
    <script src="mapEditorScriptingExtension_c.lua" type="client" validate="false" />
</meta>
```

- `name` es el nombre visible en el HUD y en las votaciones.
- `author` es obligatorio para el crédito.
- `racetype` debe coincidir con la carpeta.
- Los valores van entre corchetes. Los textos llevan `&quot;` porque el archivo es XML.

### Opciones del `meta.xml`

Esta parte es solo para mapas. Si no agregas una opción, queda en `false` y el
mapa funciona como siempre.

```xml
<settings>
    <setting name="#traffic" value="[ true ]" />
    <setting name="#wanted" value="[ true ]" />
    <setting name="#bikefall" value="[ true ]" />
    <setting name="#collisionmode" value="[ &quot;ghost&quot; ]" />
</settings>
```

#### Básicas

| Setting | Default | Qué hace |
| --- | --- | --- |
| `#duration` | — | Tiempo límite de la carrera, en segundos. |
| `#time` | — | Hora del mapa, formato `HH:MM`. |
| `#weather` | — | ID de clima. |
| `#skins` | — | Lista de skins. `random` elige al azar. |
| `#maxplayers` | — | Cantidad máxima de jugadores. |
| `#minplayers` | `0` | Jugadores mínimos para que el mapa se vote. |
| `#ghostmode` | — | `true`: los jugadores se atraviesan. |
| `#respawntime` | valor del server | Segundos para reaparecer. Si no lo pones, usa el default del server. |
| `#useLODs` | `true` | Carga LODs. Apagalo solo si el mapa pesa demasiado. |

#### Avanzadas

| Setting | Default | Qué hace |
| --- | --- | --- |
| `#timeafterfirstfinish` | valor del server | Tiempo extra cuando alguien termina. |
| `#countdownduration` | `3` | Duración de la cuenta regresiva, en segundos. |
| `#shufflespawns` | `false` | Ordena los spawnpoints al azar. |
| `#disableraceghosts` | `false` | Apaga los ghosts de la carrera. |
| `#allowonfoot` | `false` | Permite bajarse del vehículo y tocar checkpoints a pie. |

#### Funciones del mundo (opcionales)

Ninguna viene activa. Activa una por vez y prueba el mapa después de cada cambio.

**`#traffic`** (default `false`)

Activa peatones y vehículos manejados por el server. Suma carga al server y al
cliente: pruébalo con el mapa lleno antes de dejarlo. El tráfico siempre colisiona,
incluso con `#collisionmode "ghost"`.

**`#wanted`** (default `false`)

Activa nivel de búsqueda, policías y arrestos. Funciona sola o junto con
`#traffic`; con tráfico activo, los policías de patrulla se suman a la persecución.

**`#bikefall`** (default `false`)

Modo realista de moto:

- Si te caes o te bajas, quedas a pie. No reapareces en la moto.
- No hay respawn de vehículo y `/kill` queda deshabilitado.
- Si mueres, quedas fuera de la carrera y pasas a espectador.
- No hay daño ni ataques a pie entre jugadores. El tráfico y la policía sí dañan.
- Los checkpoints exigen vehículo, salvo que también actives `#allowonfoot`.

**`#collisionmode`** (default: usa `#ghostmode`)

Controla las colisiones entre jugadores:

- `"ghost"`: se atraviesan.
- `"solid"`: chocan.

**`#allowonfoot`** (default `false`)

`false`: el jugador no puede bajarse y los checkpoints solo cuentan en vehículo.
`true`: puede bajarse y los checkpoints cuentan a pie o en cualquier vehículo.
Es lo que permite terminar a pie con `#bikefall`.

**Cómo probarlas:** primero `#traffic`, después `#wanted`, al final `#bikefall`.
El mapa `In the Beginning`, en `[maps]/[SR]/[Misc]/InTheBeginning`, las usa todas
juntas como referencia.

### Checklist

- Creado con el editor del template, según la guía.
- Probado con **Test** del editor.
- `meta.xml` con `type="map"`, `gamemodes="race"` y el `racetype` de la carpeta.
- Solo los archivos necesarios: `.map`, `meta.xml` y scripts del editor.

No hace falta que la ruta sea perfecta ni que todos los checkpoints se vean.
Se revisa en el issue o en el PR.

### Probar

En el editor, **Test** carga el mapa con el gamemode `race` del template. Es la
forma más rápida de verificar que el mapa carga y se puede jugar.

Si pruebas con el server completo:

```bash
docker compose up
```

En el juego, con cuenta admin: `/changemap NombreMapa`. La lista de mapas
detectados se ve con `/maps`.

Si el mapa no aparece, revisar que `meta.xml` tenga `type="map"` y
`gamemodes="race"`.

## Editor y race custom

El server no usa el editor ni el gamemode `race` originales. El template y el
repo traen la misma versión custom. Tiene cambios que afectan a los mapas:

- El editor custom guarda `customMapEditorScriptingExtension_s.lua`. El editor
  original guarda `mapEditorScriptingExtension_s.lua`. El custom trae fixes de
  LODs, visibilidad a distancia y remoción de objetos del mundo.
- `race` soporta atributos extra en checkpoints: `blipsize`, `extracolshapesize`
  y `height`.
- El HUD, los toptimes y los ghosts son propios del server.

Recomendamos exportar con el editor del template. Si usas otro, avísalo en el issue.

Guía extendida en inglés, de donde salen estos resources:
https://gitlab.com/The123robot/robot-mta-server/-/blob/develop/Readme.md

## Features y resources

### Dónde va cada cosa

| Carpeta | Uso |
| --- | --- |
| `[gameplay]` | Mecánicas: HUD, daño, armas, pickups. |
| `[managers]` | Servicios globales: votaciones, chat, mapas, autologin. |
| `[web]` | Panel web y estadísticas. |
| `[gamemodes]/[race]/[addons]` | Extensiones del modo race. |
| `native-*` | Features nativas con tests propios. |

### meta.xml mínimo

```xml
<meta>
    <oop>true</oop>
    <info author="TuNombre" name="mi_feature" description="Qué hace" version="1.0.0" type="script" />
    <script src="server.lua" type="server" />
    <script src="client.lua" type="client" />
</meta>
```

Reglas:

- Un archivo por responsabilidad. `shared/` solo para lógica sin APIs de MTA.
- Configuración en `<settings>` del `meta.xml`, no hardcodeada en el código.
- Sin credenciales, IPs ni rutas absolutas.
- Mensajes al jugador en español.
- `outputDebugString` para logs de debug, sin ruido en producción.

### Registrar el resource

Un resource nuevo no arranca solo. Agregar la línea en
`server/mods/deathmatch/mtaserver.conf.template`:

```xml
<resource src="mi_feature" startup="1" protected="0" />
```

Sin esa línea el resource nunca se inicia en un server limpio.

### ACL

Si el resource necesita permisos, documentar cuáles y por qué en el PR.
No pedir derechos de admin completos.

### Estilo y rendimiento

- Nada de trabajo pesado en `onClientRender`. Usar timers y eventos.
- Un timer por sistema, no uno por jugador.
- Limpiar timers, binds y elementos en `onClientResourceStop`.

### Tests

Si el resource tiene lógica pura, agregar tests en `tests/`. El modo
speedrun incluye un runner Lua sobre Node:

```bash
cd "server/mods/deathmatch/resources/[gamemodes]/[speedrun]/speedrun/tests"
npm ci
npm test
```

Los tests no deben llamar APIs de MTA.

## Flujo de trabajo

### Ramas

| Prefijo | Uso |
| --- | --- |
| `feat/` | Feature nueva. |
| `fix/` | Corrección. |
| `docs/` | Documentación. |
| `maps/` | Mapas. |

Ejemplo: `feat/map-voting-timeout`.

### Commits

Formato convencional: `tipo(alcance): descripción`.

```text
feat(scoreboard): restyle Tab scoreboard with Neon theme
fix(race): respect ghostmode when collisionmode is absent
docs(contributing): add map and feature guide
```

### Pull request

1. Abrir PR contra `main`.
2. Completar la plantilla.
3. Adjuntar captura o video para cambios visuales.
4. Para mapas, adjuntar captura del recorrido.
5. Esperar revisión.

### Releases

Mergear a `main` no actualiza el server de producción. Solo reconstruye la
imagen `latest`. El deploy real es:

1. Crear y pushear un tag `v*`.
2. Esperar el release en GitHub Actions.
3. Reinstall en Pterodactyl.

Más detalles en [deployment.md](deployment.md).

## Speedrun

El modo speedrun y sus misiones están en desarrollo cerrado. No se aceptan
misiones externas por ahora.
