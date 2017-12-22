FROM mapotempo/nginx-passenger:2.0.1

LABEL maintainer="Mapotempo <contact@mapotempo.com>"

ARG ORTOOLS_VERSION
ENV ORTOOLS_VERSION ${ORTOOLS_VERSION:-v6.5}

ARG VROOM_VERSION
ENV VROOM_VERSION ${VROOM_VERSION:-v1.0.0}

ENV RAILS_ENV production
ENV ROUTER_URL https://router.mapotempo.com

ENV REDIS_HOST redis-cache

ADD . /srv/app

# Install app
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git build-essential zlib1g-dev \
            zlib1g && \
    cd /srv/app && \
    rm -rf .git && \
    bundle install --full-index --without test development && \
    \
# Fix permissions
    chown -R www-data:www-data . && \
    \
# Cleanup Debian packages
    apt-get remove -y git build-essential zlib1g-dev && \
    apt-get autoremove -y && \
    apt-get clean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# Install ORTools
RUN apt-get update && \
    apt-get install -y git bison flex python-setuptools python-dev autoconf \
            libtool zlib1g-dev texinfo help2man gawk g++ curl texlive cmake subversion unzip gettext && \
    \
# Override IP address for this mirror because the other one is buggy.
    echo "90.147.160.69 mirror2.mirror.garr.it" >> /etc/hosts && \
    \
# Get source code
    git clone https://github.com/google/or-tools.git --branch ${ORTOOLS_VERSION} /srv/or-tools && \
    \
# Build
    cd /srv/or-tools && \
    make third_party && \
    make cc && \
    \
# Get wrapper source code
    git clone https://github.com/mapotempo/optimizer-ortools.git /srv/optimizer-ortools && \
    \
# Build wrapper
    cd /srv/optimizer-ortools && \
    make tsp_simple && \
    \
# Cleanup Debian packages
    apt-get remove -y git bison flex python-setuptools python-dev autoconf \
            libtool zlib1g-dev texinfo help2man gawk g++ curl texlive cmake subversion unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# Install Vroom
RUN apt-get update && \
    apt-get install -y git build-essential libboost-all-dev libboost-dev && \
    \
# Get Source code
    git clone https://github.com/VROOM-Project/vroom --branch ${VROOM_VERSION} /srv/vroom && \
    cd /srv/vroom/src && \
    mkdir -p ../build ../bin && \
    make && \
    \
# Cleanup Debian packages
    apt-get remove -y git build-essential && \
    apt-get autoremove -y && \
    apt-get clean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*


ADD docker/env.d/* /etc/nginx/env.d/

WORKDIR /srv/app
