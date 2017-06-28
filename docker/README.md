Using Docker Compose to deploy Mapotempo Optimizer API
======================================================

Building images
---------------

    git clone https://github.com/mapotempo/optimizer-api
    cd optimizer-api/docker
    docker-compose build

Publishing images
-----------------

    docker login
    docker-compose push

Running on a docker host
------------------------

    git clone https://github.com/mapotempo/optimizer-api
    cd optimizer-api/docker
    docker-compose pull
    cp ../config/environments/production.rb ./
    # Edit production.rb file to match your needs
    docker-compose -p optimizer up -d
