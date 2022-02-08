#!/bin/bash

if [ "$#" != "1" ]; then
    echo "An org must be supplied as the first argument"
    exit 1
fi

curl -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"$1\"}" http://$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD@localhost:3000/api/orgs