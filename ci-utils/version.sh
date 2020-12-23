#!/usr/bin/env bash

if [[ $TRAVIS_BRANCH == "master" ]] || [[ $TRAVIS_TAG != "" ]]; then
  export OPTIMIZER_ORTOOLS_VERSION="v1.4.0";
else
  export OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION:-Mapotempo};
fi
