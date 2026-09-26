# Lua 5.1 toolchain for Goblinomics: busted + luacheck.
# Build:  docker build -t goblinomics-lua -f tools/docker/Dockerfile tools/docker
# Run:    tools/test.sh / tools/lint.sh
FROM alpine:3.20

RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 build-base git \
    && luarocks-5.1 install luacheck \
    && luarocks-5.1 install busted \
    && ln -sf /usr/bin/lua5.1 /usr/local/bin/lua \
    && apk del build-base

WORKDIR /work
