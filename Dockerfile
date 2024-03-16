# To set multiarch build for Docker hub automated build.
FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG VERSION
ARG DCOMPASS_TARGET_COMMITISH
ARG PRERELEASE

ENV ROOTFS=/go/rootfs

WORKDIR /go

RUN <<EOF
    set -eux;
    apk add curl jq --no-cache
    case "${TARGETPLATFORM}" in
        "linux/amd64")
            architecture="x86_64-unknown-linux-musl"
            ;;
        "linux/arm64")
            architecture="aarch64-unknown-linux-musl"
            ;;
        "linux/arm/v7")
            architecture="armv7-unknown-linux-musleabihf"
            ;;
        *)
            echo "Unknown platform: ${TARGETPLATFORM}" >&2
            exit 1
            ;;
    esac

    repo_api="https://api.github.com/repos/LEXUGE/dcompass/releases?per_page=100"
    version=${version:-latest}
    [ "$version" != "latest" ] && version="v$(echo ${version##v})"
    prerelease=${prerelease:-0}
    # asset_pattern="^.*${architecture}"
    asset_pattern="^dcompass-${architecture}$"

    if [ "$version" != "latest" ]; then
        download_url=$(curl -L "$repo_api" | jq -r --arg asset_pattern "$asset_pattern" --arg version "$version" '[.[] | select((.tag_name==$version) and (.assets | length) > 0)] | first | .assets[] | select (.name | test($asset_pattern)) | .browser_download_url' -)
    fi

    if [ "$version" = "latest" ]; then
        if [ "$prerelease" -ne 0 ]; then
            download_url=$(curl -L "$repo_api" | jq -r --arg asset_pattern "$asset_pattern" '[.[] | select(.assets | length > 0)] | first | .assets[] | select (.name | test($asset_pattern)) | .browser_download_url' -)
        else
            download_url=$(curl -L "$repo_api" | jq -r --arg asset_pattern "$asset_pattern" '[.[] | select((.prerelease==false) and (.assets | length) > 0)] | first | .assets[] | select (.name | test($asset_pattern)) | .browser_download_url' -)
        fi
    fi

    mkdir -p "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/dcompass"

    curl -L "$download_url" -o "${ROOTFS}/usr/local/bin/dcompass";
    curl -L https://github.com/LEXUGE/dcompass/raw/main/configs/example.yaml -o "${ROOTFS}/etc/dcompass/config.yaml"
EOF

COPY entrypoint.sh "${ROOTFS}/usr/local/bin/"

FROM --platform=$TARGETPLATFORM alpine AS runtime
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# RUN echo "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.11/main/" > /etc/apk/repositories

COPY --from=builder /go/rootfs/. /

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