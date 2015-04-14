#!/bin/bash

# script to flash the flukso

# flash command
PREFIX="${PREFIX-flm02.2.9}"
AP51FLASH="${AP51FLASH-${PREFIX}/tools/ap51-flash}"
IMAGEPATH="${IMAGEPATH-${PREFIX}/bin/atheros}"
DEVICE="${DEVICE-eth0}"


# kernel
ATHEROS_KERNEL="${IMAGEPATH}/openwrt-atheros-vmlinux.lzma"

# root image
ATHEROS_IMAGE="${IMAGEPATH}/openwrt-atheros-root.squashfs"

# WebAPI Url 
URL="http://192.168.255.1/cgi-bin/luci/"
URL_W="${URL}/welcome"
URL_S="${URL}/sensor"
URL_R="${URL}/registration"

#
VERBOSE="${VERBOSE-0}"
flukso_serial=$1
install_date=`date +%Y%m%d`
logfile="flukso_install.log"

# flash flukso
flash_flukso() {
    ${AP51FLASH} ${DEVICE} ${ATHEROS_IMAGE} ${ATHEROS_KERNEL}
    rc=$?
    echo "ap51-flash returned: $rc".
}

flukso_alive() {
    echo "waiting  90sec for flukso to come up."
	read -t 90 -p "Waiting 90s for flukso to come up. (Press any key to continue immediatly)"

    # check if web-api is running
    c=1
    max=10
    while [ ${c} -le ${max} ];
    do
      echo "Test ${c}/${max};"
      sleep 5
      c=`expr $c + 1`
      flukso_login
      if [ "x${json_authkey}" != "x" ]; then
        echo "flusko_alive: \"${json_authkey}\""
        break
      fi
    done
    if [ ${c} -ge ${max} ]; then
      echo "Failed either to flash the flukso or the flukso is not coming up."
      rc=1
    else
      echo "Flukso is flashed and running"
      rc=0
    fi
}

throw () {
  echo "$*" >&2
  exit 1
}

tokenize () {
  local ESCAPE='(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
  local CHAR='[^[:cntrl:]"\\]'
  local STRING="\"$CHAR*($ESCAPE$CHAR*)*\""
  local NUMBER='-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?'
  local KEYWORD='null|false|true'
  local SPACE='[[:space:]]+'
  egrep -ao "$STRING|$NUMBER|$KEYWORD|$SPACE|." --color=never |
    egrep -v "^$SPACE$" # eat whitespace
}

parse_array () {
  local index=0
  local ary=''
  read -r token
  case "$token" in
    ']') ;;
    *)
      while :
      do
parse_value "$1" "$index"
        let index=$index+1
        ary="$ary""$value"
        read -r token
        case "$token" in
          ']') break ;;
          ',') ary="$ary," ;;
          *) throw "EXPECTED , or ] GOT ${token:-EOF}" ;;
        esac
read -r token
      done
      ;;
  esac
value=`printf '[%s]' $ary`
}

parse_object () {
  local key
  local obj=''
  read -r token
  case "$token" in
    '}') ;;
    *)
      while :
      do
case "$token" in
          '"'*'"') key=$token ;;
          *) throw "EXPECTED string GOT ${token:-EOF}" ;;
        esac
read -r token
        case "$token" in
          ':') ;;
          *) throw "EXPECTED : GOT ${token:-EOF}" ;;
        esac
read -r token
        parse_value "$1" "$key"
        obj="$obj$key:$value"
        read -r token
        case "$token" in
          '}') break ;;
          ',') obj="$obj," ;;
          *) throw "EXPECTED , or } GOT ${token:-EOF}" ;;
        esac
read -r token
      done
    ;;
  esac
  value=`printf '{%s}' "$obj"`
}

parse_value () {
  local jpath="${1:+$1,}$2"
  case "$token" in
    '{') parse_object "$jpath" ;;
    '[') parse_array "$jpath" ;;
    # At this point, the only valid single-character tokens are digits.
    ''|[^0-9]) throw "EXPECTED value GOT ${token:-EOF}" ;;
    *) value=$token ;;
  esac
  varname=`echo ${jpath} | sed -e 's%"%%g' -e 's%,0%_%g' -e 's%,%%g' -e 's%\.%%g'`
  if [ "${varname}" = "" ]; then
    varname="obj"
  fi
  dummy="json_${varname}=${value}"
  if [ "${VERBOSE}" = "1" ]; then
    #echo " ==== ${varname}"
    echo ${dummy}
    #printf "[%s]\t%s\n" "$jpath" "$value"
  fi
  main_result="${main_result} ${dummy}"
  eval "${dummy}"
}

parse () {
  main_result=""
  read -r token
  parse_value
  read -r token
  case "$token" in
    '') ;;
    *) throw "EXPECTED EOF GOT $token" ;;
  esac
  #echo "$json_result"
  echo "$main_result"
}


json_split() {
    local answer="$1"
    [ "${VERBOSE}" -gt 0 ] && echo "================ split ==================="
    if [ "${VERBOSE}" -gt 0 ]; then
        echo "${answer}" | tokenize
    fi
    dummy=`echo "${answer}" | tokenize | parse`
    for i in "${dummy}"
    do
      eval "$i"
      [ "${VERBOSE}" -gt 0 ] && echo "line:  $i"
    done
}

flukso_login() {
    echo "Flukso login"
    local auth_url="${URL}rpc/auth"
    local post='{"method": "login", "params": ["root", "root"], "id": 100}'
    # curl -X POST -d '{"method": "login", "params": ["root", "root"], "id": 100}' --url $auth_url
    echo curl -X POST -d "${post}" $auth_url
    local answer=`curl -X POST -d "${post}" $auth_url 2> /dev/null`
    local curl_res=$?

    #json_authkey=`echo ${answer} | tokenize | parse`
    if [ ${curl_res} -eq 0 -a "x${answer}" != "x" ]; then
        json_split "${answer}"
        if [ "x${json_result}" != "x" ]; then
            json_authkey="${json_result}"
            echo "Key: ${json_authkey}"
        fi
    fi

    if [ "x${json_authkey}" == "x" ]; then
        echo "Authentication failed: ${answer}"
    fi
# answer has the form
#{"id":100,"result":"8552914869c03c730594841636897987","error":null}
}

flukso_uci() {
    local authkey=$1
    echo "Flukso System Values"
    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    local post='{"method": "foreach", "params": ["system", "system"], "id": 101}'
    echo curl -X POST -d ${post} $auth_url
    answer=`curl -X POST -d "${post}" $auth_url 2> /dev/null`
    json_split ${answer}
    flukso_device="${json_result_device}"
    flukso_version="${json_result_version}"
    flukso_key="${json_result_key}"

    if [ "x${flukso_serial}" != "x" ]; then
        local setserialpost="{\"method\": \"set\", \"params\": [\"system\", \"${json_result_name}\", \"serial\", \"${flukso_serial}\"], \"id\": 102}"
        echo curl -X POST -d "${setserialpost}" $auth_url
        answer=`curl -X POST -d "${setserialpost}" $auth_url 2> /dev/null`
        json_split "${answer}"
        [ "${VERBOSE}" -gt 0 ] && echo "${answer}"
        if [[ "${json_result}" != "true" ]]; then
            echo "Error setting serial: ${json_errormessage}"
        fi

        local commitserialpost='{"method": "commit", "params": ["system"], "id":103}'
        echo curl -X POST -d "${commitserialpost}" $auth_url
        answer=`curl -X POST -d "${commitserialpost}" $auth_url 2> /dev/null`
        json_split "${answer}"
        [ "${VERBOSE}" -gt 0 ] && echo "${answer}"
        if [[ "${json_result}" != "true" ]]; then
            echo "Error committing changes: ${json_errormessage}"
        fi
    fi
}

##### MAIN
flash_flukso
flukso_alive
if [ -z "${json_authkey}" ]; then
	echo "Authorization failed."
	exit 1
fi
flukso_uci ${json_authkey}

echo "Flusko is running"
echo "${flukso_serial};${install_date};${json_result_device};${json_result_version};${json_result_key}" | tee -a ${logfile}
exit ${rc}

#curl -X POST -d '{"method": "login", "params": ["root", "root"], "id": 100}' http://192.168.255.1/cgi-bin/luci/rpc/auth
#

#curl -X POST -d '{"method": "foreach", "params": ["system", "system"], "id": 100}' 'http://192.168.255.1/cgi-bin/luci/rpc/uci?auth=8552914869c03c730594841636897987'
#{"id":100,"result":[{".name":"cfg028d78",
#    ".anonymous":true,
#    "device":"27bb7c4032fcda89e86e4d6347a5b580",
#    "timezone":"UTC","firstboot":"0",".index":0,
#    "key":"5584c74f7d482fe5042fe907adfe7818",
#    "cronloglevel":"1","hostname":"flukso-27bb7c",
#    ".type":"system","version":"202"}],"error":null}

