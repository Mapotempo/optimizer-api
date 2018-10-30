#!/usr/bin/env bash

git clone --depth 1 --single-branch --branch "${BRANCH:-master}" "https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/${GITLAB_USER}/ci-utils.git" ci-tmp
rsync -a ci-tmp/* ./ci-utils

./ci-utils/deploy.sh "${SLACK_CHANNELS}" "${HOOKS}"
