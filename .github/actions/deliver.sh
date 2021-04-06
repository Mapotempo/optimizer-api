#!/usr/bin/env bash
ref=${GITHUB_REF/refs\/tags\//}

docker login -u ${REGISTRY_USER} -p ${REGISTRY_PWD} ${REGISTRY}
docker pull ${REGISTRY}/mapotempo-ce/optimizer-api:${ref}

if [[ $? == 0 ]];then
  docker tag ${REGISTRY}/mapotempo-ce/optimizer-api:${ref} ${REGISTRY}/mapotempo-ce/optimizer-api:${ref}-old
  docker push ${REGISTRY}/mapotempo-ce/optimizer-api:${ref}-old
fi

docker tag registry.test.com/mapotempo/optimizer-api:latest ${REGISTRY}/mapotempo-ce/optimizer-api:${ref}
docker push ${REGISTRY}/mapotempo-ce/optimizer-api:${ref}
