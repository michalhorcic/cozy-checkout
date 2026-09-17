# Find eligible builder images on Docker Hub:
# https://hub.docker.com/r/hexpm/elixir/tags

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29
ARG ALPINE_VERSION=3.22

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} AS build

# install build dependencies
RUN apk add --no-cache build-base git python3

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/config.exs config/prod.exs config/
COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=build --chown=nobody:nobody _build/prod/rel/cozy_checkout ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes,
# consider adding an init process via tini:
# https://github.com/krallin/tini
CMD ["/app/bin/server"]
