#!/bin/bash
 
execdir=$(dirname $(readlink -f $0))

DEST=.
JOBS=1

CLIENT=CURL

while getopts "aco:j:" o; do
  case $o in
    o) DEST=$OPTARG ;;
    j) JOBS=$OPTARG ;;
    a) CLIENT=ASCP  ;;
    c) CLIENT=CURL  ;;
  esac
done
shift $((OPTIND-1))
inputs=( $* )

function fetch_ascp {
  date
  du -k TEST.1

  PARASCP_CORES=$JOBS ${execdir}/ascppar.sh -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh \
	-G 8M -T -Ql ${JOBS}g -Z 8232 -- -L/tmp --mode recv --host 130.14.250.13 --user anonftp \
	--file-list $1 $2

  date
  du -k TEST.1
}

function fetch_curl {
  ${execdir}/pcurl.py -i $1 -o $2 -j $JOBS
}

for (( i=0; i<${#inputs[@]}; i++)); do
  destdir=$(readlink -f $(printf "%s/OUT.%02d" $DEST $i))
  mkdir -p $destdir
  if [[ $CLIENT == "CURL" ]]; then
    fetch_curl ${inputs[$i]} $destdir
  else
    fetch_ascp ${inputs[$i]} $destdir
  fi
done


