#!/usr/bin/env bash

docker build --build-arg BUNDLE_WITHOUT=development --build-arg VROOM_VERSION=${VROOM_VERSION} --build-arg OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION} -f docker/Dockerfile -t registry.test.com/mapotempo/optimizer-api:latest .

# Cache generated gems
mkdir -p vendor/bundle
docker cp $(docker create --rm registry.test.com/mapotempo/optimizer-api:latest):/srv/app/vendor/bundle/. vendor/bundle

# Initialize swarm
docker swarm init
mkdir -p ./redis
mkdir -p ./redis-count
docker stack deploy -c ./docker/docker-compose.yml ${PROJECT}

# Wait until all services are up
REGISTRY=${REGISTRY:-registry.mapotempo.com}
max_time=60 # Time in secondes
for ((cpt=1;cpt<=$max_time;cpt++));
do
  if [ $cpt == ${max_time} ];
  then
    echo "Could not start services after ${max_time} seconds"
    docker service ls
    for srv in $(docker service ls | grep 0/1 | awk '{print $1}');
    do
      docker service ps --no-trunc $srv
      docker service logs $srv
    done
    exit 1
  fi

  nb_services=${NB_SERVICES:-5}
  nbps=$(docker service ls | grep 1/1 | awk '{print $4}' | wc -l)
  if [ ${nbps} -eq ${nb_services} ];
  then
    echo "All services up, starting tests"
    break;
  fi

  echo "Waiting for all services (${nbps}/${nb_services}) to start ($cpt secondes)."
  sleep 1
done
