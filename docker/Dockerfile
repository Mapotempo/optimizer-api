ARG BRANCH=${BRANCH:-ce}
ARG OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION}
ARG REGISTRY=${REGISTRY:-registry.mapotempo.com/}
ARG VROOM_VERSION=${VROOM_VERSION}

# Install Optimizer-ortools
FROM ${REGISTRY}mapotempo-${BRANCH}/optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION} as optimizer-ortools

# Install Vroom
RUN echo ${REGISTRY}mapotempo/vroom:${VROOM_VERSION}
FROM ${REGISTRY}mapotempo/vroom:${VROOM_VERSION} as vroom

RUN echo ${VROOM_VERSION}

# Rake
FROM ruby:2.3.3 as rake

ENV LANG C.UTF-8

RUN apt-get update > /dev/null && \
  apt-get install -y git build-essential libgeos-dev libgeos-3.4.2 libicu-dev zlib1g-dev zlib1g nano > /dev/null

COPY . /srv/app
WORKDIR /srv/app
RUN gem install bundler --version 1.17.3
RUN bundle --version
RUN bundle check || bundle install --full-index --without development -j $(nproc)
# Final image
FROM ruby:2.3.3

LABEL maintainer="Mapotempo <contact@mapotempo.com>"

ENV APP_ENV production
ENV REDIS_HOST redis-cache
ENV LANG C.UTF-8

COPY --from=optimizer-ortools /srv/or-tools srv/or-tools
COPY --from=optimizer-ortools /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=optimizer-ortools /srv/optimizer-ortools /srv/optimizer-ortools
COPY --from=optimizer-ortools /lib/x86_64-linux-gnu/libm* /lib/x86_64-linux-gnu/
COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/
COPY --from=rake /srv/app /srv/app
COPY --from=rake /usr/local/bundle /usr/local/bundle
COPY --from=rake /usr/local/ /usr/local/
COPY --from=rake /usr/lib/libgeos* /usr/lib/
COPY --from=rake /usr/lib/x86_64-linux-gnu/icu* /usr/lib/x86_64-linux-gnu/
COPY --from=rake /usr/lib/x86_64-linux-gnu/libicu* /usr/lib/x86_64-linux-gnu/

WORKDIR /srv/app

EXPOSE 1791
CMD ["bundle", "exec", "rake", "server"]
