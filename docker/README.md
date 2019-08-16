# Building images

```
export REGISTRY='registry.mapotempo.com/'
```

## Required images
Optimizer requires the two following images that must be manually built.

### Ortools

```
export ORTOOLS_VERSION=v7.0
docker build --build-arg ORTOOLS_VERSION=${ORTOOLS_VERSION} \
  -f ./docker/ortools/Dockerfile -t ${REGISTRY}mapotempo/ortools:${ORTOOLS_VERSION} .
```

### Optimizer Ortools (wrapper)
*OPTIMIZER_ORTOOLS_VERSION* can either be *master*, *v7.0* or *dev*

```
export ORTOOLS_VERSION=v7.0
export OPTIMIZER_ORTOOLS_VERSION=dev
export BRANCH=${BRANCH:-beta}
docker build --build-arg OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION} \
  --build-arg ORTOOLS_VERSION=${ORTOOLS_VERSION} \
  --build-arg BRANCH=${BRANCH} \
  -f ./docker/optimizer-ortools/Dockerfile -t ${REGISTRY}mapotempo-${BRANCH}/optimizer-ortools:latest .
```

#### Vroom
```
export VROOM_VERSION=v1.2.0
docker build --build-arg VROOM_VERSION=${VROOM_VERSION} \
  -f ./docker/vroom/Dockerfile -t ${REGISTRY}mapotempo/vroom:${VROOM_VERSION} .
```

## Build API

```
export CI_COMMIT_REF_NAME=latest
export OPTIMIZER_ORTOOLS_VERSION=latest
export ORTOOLS_VERSION=v7.0
export VROOM_VERSION=v1.2.0
export BRANCH=${BRANCH:-beta}
docker build \
  --build-arg ORTOOLS_VERSION=${ORTOOLS_VERSION} \
  --build-arg OPTIMIZER_ORTOOLS_VERSION=${OPTIMIZER_ORTOOLS_VERSION} \
  --build-arg VROOM_VERSION=${VROOM_VERSION} \
  --build-arg CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME} \
  -f ./docker/Dockerfile -t ${REGISTRY}mapotempo-${BRANCH}/optimizer-api:${CI_COMMIT_REF_NAME} .
```

## Running services
This project uses swarm to launch

```
docker swarm init
```

Optimizer requires router matrix, you can define variables that the container will use to hit.

```
export PROJECT_NAME='optimizer'
export ROUTER_API_KEY=''
export ROUTER_URL='http://localhost:4899/0.1'
export REGISTRY='registry.mapotempo.com/'
```

**Deploy the services (Access it via http://localhost:8083)**

```
mkdir -p ./docker/redis
docker stack deploy -c ./docker/docker-compose.yml ${PROJECT_NAME}
```

**Execute something inside the api container**

```
DOCKER_SERVICE_NAME=${PROJECT_NAME}_api
CONTAINER=${DOCKER_SERVICE_NAME}.1.$(docker service ps -f "name=${DOCKER_SERVICE_NAME}.1" ${DOCKER_SERVICE_NAME} -q --no-trunc | head -n1)
docker exec -i ${CONTAINER} ls -l /var/log
```