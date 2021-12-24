ARG BRANCH
ARG BUNDLE_WITHOUT="development test"
ARG OPTIMIZER_ORTOOLS_VERSION
ARG REGISTRY
ARG VROOM_VERSION

# Install Vroom
FROM vroomvrp/vroom-docker:${VROOM_VERSION:-v1.8.0} as vroom

# Rake
FROM ${REGISTRY:-registry.mapotempo.com/}mapotempo-${BRANCH:-ce}/optimizer-ortools:${OPTIMIZER_ORTOOLS_VERSION:-v1.10.0}
ARG BUNDLE_WITHOUT

ENV LANG C.UTF-8

# Set correct environment variables.
ENV HOME /root

# Trick to install passenger-docker on Ruby 2.5. Othwerwise `apt-get update` fails with a
# certificate error. See following links for explanantion:
# https://issueexplorer.com/issue/phusion/passenger-docker/325
# and
# https://issueexplorer.com/issue/phusion/passenger-docker/322
# Basically, DST Root CA X3 certificates are expired on Setember 2021 and apt-get cannot validate
# with the old certificates and the certification correction is only done for Ruby 2.6+ on the
# passenger-docker repo because Ruby 2.5 is EOL.
RUN mv /etc/apt/sources.list.d /etc/apt/sources.list.d.bak
RUN apt update && apt install -y ca-certificates
RUN mv /etc/apt/sources.list.d.bak /etc/apt/sources.list.d
# The above trick can be removed after Ruby version is increased.

RUN apt-get update > /dev/null && \
  libgeos=$(apt-cache search 'libgeos-' | grep -P 'libgeos-\d.*' | awk '{print $1}') && \
  apt-get install -y git libgeos-dev ${libgeos} libicu-dev nano > /dev/null

COPY --chown=app . /srv/app/
RUN install -d --owner app /srv/app/archives

USER app
WORKDIR /srv/app

RUN gem install bundler --version 2.2.24 && \
  bundle --version && \
  bundle install --path vendor/bundle --full-index --without ${BUNDLE_WITHOUT} -j $(nproc)

LABEL maintainer="Mapotempo <tech@mapotempo.com>"

ENV REDIS_HOST redis-cache
ENV LANG C.UTF-8

COPY --from=vroom /usr/local/bin /srv/vroom/bin

USER root
# Enable Nginx and Passenger
RUN rm -f /etc/service/nginx/down && \
  rm /etc/nginx/sites-enabled/default

# Enable app
ADD docker/env.d/* /etc/nginx/main.d/
ADD docker/snippets/* /etc/nginx/snippets/
ADD docker/webapp.conf /etc/nginx/sites-enabled/webapp.conf

RUN apt-get remove -y git build-essential && \
  apt-get autoremove -y && \
  apt-get clean && \
  echo -n > /var/lib/apt/extended_states && \
  rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*
