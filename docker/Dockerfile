FROM debian:trixie-slim

LABEL org.opencontainers.image.title="Speedrun LATAM" \
      org.opencontainers.image.description="Runtime image for Speedrun LATAM (San Andreas Online engine)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    fontconfig \
    git \
    iproute2 \
    libncursesw6 \
    libstdc++6 \
    lsof \
    nginx-light \
    openssl \
    python3 \
    python3-pip \
    python3-venv \
    rsync \
    sqlite3 \
    tar \
    tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -d /home/container -m container

COPY ghosts_server /opt/ghosts_server
RUN python3 -m venv /opt/ghosts-venv \
    && /opt/ghosts-venv/bin/pip install --no-cache-dir -r /opt/ghosts_server/requirements.txt

COPY entrypoint.sh /entrypoint.sh
COPY install-server.sh /opt/install-server.sh
COPY sync-excludes.txt /opt/sync-excludes.txt
COPY deploy_agent /opt/deploy_agent
COPY nginx/nginx.conf.template /opt/nginx/nginx.conf.template
RUN chmod +x /entrypoint.sh /opt/install-server.sh

# Wings runs the server process with the configured pterodactyl user (999:988).
# The installation container runs as root, which is required to read Wings'
# 0700 installation directory mounted at /mnt/install. Do not set USER here.
ENV USER=container HOME=/home/container
WORKDIR /home/container

STOPSIGNAL SIGTERM
CMD ["/bin/bash", "/entrypoint.sh"]
