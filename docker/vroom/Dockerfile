# Install Vroom
FROM debian:latest as vroom

ARG VROOM_VERSION=latest
ENV VROOM_VERSION ${VROOM_VERSION:-latest}

RUN apt-get update && \
  apt-get install -y git build-essential libboost-all-dev libboost-dev && \
# Get Source code
  git clone https://github.com/VROOM-Project/vroom --branch ${VROOM_VERSION} /srv/vroom

# Build
RUN cd /srv/vroom/src && \
  mkdir -p ../build ../bin && \
  make

FROM debian:latest
LABEL maintainer="Mapotempo <contact@mapotempo.com>"

COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/
