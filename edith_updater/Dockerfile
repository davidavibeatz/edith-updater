FROM ghcr.io/home-assistant/base:3.21

ARG BUILD_VERSION
ARG BUILD_ARCH
LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}"

RUN apk add --no-cache curl jq unzip

COPY run.sh /run.sh
COPY update.sh /update.sh
RUN chmod a+x /run.sh /update.sh

CMD ["/run.sh"]
