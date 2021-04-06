#!/usr/bin/env bash

docker build --build-arg BUNDLE_WITHOUT=development --build-arg VROOM_VERSION=${VROOM_VERSION} --build-arg OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION} -f docker/Dockerfile -t registry.test.com/mapotempo/optimizer-api:latest .

# Cache generated gems
mkdir -p vendor/bundle
docker cp $(docker create --rm registry.test.com/mapotempo/optimizer-api:latest):/srv/app/vendor/bundle/. vendor/bundle
