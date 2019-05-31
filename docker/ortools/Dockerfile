# Install ORTools
FROM debian:latest as ortools

ARG ORTOOLS_VERSION=latest
ENV ORTOOLS_VERSION ${ORTOOLS_VERSION}

RUN apt-get update > /dev/null && \
  apt-get -y install git wget pkg-config build-essential cmake autoconf libtool zlib1g-dev lsb-release > /dev/null && \
  git clone https://github.com/google/or-tools.git --branch ${ORTOOLS_VERSION} /srv/or-tools

# Build
RUN cd /srv/or-tools && \
  make third_party && \
  make cc

RUN find /srv/or-tools/dependencies -name '.git' -exec rm -rf {} + && \
  find /srv/or-tools/dependencies -name 'cmake' -exec rm -rf {} +

FROM debian:latest
LABEL maintainer="Mapotempo <contact@mapotempo.com>"

COPY --from=ortools /srv/or-tools/Makefile* srv/or-tools/
COPY --from=ortools /srv/or-tools/Version.txt srv/or-tools/Version.txt
COPY --from=ortools /srv/or-tools/makefiles srv/or-tools/makefiles
COPY --from=ortools /srv/or-tools/lib srv/or-tools/lib
COPY --from=ortools /srv/or-tools/ortools srv/or-tools/ortools
COPY --from=ortools /srv/or-tools/dependencies srv/or-tools/dependencies
