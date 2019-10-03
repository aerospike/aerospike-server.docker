#!/bin/sh

echo "ASD package start"
OPTIONS=e:l:n:m:i:p:h:y:d:r:
LONGOPTS=etcdip:,svc_label:,svc_idx:,mode:,ip:,port:,ha_port:,memory_size_gb:,disks:,migration_profile:

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$PARSED"

ETCDIP=""
SVCLABEL=""
SVCIDX=1
MODE=""
IP=""
PORT=""
HA_PORT=8000
MEMORY=10
DISKS=2
MIGRATION_PROFILE="lite"

while true ; do
      case $1 in
            -e|--etcdip)
                  echo "Setting etcd ip to [$2] !"
                  ETCDIP=$2
                  shift 2
                  ;;

            -l|--svc_label)
                  echo "Setting svc_label to [$2] !"
                  SVCLABEL=$2
                  shift 2
                  ;;

            -n|--svc_idx)
                  echo "Setting svc_idx to [$2] !"
                  SVCIDX=$2
                  shift 2
                  ;;

            -m|--mode)
                  echo "Setting mode to [$2] !"
                  MODE=$2
                  shift 2
                  ;;

            -i|--ip)
                  echo "Setting ip to [$2] !"
                  IP=$2
                  shift 2
                  ;;

            -p|--port)
                  echo "Setting port to [$2] !"
                  PORT=$2
                  shift 2
                  ;;

            -h|--ha_port)
                  echo "Setting ha_port to [$2] !"
                  HA_PORT=$2
                  shift 2
                  ;;

            -y|--memory_size_gb)
                  echo "Setting memory to [$2] !"
                  MEMORY=$2
                  shift 2
                  ;;

            -d|--disks)
                  echo "Setting disks to [$2] !"
                  DISKS=$2
                  shift 2
                  ;;

            -r|--migration_profile)
                  echo "Setting migration profile to [$2] !"
                  MIGRATION_PROFILE=$2
                  shift 2
                  ;;

            --)
                  shift
                  break
                  ;;

            *)
                  echo "Programming error"
                  exit 3
                  ;;
      esac
done

gunicorn -b 0.0.0.0:$HA_PORT --certfile=/etc/certs/server_certificate.pem --keyfile=/etc/certs/server_key.pem hyc_asd_mgr:app etcdip=$ETCDIP svc_label=$SVCLABEL svc_idx=$SVCIDX mode=$MODE ip=$IP port=$PORT memory=$MEMORY disks=$DISKS migration_profile=$MIGRATION_PROFILE
