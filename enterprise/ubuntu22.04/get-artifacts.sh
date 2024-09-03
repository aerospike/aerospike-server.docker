#!/bin/bash

CLIENT_CLONE_URL=$1
CLIENT_CLONE_REV=$3
BUILD_NAME=$2
BUILD_LABEL=$4

REPO=$(echo $CLIENT_CLONE_URL | cut -d':' -f2)

ARCH=`uname -m`
if [[ $ARCH == *"aarch64"* ]]; then
	BUILDCTL_DOWNLOAD="http://build.browser.qe.aerospike.com/citrusleaf/qe.go/3.3.0-52-gd66bd4b/build/1.17/default/artifacts/buildctl.aarch64.linux"
	BUILDCTL="buildctl.aarch64.linux"
else
	BUILDCTL_DOWNLOAD="http://build.browser.qe.aerospike.com/citrusleaf/qe.go/3.3.0-52-gd66bd4b/build/1.17/default/artifacts/buildctl.linux"
	BUILDCTL="buildctl.linux"
fi

if [ ! -f $BUILDCTL ]; then
	curl -O -f $BUILDCTL_DOWNLOAD
	chmod 700 $BUILDCTL
fi

echo "$BUILDCTL rev --repo $REPO --ref $CLIENT_CLONE_REV --no-trunc "
BUILD=$(./$BUILDCTL rev --repo $REPO --ref $CLIENT_CLONE_REV --no-trunc | sed -n 2p | awk '{print $3}')

URL_BASE="http://build.browser.qe.aerospike.com"
URL="$URL_BASE/$REPO/$BUILD/build/$BUILD_NAME/$BUILD_LABEL/artifacts/"
echo "$URL"
ARTIFACT_LINKS=$(curl -s $URL | sed -n 's/.*href="\([^"]*\).*/\1/p')
LOCAL_ARTIFACTS="artifacts"
mkdir -p $LOCAL_ARTIFACTS
for ARTIFACT_LINK in $ARTIFACT_LINKS; do
	ARTIFACT_URL=$URL_BASE$ARTIFACT_LINK
	printf "$ARTIFACT_URL\n"
	(cd $LOCAL_ARTIFACTS && curl -O -f $ARTIFACT_URL)
done    
ls -lat $LOCAL_ARTIFACTS