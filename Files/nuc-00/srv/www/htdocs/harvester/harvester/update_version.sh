#!/bin/bash

# This creates new copies of the config-{create|join}*.yaml files
# how to run this: 
# ../update_version.sh
EXISTING_VERSION=v1.8.2
NEW_VERSION=v1.9.1
ENVIRONMENT=prime

# Create the "create" file (1 host)
#
sed "s/${EXISTING_VERSION}/${NEW_VERSION}/g" config-create-nuc-01-$ENVIRONMENT-$EXISTING_VERSION.yaml > config-create-nuc-01-$ENVIRONMENT-$NEW_VERSION.yaml

# Create the "join" file(s) (x number of hosts)
for HOST in  2 3 4 5 6
do
  OLD_FILE="config-join-nuc-0${HOST}-${ENVIRONMENT}-${EXISTING_VERSION}.yaml"
  NEW_FILE="config-join-nuc-0${HOST}-${ENVIRONMENT}-${NEW_VERSION}.yaml"
  sed "s/${EXISTING_VERSION}/${NEW_VERSION}/g" "$OLD_FILE" > "$NEW_FILE"
done

exit 0

