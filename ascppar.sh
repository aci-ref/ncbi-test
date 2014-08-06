#!/bin/bash
# ascppar-- parallel ascp initiator

function usage
{
    cat 1>&2 <<'EOF'
  $PARASCP_LOCALS: space-separated list of hostnames on which to run clients
     (default "localhost")
  $PARASCP_REMOTES: corresponding list of hostnames of servers to connect to
     (no default: error if not set)
  $PARASCP_CORES: number of processes to run on each host (default 1)
  $PARASCP_REMSH: command to run a process on a remote node (default "ssh")
  $PARASCP_REMUSER: user name to run remote (default $USER)
  $PARASCP_PASS: password for the remote user (default empty)
  $PARASCP_TRIES: number of attempts at transfer before failure (default 3)
  $PARASCP_TAG: tag passed to trapd
  $PARASCP_TAG_DISABLE: Disable generation of tag.
  
    ascppar [ascp options] -- :src [ :src ... ] dest
    ascppar [ascp options] -- src [ src ... ] :dest

  Rate arguments (e.g. to "-l", "-m") are aggregate, for the whole transfer.
  Prefix each remote argument with ":", with no hostname or username.

  You may pass env variables to ascppar by using '-f <config file>' option.
  for example:
    
    ascppar -f ascppar.conf [ascp options] ... 

  Environment variables passed in this way should be in bash key=value format.

EOF
  exit 1
}

: ${PARASCP_CORES:=2}
: ${PARASCP_LOCALS:=localhost}
: ${PARASCP_REMSH:=ssh}
: ${PARASCP_REMUSER:=$USER}
: ${PARASCP_TRIES:=3}
: ${PARASCP_ASCP:=ascp} 

if [ -z "$PARASCP_TAG_DISABLE" ]; then 
  openssl_binary=/opt/aspera/bin/openssl

  if [ ! -x "$openssl_binary" ]; then
    openssl_binary=`pwd`/bin/openssl
    if [ ! -x "$openssl_binary" ]; then
      openssl_binary=`which openssl`
    fi
  fi 

  if [ ! -x "$openssl_binary" ]; then
    echo "OpenSSL library binary not found, please add openssl to your path."
    exit
  fi

  if [ x"${PARASCP_TAG:-}" == x ]; then
    PARASCP_TAG=`dd if=/dev/urandom bs=16 count=1 2> /dev/null | ${openssl_binary} enc -base64 | sed 's/==//'`
  fi

  tag_name="--tags={\"aspera\":{\"xfer_id\":\"${PARASCP_TAG}\"}}"
fi



if [ ${#locals[*]} != ${#remotes[*]} ]; then
  echo  1>&2
  echo 'error: number of hosts in $PARASCP_LOCALS must match $PARASCP_REMOTES' 1>&2
  echo $PARASCP_LOCAL $PARASCP_REMOTES
  echo  1>&2
  usage
fi


declare -a args=("-q")
declare -i argix=1
while getopts QTdprk:f:l:m:u:i:Z:X:g:G:L:R:S:e:O:P: arg; do
    case "$arg" in
     '?') usage
          ;;
     l|m) rate=${OPTARG%[kKmMgGpP%]}
          case "$OPTARG" in 
            *k|*K|[0-9])  CALC_RATE=$rate 
                ;;
            *m|*M)     CALC_RATE=`expr $rate \* 1000`
                ;;
            *g|*G)     CALC_RATE=`expr $rate \* 1000000`
                ;;
            *) echo "error: percentage rates not allowed" 1>&2; usage;;
          esac
          OPTARG="__PAR_SKIP__"
          ;;

          
     f)   . $OPTARG  # Read config from file
          OPTARG="__PAR_SKIP__"
          ;;

    esac
    case "$OPTARG" in
      "__PAR_SKIP__")
          ;;
      "") args[$argix]="-$arg"
          ((++argix))
          ;;
       *) args[$argix]="-$arg";
          args[$argix+1]="$OPTARG";
          ((argix+=2))
          ;;
    esac
    argix=argix+1
done

if [ x"${PARASCP_REMOTES:-}" == x ]; then
  PARASCP_REMOTES=__SKIP_PARASCP_REMOTES__
  PARASCP_LOCAL="127.0.0.1"
fi

# extract command-line arguments into an array, respecting quoting.
# explode remaining args, hostnames into arrays
declare -a locals=($PARASCP_LOCALS)
declare -a remotes=($PARASCP_REMOTES)
numhosts=${#remotes[@]} 
if [ "${numhosts}" -lt 1 ]; then
  numhosts=1
fi
((total=numhosts*PARASCP_CORES))

((CALC_RATE=CALC_RATE/total))

if [ "${CALC_RATE}" -gt 1 ]; then
  args[$argix]="-l"
  ((argix+=1))
  args[$argix]=${CALC_RATE}
  ((argix+=1))
fi



declare -a fileargs=("$@")
declare -a joblist=()

logger -plocal0.info ascppar: spawning transfer jobs

for ((node=0; node < ${#remotes[*]}; ++node)); do
    if [ "${remotes[$node]}" == "__SKIP_PARASCP_REMOTES__" ]; then 
      # If PARASCP_REMOTES not specified, do nothing but fill in fargs
      typeset -a fargs=();
      for ((rem=$OPTIND-1; rem < ${#fileargs[*]}; ++rem)); do
          ((ix=rem-(OPTIND-1) ))
          case "${fileargs[rem]}" in
              *)  fargs[$ix]="${fileargs[rem]}" ;;
          esac
      done
    else
      remhost="${remotes[$node]}"
      # paste hostname in place of leading ":" on file args.
      typeset -a fargs=();
      for ((rem=$OPTIND-1; rem < ${#fileargs[*]}; ++rem)); do
          ((ix=rem-(OPTIND-1) ))
          case "${fileargs[rem]}" in
              :*) fargs[$ix]="$PARASCP_REMUSER@$remhost:${fileargs[rem]#:}" ;;
              *)  fargs[$ix]="${fileargs[rem]}" ;;
          esac
      done
    fi 

    for ((core=0; core < PARASCP_CORES; ++core)); do
        clustarg="$((node*PARASCP_CORES+(core+1))):$total"
        (
            run=0
            while (( run < PARASCP_TRIES )); do
                    
                logger -plocal0.info ascppar: starting transfer $clustarg on ${locals[node]}, attempt ${run}/${PARASCP_TRIES} 

                case ${locals[node]} in

                localhost|127.0.0.1)
                    # run it here
                    #echo ${PARASCP_ASCP} -C $clustarg $tag_name "${args[@]}" "${fargs[@]}" \&
                    ASPERA_SCP_PASS=${PARASCP_PASS}  \
                        ${PARASCP_ASCP} \
                            -C $clustarg $tag_name "${args[@]}" "${fargs[@]}" &&
                                break
                    ;;
                *)
                    # ssh there to run it
                    ${PARASCP_REMSH} ${locals[node]} \
                        ASPERA_SCP_PASS=${PARASCP_PASS} \
                        ${PARASCP_ASCP} \
                            -C $clustarg $tag_name "${args[@]}" "${fargs[@]}" &&
                                break
                    ;;
                esac

                ((++run))
            done
            if (( run == PARASCP_TRIES )); then
                echo \
"error: transfer $clustarg to host $node failed in $PARASCP_TRIES attempts" 1>&2
                logger -plocal0.info "ascppar: error - transfer $clustarg to host $node failed in $PARASCP_TRIES attempts"
                exit 1
            fi
        )&
        joblist[node*PARASCP_CORES+core]=$!
#        nodelist[node*PARASCP_CORES+core]=$node
#        corelist[node*PARASCP_CORES+core]=$core
    done;
done

logger -plocal0.info ascppar: spawned all transfer jobs - waiting for them to finish

declare -i fails=0
for job in ${joblist[@]}; do
     wait ${job[0]} || ((++fails))
done
 
if ((fails != 0)); then
    echo "error: $fails transfer jobs failed." 1&>2 
    logger -plocal0.info ascppar: $fails transfer jobs failed
    exit $fails
fi

logger -plocal0.info ascppar: all transfers completed successfully 

exit 0

