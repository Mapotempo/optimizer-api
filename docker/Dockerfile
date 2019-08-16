ARG BRANCH=${BRANCH:-ce}
ARG OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION:-latest}
ARG ORTOOLS_VERSION=${ORTOOLS_VERSION:-latest}
ARG REGISTRY=${REGISTRY:-registry.mapotempo.com/}
ARG VROOM_VERSION=${VROOM_VERSION:-latest}

# Install ORTools
FROM ${REGISTRY}mapotempo/ortools:${ORTOOLS_VERSION} as ortools

# Install Optimizer-ortools
FROM ${REGISTRY}mapotempo-${BRANCH}/optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION} as optimizer-ortools

# Install Vroom
FROM ${REGISTRY}mapotempo/vroom:${VROOM_VERSION} as vroom

RUN echo ${VROOM_VERSION}

# Rake
FROM ruby:2.3-slim as rake

ENV LANG C.UTF-8

RUN apt-get update > /dev/null && \
  apt-get install -y git build-essential libgeos-dev zlib1g-dev zlib1g nano > /dev/null

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

COPY --from=ortools /srv/or-tools srv/or-tools
COPY --from=optimizer-ortools /srv/optimizer-ortools /srv/optimizer-ortools
COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/
COPY --from=rake /srv/app /srv/app
COPY --from=rake /usr/local/ /usr/local/
COPY --from=rake /usr/lib/x86_64-linux-gnu/libgeos* /usr/lib/x86_64-linux-gnu/

WORKDIR /srv/app

EXPOSE 1791
CMD ["bundle", "exec", "rake", "server"]
