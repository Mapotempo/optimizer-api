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

# Install Rake
FROM mapotempo/nginx-passenger:2.0.1 as rake

ENV APP_ENV production

ADD . /srv/app
RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y git build-essential zlib1g-dev zlib1g nano
RUN which nano

RUN cd /srv/app && \
  gem install --no-rdoc --no-ri bundler && \
  bundle check --path vendor/bundle --without development || bundle install --full-index --without development --path vendor/bundle && \
  chown -R www-data:www-data .

# Install Vroom
FROM ${REGISTRY}mapotempo/vroom:${VROOM_VERSION} as vroom

RUN echo ${VROOM_VERSION}

# Final image
FROM mapotempo/nginx-passenger:2.0.1
LABEL maintainer="Mapotempo <contact@mapotempo.com>"

ENV REDIS_HOST redis-cache
ADD docker/env.d/* /etc/nginx/env.d/

COPY --from=ortools /srv/or-tools/lib srv/or-tools/lib
COPY --from=ortools /srv/or-tools/bin srv/or-tools/bin
COPY --from=ortools /srv/optimizer-ortools /srv/optimizer-ortools
COPY --from=vroom /srv/vroom/bin /srv/vroom/bin
COPY --from=vroom /usr/lib/x86_64-linux-gnu/libboost* /usr/lib/x86_64-linux-gnu/
COPY --from=rake /srv/app /srv/app
COPY --from=rake /usr/local/bin /usr/local/bin
COPY --from=rake /var/lib/gems /var/lib/gems
COPY --from=rake /bin/nano /bin/nano

WORKDIR /srv/app
