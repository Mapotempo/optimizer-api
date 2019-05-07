# Install ORTools
FROM debian:latest as ortools

ARG ORTOOLS_VERSION=latest
ENV ORTOOLS_VERSION ${ORTOOLS_VERSION}

RUN apt-get update && \
  apt-get install -y git bison flex python-setuptools python-dev autoconf \
  libtool zlib1g-dev texinfo help2man gawk g++ curl texlive cmake subversion unzip gettext && \
# Override IP address for this mirror because the other one is buggy.
  echo "90.147.160.69 mirror2.mirror.garr.it" >> /etc/hosts && \
# Get source code
  git clone https://github.com/google/or-tools.git --branch ${ORTOOLS_VERSION} /srv/or-tools

# Build
RUN cd /srv/or-tools && \
  make third_party && \
  make cc

FROM debian:latest
LABEL maintainer="Mapotempo <contact@mapotempo.com>"

COPY --from=ortools /srv/or-tools/ srv/or-tools/
