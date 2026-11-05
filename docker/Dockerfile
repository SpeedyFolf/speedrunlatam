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
RUN chmod +x /entrypoint.sh /opt/install-server.sh

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

STOPSIGNAL SIGTERM
CMD ["/bin/bash", "/entrypoint.sh"]
