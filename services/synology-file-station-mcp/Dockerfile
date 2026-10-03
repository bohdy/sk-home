# Build the adapter from a pinned Python runtime and the same verified
# OpenAI tunnel-client runtime used by the Grafana image. ffprobe is built
# from the verified upstream release with only the formats and protocols this
# adapter needs; the runtime image does not inherit a distribution ffmpeg.
ARG PYTHON_BASE_IMAGE=python:3.14.8-slim-trixie@sha256:89fb7d3da20043c370643435258bdd7ab755d326d359001d02988ed15ae5219e
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS ffprobe-builder

ARG FFMPEG_VERSION=9.0.2
ARG FFMPEG_SHA256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install --no-install-recommends --yes build-essential ca-certificates curl pkg-config xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl --fail --location --proto '=https' --tlsv1.2  \
    --output "/tmp/ffmpeg-${FFMPEG_VERSION}.tar.xz"        "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && echo "${FFMPEG_SHA256}  /tmp/ffmpeg-${FFMPEG_VERSION}.tar.xz" | sha256sum --check --strict \
    && tar --extract --file "/tmp/ffmpeg-${FFMPEG_VERSION}.tar.xz" --directory /tmp

WORKDIR /tmp/ffmpeg-${FFMPEG_VERSION}
RUN ./configure \
    --prefix=/opt/ffprobe \
    --disable-debug \
    --disable-doc \
    --disable-autodetect \
    --enable-network --disable-x86asm \
    --disable-everything \
    --disable-ffmpeg \
    --disable-ffplay \
    --disable-shared \
    --enable-static \
    --enable-ffprobe \
    --enable-protocol=file,http,tcp \
    --enable-demuxer=aac,avi,flac,matroska,mp3,mpegts,mov,ogg,wav \
    --enable-parser=aac,ac3,flac,h264,hevc,mjpeg,mpegaudio,mpeg4video,opus,vorbis,vp8,vp9 \
    --enable-decoder=aac,ac3,flac,h264,hevc,mjpeg,mpeg1video,mpeg2video,mpeg4,mp3,opus,vorbis,vp8,vp9 \
    && make -j"$(nproc)" ffprobe \
    && install -D --mode=0755 ffprobe /opt/ffprobe/usr/local/bin/ffprobe \
    && /opt/ffprobe/usr/local/bin/ffprobe -version | head -n 1

FROM ${PYTHON_BASE_IMAGE}

# Consume BuildKit automatic target architecture for native and multi-platform release selection.
ARG TARGETARCH
ARG TUNNEL_VERSION=v0.0.15

ENV PYTHONDONTWRITEBYTECODE=1     PYTHONUNBUFFERED=1     PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install --no-install-recommends --yes ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ffprobe-builder /opt/ffprobe/usr/local/bin/ffprobe /usr/local/bin/ffprobe

RUN set -eux;     case "${TARGETARCH}" in       amd64) tunnel_arch=amd64; tunnel_sha=f26f8b3ee6c335e38fa5cfbe6ce5635f53738f08a26eecf07d6cebacab4a1abf ;;       arm64) tunnel_arch=arm64; tunnel_sha=a868d295385b22449341fa141b911f3e991583e45b1fa2a5bfb946aed1861b88 ;;       *) echo "unsupported target architecture" >&2; exit 1 ;;     esac;     archive="tunnel-client-runtime-${TUNNEL_VERSION}-linux-${tunnel_arch}.zip";     url="https://github.com/openai/tunnel-client/releases/download/${TUNNEL_VERSION}/${archive}";     curl --fail --location --proto '=https' --tlsv1.2 --output "/tmp/${archive}" "${url}";     echo "${tunnel_sha}  /tmp/${archive}" | sha256sum --check --strict;     unzip -p "/tmp/${archive}" tunnel-client-runtime > /usr/local/bin/tunnel-client;     chmod 0755 /usr/local/bin/tunnel-client;     rm -f "/tmp/${archive}"

WORKDIR /opt/synology-file-station-mcp
COPY pyproject.toml ./
COPY requirements.lock ./
COPY synology_file_station_mcp ./synology_file_station_mcp
RUN python -m pip install --no-cache-dir --require-hashes --no-deps --requirement requirements.lock \
    && python -m pip install --no-cache-dir --no-build-isolation --no-deps .

# Keep the adapter non-root and provide only the bounded scratch locations it
# needs. Kubernetes repeats these controls in the pod security context.
RUN useradd --system --uid 65532 --home-dir /nonexistent --shell /usr/sbin/nologin mcp \
    && install --directory --owner=65532 --group=65532 --mode=0750 /run/tunnel-client /tmp/mcp \
    && chown -R 65532:65532 /opt/synology-file-station-mcp /usr/local/bin/tunnel-client /usr/local/bin/ffprobe

USER 65532:65532
ENV PATH=/usr/local/bin:/usr/bin:/bin
ENTRYPOINT ["/usr/local/bin/tunnel-client"]
