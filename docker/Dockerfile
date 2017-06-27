FROM mapotempo/nginx-passenger:latest

LABEL maintainer="Mapotempo <contact@mapotempo.com>"

ARG ORTOOLS_VERSION
ENV ORTOOLS_VERSION ${ORTOOLS_VERSION:-v5.1}

ARG JSPRIT_VERSION
ENV JSPRIT_VERSION ${JSPRIT_VERSION:-latestPrime}

ARG VROOM_VERSION
ENV VROOM_VERSION ${VROOM_VERSION:-v0.3.1}

ENV RAILS_ENV production
ENV APP_
ENV ROUTER_URL https://router.mapotempo.com

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

# Install JSprit
RUN echo "deb http://ftp.fr.debian.org/debian jessie-backports main" > /etc/apt/sources.list.d/backports.list && \
    apt-get update && \
    apt-get install -y git && \
    apt-get install -y -t jessie-backports openjdk-8-jdk maven \
            openjdk-8-jre && \
    \
# Get source code
    git clone https://github.com/mapotempo/jsprit --branch ${JSPRIT_VERSION} /srv/jsprit && \
    git clone https://github.com/mapotempo/optimizer-jsprit /srv/optimizer-jsprit && \
    \
# Build
    cd /srv/jsprit && \
    rm -rf .git && \
    mvn clean install -Dmaven.test.skip=true && \
    \
    cd /srv/optimizer-jsprit && \
    rm -rf .git && \
    mvn clean install -Dmaven.test.skip=true && \
    \
# Cleanup Debian packages
    apt-get remove -y git maven openjdk-8-jdk && \
    apt-get autoremove -y && \
    apt-get clean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# Install ORTools
RUN apt-get update && \
    apt-get install -t jessie-backports -y git bison flex python-setuptools python-dev autoconf \
            libtool zlib1g-dev texinfo help2man gawk g++ curl texlive cmake subversion unzip gettext && \
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

WORKDIR /srv/app
