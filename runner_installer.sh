#!/bin/bash

# Variables for registering runners
export GITLAB_URL="https://gitlab.com"
export GITLAB_RUNNER_REGISTRATION_TOKEN=""
export GITLAB_RUNNER_EXECUTOR="shell"

# Install GitLab Runner on Oracle Linux
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | sudo bash
sudo yum install gitlab-runner -y

sudo gitlab-runner start

sudo gitlab-runner register \
  --non-interactive \
  --description "$(hostname)" \
  --url "$GITLAB_URL" \
  --registration-token "$GITLAB_RUNNER_REGISTRATION_TOKEN" \
  --executor "$GITLAB_RUNNER_EXECUTOR" \
  --tag-list "oci" \
  --run-untagged="true" \
  --locked="false" \
  --access-level="not_protected"
