#!/usr/bin/env bash
TEST_ENV=''
TEST_LOG_LEVEL='info'
TEST_COVERAGE='false'
DOCKER_SERVICE_NAME=optimizer_api
CONTAINER=${DOCKER_SERVICE_NAME}.1.$(docker service ps -f "name=${DOCKER_SERVICE_NAME}.1" ${DOCKER_SERVICE_NAME} -q --no-trunc | head -n1)

case "$1" in
  'basis')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} SKIP_DICHO=true SKIP_JSPRIT=true SKIP_REAL_CASES=true SKIP_SCHEDULING=true SKIP_SPLIT_CLUSTERING=true"
    ;;
  'dicho')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} TEST=test/lib/heuristics/dichotomious_test.rb"
    ;;
  'real')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} TEST=test/real_cases_test.rb"
    ;;
  'real_scheduling')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} TEST=test/real_cases_scheduling_test.rb"
    ;;
  'real_scheduling_solver')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} TEST=test/real_cases_scheduling_solver_test.rb"
    ;;
  'scheduling')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} TEST=test/lib/heuristics/scheduling_*"
    ;;
  'split_clustering')
    TEST_ENV="TRAVIS=true COV=${TEST_COVERAGE} LOG_LEVEL=${TEST_LOG_LEVEL} INTENSIVE_TEST=true TEST=test/lib/interpreters/split_clustering_test.rb"
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

docker exec -i ${CONTAINER} apt update -y > /dev/null
docker exec -i ${CONTAINER} apt install git -y > /dev/null

# Output something regularly or Travis kills the job
while sleep 60; do echo "=====[ $SECONDS seconds still running ]====="; done &

# Run the tests without an output buffer and register the exit value
stdbuf -o0 docker exec -it ${CONTAINER} bundle exec rake test ${TEST_ENV}
test_exit_status=$?

# Kill background sleep loop
kill %1

# Return the exit value of the tests
exit $test_exit_status
