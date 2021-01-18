ARG BRANCH=${BRANCH:-ce}
ARG OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION}
ARG REGISTRY=${REGISTRY:-registry.mapotempo.com/}
ARG VROOM_VERSION=${VROOM_VERSION}

# Install Vroom
FROM ${REGISTRY}mapotempo/vroom:${VROOM_VERSION:-v1.5.0} as vroom

# Rake
FROM ${REGISTRY}mapotempo-${BRANCH}/optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION:-v1.4.0}

ENV LANG C.UTF-8

RUN apt-get update > /dev/null
RUN libgeos=$(apt-cache search 'libgeos-' | grep -P 'libgeos-\d.*' | awk '{print $1}')
RUN apt-get install -y git libgeos-dev ${libgeos} libicu-dev nano > /dev/null

COPY . /srv/app
WORKDIR /srv/app
RUN bundle --version
RUN bundle check || bundle install --full-index --without development -j $(nproc)

LABEL maintainer="Mapotempo <contact@mapotempo.com>"

ENV APP_ENV production
ENV REDIS_HOST redis-cache
ENV LANG C.UTF-8

COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/

RUN apt-get remove -y git build-essential && \
  apt-get autoremove -y && \
  apt-get clean && \
  echo -n > /var/lib/apt/extended_states && \
  rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

WORKDIR /srv/app

EXPOSE 1791
CMD ["bundle", "exec", "rake", "server"]
