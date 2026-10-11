ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=28.5.0.7
ARG DEBIAN_VERSION=trixie-20261005-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV MIX_ENV=prod
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
RUN mix deps.compile

COPY lib lib
RUN mix release

FROM debian:${DEBIAN_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libncurses6 libstdc++6 openssl tzdata \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
  PORT=4000 \
  RELEASE_DISTRIBUTION=none \
  RELEASE_TMP=/tmp

WORKDIR /app
COPY --from=build /app/_build/prod/rel/spickzettel ./

USER nobody
EXPOSE 4000

CMD ["/app/bin/spickzettel", "start"]
