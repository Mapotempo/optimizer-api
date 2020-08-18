ARG BRANCH=${BRANCH:-ce}
ARG OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION}
ARG REGISTRY=${REGISTRY:-registry.mapotempo.com/}
ARG VROOM_VERSION=${VROOM_VERSION}

# Install Vroom
FROM ${REGISTRY}mapotempo/vroom:${VROOM_VERSION} as vroom
RUN echo ${REGISTRY}mapotempo/vroom:${VROOM_VERSION}

# From  Optimizer-ortools
FROM ${REGISTRY}mapotempo-${BRANCH}/optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION}

ENV LANG C.UTF-8

RUN apt-get update > /dev/null && \
  apt-get install -y libgeos-dev libgeos-3.8.0 libicu-dev zlib1g nano > /dev/null

COPY . /srv/app
WORKDIR /srv/app
RUN bundle --version
RUN bundle check || bundle install --full-index --without development -j $(nproc)

ENV APP_ENV production
ENV REDIS_HOST redis-cache
LABEL maintainer="Mapotempo <tech@mapotempo.com>"

COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/

# Enable app
COPY docker/env.d/* /etc/nginx/main.d/
COPY docker/snippets/* /etc/nginx/snippets/
COPY docker/vhost.conf /etc/nginx/sites-enabled/default

# Cleanup packages
RUN apt-get remove -y git build-essential && \
  apt-get autoremove -y && \
  apt-get clean && \
  bundle clean --force && \
  echo -n > /var/lib/apt/extended_states && \
  rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# Enable Nginx and Passenger
RUN rm -f /etc/service/nginx/down

EXPOSE 1791
CMD ["bundle", "exec", "rackup", "-p", "1791"]
