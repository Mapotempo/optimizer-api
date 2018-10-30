#!/usr/bin/env bash

docker stack deploy -c ./docker/travis-dc.yml optimizer

DOCKER_SERVICE_NAME=optimizer_api
CONTAINER=${DOCKER_SERVICE_NAME}.1.$(docker service ps -f "name=${DOCKER_SERVICE_NAME}.1" ${DOCKER_SERVICE_NAME} -q --no-trunc | head -n1)

while true;
do
  STATE=$(docker ps | grep ${CONTAINER})
  if [ -n "${STATE}" ]; then break; fi
  docker service ls
  docker service ps --no-trunc ${DOCKER_SERVICE_NAME}
  sleep 1
done

docker exec -i ${CONTAINER} bash -c 'ls -l test/'
docker exec -i ${CONTAINER} apt update -y > /dev/null
docker exec -i ${CONTAINER} apt install git -y > /dev/null
docker exec -i ${CONTAINER} rm /srv/app/.bundle/config
docker exec -i ${CONTAINER} bundle install
docker exec -i ${CONTAINER} bundle exec rake test SKIP_JSPRIT=true REAL_CASES=true
