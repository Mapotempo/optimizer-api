#!/usr/bin/env bash

CONTAINER=${PROJECT}_api.1.$(docker service ps -f "name=${PROJECT}_api.1" ${PROJECT}_api -q --no-trunc | head -n1)
docker exec -i ${CONTAINER} rake test TESTOPTS="${TESTOPTS}" ${OPTIONS}
