#!/usr/bin/env bash

git clone --depth 1 --single-branch --branch "${BRANCH:-master}" "https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/${GITLAB_USER}/ci-utils.git" ci-tmp
rsync -a ci-tmp/* ./ci-utils

# shellcheck disable=SC1091
source ./ci-utils/utils.sh

slacks "*ERROR* ${slack_users}, *access.rb* is managed by optimizer-conf project, the change has to be done there." "${SLACK_CHANNELS}"

exit 1
