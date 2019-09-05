#!/usr/bin/env bash

docker stack deploy -c ./docker/travis-dc.yml optimizer

TEST_ENV=''
DOCKER_SERVICE_NAME=optimizer_api
CONTAINER=${DOCKER_SERVICE_NAME}.1.$(docker service ps -f "name=${DOCKER_SERVICE_NAME}.1" ${DOCKER_SERVICE_NAME} -q --no-trunc | head -n1)
case "$1" in
  'basis')
    TEST_ENV='TRAVIS=true SKIP_DICHO=true SKIP_JSPRIT=true SKIP_REAL_CASES=true SKIP_SCHEDULING=true'
    ;;
  'dicho')
    TEST_ENV='TRAVIS=true TEST=test/lib/heuristics/dichotomious_test.rb'
    ;;
  'real')
    TEST_ENV='TRAVIS=true TEST=test/real_cases_test.rb'
    ;;
  'real_scheduling')
    TEST_ENV='TRAVIS=true TEST=test/real_cases_scheduling_test.rb'
    ;;
  'scheduling')
    TEST_ENV="TRAVIS=true TEST=test/lib/heuristics/scheduling_*"
    ;;
  *)
    ;;
esac

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
docker exec -i ${CONTAINER} bundle exec rake test ${TEST_ENV}
