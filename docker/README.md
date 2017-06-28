Using Docker Compose to deploy Mapotempo Optimizer API
======================================================

Building images
---------------

The followings commands will get the source code and build the optimize-api
and needed images:

    git clone https://github.com/mapotempo/optimizer-api
    cd optimizer-api/docker
    docker-compose build

Publishing images
-----------------

To pull them from another host, we need to push the built images to
hub.docker.com:

    docker login
    docker-compose push

Running on a docker host
------------------------

First, we need to retrieve the source code and the prebuilt images:

    git clone https://github.com/mapotempo/optimizer-api
    cd optimizer-api/docker
    docker-compose pull

Then use the configuration file and edit it to match your needs:

    cp ../config/environments/production.rb ./

    # Edit production.rb

Finally run the services:

    docker-compose -p optimizer up -d
