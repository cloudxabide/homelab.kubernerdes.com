#!/bin/bash

EXISTING_VERSION=v1.8.1
NEW_VERSION=v1.8.2
ENVIRONMENT=community

# Create the "create" file (1 host)
#
sed "s/${EXISTING_VERSION}/${NEW_VERSION}/g" config-create-nuc-01-$ENVIRONMENT-$EXISTING_VERSION.yaml > config-create-nuc-01-$ENVIRONMENT-$NEW_VERSION.yaml

# Create the "join" file(s) (x number of hosts)
for HOST in  2 3
do
  OLD_FILE="config-join-nuc-0${HOST}-${ENVIRONMENT}-${EXISTING_VERSION}.yaml"
  NEW_FILE="config-join-nuc-0${HOST}-${ENVIRONMENT}-${NEW_VERSION}.yaml"
  sed "s/${EXISTING_VERSION}/${NEW_VERSION}/g" "$OLD_FILE" > "$NEW_FILE"
done

exit 0

