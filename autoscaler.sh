#!/bin/bash

set -ex

export COMPARTMENT_ID=""
export IMAGE_ID=""
export SUBNET_ID=""
export AD=""
export SHAPE="VM.Standard.E3.Flex"
export CLOUD_INIT_FILE_LOCATION="./runner_installer.sh"

export GITLAB_PERSONAL_TOKEN=""
export GITLAB_URL="https://gitlab.com"
export GITLAB_PROJECT_ID=""

export RUNNER_IDLE_TIME_THRESHOLD=120
export MAXIMUM_NUMBER_OF_PENDING_JOBS_THRESHOLD=3
export MAXIMUM_NUMBER_OF_RUNNERS=20
export MINIMUM_NUMBER_OF_RUNNERS=1

# ADDING NEW INSTANCES
# Create new instances if the number of pending jobs is higher than threshold

# Get the number of pending jobs
CURRENT_NUMBER_OF_PENDING_JOBS=$(curl --silent --globoff --header "PRIVATE-TOKEN: "$GITLAB_PERSONAL_TOKEN"" "$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/jobs?scope=pending" | jq '. | length')
CURRENT_NUMBER_OF_RUNNERS=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/runners?type=project_type" | jq '.[].id' | wc -l)

if [ $CURRENT_NUMBER_OF_PENDING_JOBS -gt $MAXIMUM_NUMBER_OF_PENDING_JOBS_THRESHOLD ] && [ $CURRENT_NUMBER_OF_RUNNERS -lt $MAXIMUM_NUMBER_OF_RUNNERS ]
    then
        echo "Scaling: The number of pending jobs $CURRENT_NUMBER_OF_PENDING_JOBS is higher than the threshold of $MAXIMUM_NUMBER_OF_PENDING_JOBS_THRESHOLD"
        CREATED_INSTANCE_DATA=$(oci compute instance launch --compartment-id $COMPARTMENT_ID --availability-domain $AD --subnet-id $SUBNET_ID --image-id $IMAGE_ID --shape $SHAPE --shape-config '{"memoryInGBs": 2.0, "ocpus": 1.0}' --user-data-file $CLOUD_INIT_FILE_LOCATION)
    else
        echo "Skipping: The number of pending jobs $CURRENT_NUMBER_OF_PENDING_JOBS is not higher than the threshold of $MAXIMUM_NUMBER_OF_PENDING_JOBS_THRESHOLD"
fi

# DELETING INSTANCES
# Find idle runners and delete them if they are not currently running any job and have been idle for $RUNNER_IDLE_TIME_THRESHOLD seconds
RUNNER_IDS=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/runners?type=project_type" | jq '.[].id')

for id in $RUNNER_IDS
do
    NUMBER_OF_RUNNING_JOBS=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/runners/$id/jobs?status=running" | jq '. | length')
    CURRENT_NUMBER_OF_RUNNERS=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/runners?type=project_type" | jq '.[].id' | wc -l)
    RUNNER_CONTACTED_AT=$(date -d "$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/runners/$id" | jq -r '."contacted_at"')" +%s)
    CURRENT_TIME=$(date +%s)
    RUNNER_IDLE_TIME=$((CURRENT_TIME - RUNNER_CONTACTED_AT))
    
    if [ $NUMBER_OF_RUNNING_JOBS -eq 0 ] && [ $RUNNER_IDLE_TIME -gt $RUNNER_IDLE_TIME_THRESHOLD ] && [ $CURRENT_NUMBER_OF_RUNNERS -gt $MINIMUM_NUMBER_OF_RUNNERS ]
    then
        echo "Scaling: Runner $id is not currently running any jobs, have been idle more than the threshold, deleting the instance"
        RUNNER_NAME=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/runners/$id" | jq -r '.description')
        INSTANCE_TO_DELETE=$(oci compute instance list --compartment-id $COMPARTMENT_ID | jq -r --arg RUNNER_NAME "$RUNNER_NAME" '.data[] | select(."display-name"==$RUNNER_NAME) | .id')
        curl --request DELETE --header "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" "$GITLAB_URL/api/v4/runners/$id"
        oci compute instance terminate --instance-id $INSTANCE_TO_DELETE --force
    else
        echo "Skipping: Runner $id is either currently running jobs or haven't been idle long enough"
    fi
done
