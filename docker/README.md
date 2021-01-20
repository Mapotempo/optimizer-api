# Building images

```
export REGISTRY='registry.mapotempo.com/'
```

## Required images
Optimizer requires the two following images that must be manually built.

### Optimizer Ortools (wrapper)
see https://github.com/mapotempo/optimizer-ortools.git

#### Vroom
see https://github.com/VROOM-Project/vroom-docker

## Build API

```
export CI_COMMIT_REF_NAME=latest
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
