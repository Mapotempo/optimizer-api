ARG ARCHITECTURE
ARG BRANCH
ARG BUNDLE_WITHOUT="development test"
ARG OPTIMIZER_ORTOOLS_VERSION
ARG REGISTRY_URL
ARG VROOM_VERSION

# Install Vroom
FROM vroomvrp/vroom-docker:${VROOM_VERSION:-v1.12.0} as vroom

# optimizer-ortools
# Set OPTIMIZER_ORTOOLS_VERSION to a tag from mapotempo/optimizer-ortools repo as a secret on your
# optimizer-api repo to force the CI to use a specific mapotempo/optimizer-ortools image.
# Mapotempo devs can also set this variable to their github username on their own optimizer-api repo
# to force the CI to use the last succesful username/optimizer-ortools image.
FROM ${REGISTRY_URL:-registry.mapotempo.com/}mapotempo-${BRANCH:-ce}/${ARCHITECTURE}optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION:-v1.17.1}
ARG BUNDLE_WITHOUT

LABEL maintainer="Mapotempo <tech@mapotempo.com>"

# Set correct environment variables.
ENV HOME /root
ENV LANG C.UTF-8
ENV REDIS_HOST redis-cache

RUN apt-get update > /dev/null && \
  libgeos=$(apt-cache search 'libgeos-' | grep -P 'libgeos-\d.*' | awk '{print $1}') && \
  apt-get install -y git libgeos-dev ${libgeos} libicu-dev libglpk-dev nano gawk bison > /dev/null

# remove when ruby in optimizer-ortools is > 2.5
RUN wget -c https://ftp.gnu.org/gnu/glibc/glibc-2.29.tar.gz && \
  tar -zxvf glibc-2.29.tar.gz && \
  mkdir glibc-build && \
  cd glibc-build && \
  ../glibc-2.29/configure --prefix=/opt/glibc && \
  make && \
  make install

WORKDIR /srv/app
COPY . /srv/app/
RUN mkdir -p /srv/app/archives

RUN gem install bundler --version 2.2.24 && \
  bundle --version && \
  bundle install --path vendor/bundle --full-index --without ${BUNDLE_WITHOUT} -j $(nproc)

COPY --from=vroom /usr/local/bin /srv/vroom/bin
