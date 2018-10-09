#!/bin/sh

echo "ASD package run"

OPTIONS=e:l:n:m:i:p:
LONGOPTS=etcdip:,svc_label:,svc_idx:,mode:,ip:,port:

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$PARSED"

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

./start.sh $ETCDIP $SVCLABEL $SVCIDX $MODE $IP $PORT
tail -f /dev/null
