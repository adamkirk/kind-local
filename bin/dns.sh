#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

IPV4_TARGET="127.0.0.1"
IPV6_TARGET="::1"
REQUIRED_HOSTS=$(kubectl get ingress --all-namespaces -o jsonpath='{.items[*].spec.rules[*].host}' | tr ' ' '\n' | uniq)

while read -r HOSTNAME; do 
	sudo $SCRIPT_DIR/hosts remove host $HOSTNAME 
done <<< "$REQUIRED_HOSTS";

while read -r HOSTNAME; do 
	sudo $SCRIPT_DIR/hosts add $IPV4_TARGET $HOSTNAME 
done <<< "$REQUIRED_HOSTS"

