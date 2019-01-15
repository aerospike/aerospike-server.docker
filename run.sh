#!/bin/sh

echo "ASD package run"

./start.sh $@

tail -f /dev/null
