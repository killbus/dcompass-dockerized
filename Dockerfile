# To set multiarch build for Docker hub automated build.
FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG VERSION
ARG DCOMPASS_TARGET_COMMITISH
ARG GEOIP2_VERSION
ARG PRERELEASE

WORKDIR /go
RUN apk add curl jq --no-cache

RUN set -eux; \
    \
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then architecture="x86_64-unknown-linux-musl"; fi; \
    if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then architecture="aarch64-unknown-linux-musl"; fi; \
    if [ "${TARGETPLATFORM}" = "linux/arm/v7" ]; then architecture="armv7-unknown-linux-musleabihf"; fi; \
    \
    REPO_API="https://api.github.com/repos/LEXUGE/dcompass/releases"; \
    VERSION=${VERSION:-latest}; \
    GEOIP2_VERSION=${GEOIP2_VERSION:-cn}; \
    [ "$VERSION" != "latest" ] && VERSION="v$(echo ${VERSION##v})"; \
    PRERELEASE=${PRERELEASE:-0}; \
    tag_name_keyword="${architecture}-${GEOIP2_VERSION}"; \
    \
    if [ "$VERSION" != "latest" ]; then download_url=$(curl -L $REPO_API | jq -r --arg architecture "$architecture" --arg version "$VERSION" '.[] | select(.tag_name==$version) | .assets[] | select (.name | contains($architecture)) | .browser_download_url' -); fi; \
    if [ "$VERSION" = "latest" ] && [ "$PRERELEASE" -ne 0 ]; then download_url=$(curl -L $REPO_API | jq -r --arg architecture "$architecture" '.[0] | .assets[] | select (.name | contains($architecture)) | .browser_download_url' -); fi; \
    if [ "$VERSION" = "latest" ] && [ "$PRERELEASE" -eq 0 ]; then download_url=$(curl -L $REPO_API | jq -r --arg architecture "$architecture" '[.[] | select(.prerelease==false)] | first | .assets[] | select (.name | contains($architecture)) | .browser_download_url' -); fi; \
    \
    curl -L $download_url -o dcompass; \
    curl -L https://github.com/LEXUGE/dcompass/raw/main/configs/example.yaml -o config.yaml;

FROM --platform=$TARGETPLATFORM alpine AS runtime
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# RUN echo "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.11/main/" > /etc/apk/repositories

COPY --from=builder /go/dcompass /usr/local/bin
COPY --from=builder /go/config.yaml /etc/dcompass/config.yaml
COPY entrypoint.sh /usr/local/bin/

RUN set -eux; \
    \
    apk add --no-cache \
        ca-certificates; \
    \
    rm -rf /var/cache/apk/*; \
    chmod a+x /usr/local/bin/dcompass; \
    chmod a+x /usr/local/bin/entrypoint.sh

EXPOSE 53/udp

ENTRYPOINT ["entrypoint.sh"]
CMD ["dcompass", "-c", "/etc/dcompass/config.yml"]