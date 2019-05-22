ARG CI_COMMIT_REF_NAME=latest
ARG ORTOOLS_VERSION=${ORTOOLS_VERSION:-latest}
ARG VROOM_VERSION=${VROOM_VERSION:-latest}
ARG REGISTRY=${REGISTRY:-registry.mapotempo.com/}

# Install ORTools
FROM ${REGISTRY}mapotempo/ortools:${ORTOOLS_VERSION} as ortools

RUN apt-get update && \
  apt-get install -y git bison flex python-setuptools python-dev autoconf \
  libtool zlib1g-dev texinfo help2man gawk g++ curl texlive cmake subversion unzip gettext

RUN if [ "$CI_COMMIT_REF_NAME" == "beta"]; \
  then export OPTIMIZER_ORTOOLS_VERSION=dev; \
  fi

# Build wrapper
RUN  git clone https://github.com/mapotempo/optimizer-ortools.git --branch ${OPTIMIZER_ORTOOLS_VERSION:-master} /srv/optimizer-ortools && \
  cd /srv/optimizer-ortools && \
  make tsp_simple

# Install Vroom
FROM ${REGISTRY}mapotempo/vroom:${VROOM_VERSION} as vroom

RUN echo ${VROOM_VERSION}

# Rake
FROM ruby:2.3-slim as rake

ENV LANG C.UTF-8

RUN apt-get update && \
  apt-get install -y git build-essential zlib1g-dev zlib1g nano

ADD . /srv/app
RUN cd /srv/app && \
  gem install bundler && \
  bundle check --path vendor/bundle --without development || bundle install --full-index --without development --path vendor/bundle

# Final image
FROM ruby:2.3-slim

LABEL maintainer="Mapotempo <contact@mapotempo.com>"

ENV APP_ENV production
ENV REDIS_HOST redis-cache
ENV LANG C.UTF-8

COPY --from=ortools /srv/or-tools/lib srv/or-tools/lib
COPY --from=ortools /srv/or-tools/bin srv/or-tools/bin
COPY --from=ortools /srv/optimizer-ortools /srv/optimizer-ortools
COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/
COPY --from=rake /srv/app /srv/app
COPY --from=rake /usr/local/ /usr/local/

WORKDIR /srv/app

EXPOSE 1791
CMD ["bundle", "exec", "rake", "server"]
