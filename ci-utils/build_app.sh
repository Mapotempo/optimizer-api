#!/usr/bin/env bash

echo "SLACK_CHANNELS: $SLACK_CHANNELS"
echo "PROJECT_NAME: $PROJECT_NAME"

git clone --depth 1 --single-branch --branch "${BRANCH:-master}" "https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/${GITLAB_USER}/ci-utils.git" ci-tmp
rsync -a ci-tmp/* ./ci-utils

./ci-utils/build_and_push.sh "${PROJECT_NAME}" "${SLACK_CHANNELS}"
