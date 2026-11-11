FROM docker.io/hexpm/elixir:1.20.5-erlang-29.1.2-debian-trixie-20261104

RUN apt-get update \
    && apt-get install -y --no-install-recommends git nodejs npm \
    && rm -rf /var/lib/apt/lists/*
