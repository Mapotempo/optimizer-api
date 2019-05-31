ARG OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION:-dev}
ARG ORTOOLS_VERSION=${ORTOOLS_VERSION:-latest}
ARG REGISTRY=${REGISTRY:-registry.mapotempo.com/}

# Install ORTools
FROM ${REGISTRY}mapotempo/ortools:${ORTOOLS_VERSION} as optimizer-ortools
ARG OPTIMIZER_ORTOOLS_VERSION

RUN echo "Build optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION}"
# Build wrapper
RUN apt-get update > /dev/null && \
  apt-get -y install git wget pkg-config build-essential cmake autoconf libtool zlib1g-dev lsb-release > /dev/null

RUN  git clone https://github.com/mapotempo/optimizer-ortools.git --branch ${OPTIMIZER_ORTOOLS_VERSION} /srv/optimizer-ortools && \
  cd /srv/optimizer-ortools && \
  make tsp_simple

# Final image
FROM debian:latest

LABEL maintainer="Mapotempo <contact@mapotempo.com>"

COPY --from=optimizer-ortools /srv/optimizer-ortools /srv/optimizer-ortools

WORKDIR /srv/optimizer-ortools
