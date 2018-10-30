#!/usr/bin/env bash

echo "PROJECT_NAME: $PROJECT_NAME"
export LABEL=${CI_COMMIT_REF_NAME}

git clone --depth 1 --single-branch --branch "${BRANCH:-master}" "https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/${GITLAB_USER}/ci-utils.git" ci-tmp
rsync -a ci-tmp/* ./ci-utils

./ci-utils/tag_issues.sh
