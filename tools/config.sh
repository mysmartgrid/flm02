#!/bin/bash

# script to flash the flukso

# flash command
AP51FLASH=./ap51-flash

# kernel
ATHEROS_KERNEL=openwrt-atheros-vmlinux-jswizard.lzma

# root image
#ATHEROS_IMAGE=openwrt-atheros-root-jswizard.squashfs
ATHEROS_IMAGE=openwrt-atheros-root-no_wizard.squashfs

# device
DEVICE=eth0

# WebAPI Url 
URL="http://192.168.255.1/cgi-bin/luci/"
URL_W="${URL}/welcome"
URL_S="${URL}/sensor"
URL_R="${URL}/registration"

#
verbose=0
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

    # wait for flukso to reboot
    sleep 30
    ifconfig ${DEVICE} 192.168.255.11

    # check if web-api is running
    c=1
    max=10
    while [ ${c} -le ${max} ];
    do
	echo "Test ${c}/${max}; call returned: $rc"
	sleep 5
	c=`expr $c + 1`
	curl --head --url ${URL_W}
	rc=$?
	if [ ${rc} -eq 0 ]; then
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
  if [ "${verbose}" = "1" ]; then
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
    local answer=$1
    local n="json"
    k=`echo ${answer} | sed -e 's%{%{ %g' -e 's%:%: %g' -e 's%,%, %g' -e 's%}% }%g'`
    echo "================ split ==================="
    verbose=0
    dummy=`echo ${answer} | tokenize | parse`
    for i in ${dummy}
    do
      eval "$i"
      echo "line:  $i"
    done
}

## send a curl call to flusko
flukso_luci_send() {
    local auth_url=$1
    local post=$2
    echo curl -X POST -d ${post} $auth_url
    answer=`curl -X POST -d "${post}" $auth_url 2> /dev/null`
    echo $answer
    json_split ${answer}
}


flukso_login() {
    echo "Flukso login"
    local auth_url="${URL}rpc/auth"
    local post='{"method": "login", "params": ["root", "root"], "id": 100}'
    flukso_luci_send ${auth_url} "${post}"

    #json_authkey=`echo ${answer} | tokenize | parse`
    json_authkey=${json_result}
    echo "Key: ${json_authkey}"
# answer has the form
#{"id":100,"result":"8552914869c03c730594841636897987","error":null}
}


flukso_uci() {
    local authkey=$1
    echo "Flukso System Values"
    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    local post='{"method": "foreach", "params": ["system", "system"], "id": 100}'
#    local post='{"method": "foreach", "params": ["wireless", "wifi-iface"], "id": 100}'
    flukso_luci_send ${auth_url} "${post}"
}

flukso_reboot() {
    local authkey=$1
    echo "Flukso reboot flukso"
    local auth_url="${URL}/rpc/sys?auth=${authkey}"
    local post='{"method": "reboot", "id": 100}'
    flukso_luci_send "${auth_url}" "${post}"
}

flukso_exec() {
    local authkey=$1
    local auth_url="${URL}/rpc/sys?auth=${authkey}"
    local post='{"method": "exec", "params": ["uci set ntpclient.@ntpserver[0].hostname=172.18.25.254"], "id": 100}'
    flukso_luci_send ${auth_url} "${post}"
    flukso_uci_commit ${authkey} "ntpclient"
}

flukso_sys_date() {
    local authkey=$1
    echo "Flukso SYS Set Date"
#    local auth_url="${URL}/rpc/sys?auth=${authkey}"
    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    d=`date +%Y%m%d%H%M`
#    local post='{"method": "call", "params": ["date", "$d"], "id": 100}'
#    local post='{"method": "exec", "params": ["date"], "id": 100}'
#    local post='{"method": "exec", "params": ["uci", "set", "system.@system[0].firstboot='0'"], "id": 100}'
#    local post='{"method": "exec", "params": ["uci", "commit"], "id": 100}'
#   local post='{"params": ["system", "system[0]", "firstboot"], "id": 100, "method": "get"}'
   local post='{"method": "get", "params": [ "system", "@system[0]", "device" ], "id": null}'
    local post='{"method": "set", "params": [ "system", "@system[0]", "firstboot", "1"], "id": null}'
    local post='{"method": "set", "params": [ "network", "lan", "dns", "172.17.0.1"], "id": null}'

## OK - works
#    local post='{"jsonrpc": "2.0", "method": "net.arptable", "id": null }'
#    local post='{"jsonrpc": "2.0", "method": "user.setpasswd", "params": [ "root", "root" ], "id": null }'
    flukso_luci_send ${auth_url} "${post}"
}

flukso_uci_set_config() {
    local authkey=$1
    local params=$2
    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    local post='{"method": "set", "params": [ '${params}' ], "id": 100}'
    flukso_luci_send "${auth_url}" "${post}"
}

flukso_uci_tset_config() {
    local authkey=$1
    local config=$2
    local section=$3
    local params=$4

    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    local post='{"method": "tset", "params": [ "'${config}'", "'${section}'", {'${params}'} ], "id": 100}'

# "tset", '["network", "lan", ' + JSON.stringify({"ifname": "eth0", "ipaddr": "192.168.255.1", "netmask": "255.255.255.0", "proto": "static"}) + ']'
    flukso_luci_send "${auth_url}" "${post}"
}

flukso_uci_commit() {
    local authkey=$1
    local params=$2
    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    local post='{"method": "commit", "params": [ "'${params}'" ], "id": null}'
    flukso_luci_send ${auth_url} "${post}"
}

flukso_uci_config1() {
    local authkey=$1
    flukso_uci_tset_config ${authkey} "network" "lan" '"dns": "192.168.255.254", "gateway": "192.168.255.31"'
#    flukso_uci_tset_config ${authkey} "network" "lan" '"dns": "172.17.0.1", "gateway": "192.168.255.11"'
#    flukso_uci_set_config ${authkey} '"network", "lan", "gateway", "192.168.255.31"'
    flukso_uci_commit ${authkey} "network"
    flukso_uci_tset_config ${authkey} "flukso" "daemon" \
	'"wan_base_url": "https://dev3-api.mysmartgrid.de:8443/", "upgrade_url": "https://dev3-www.mysmartgrid.de/files/upgrade/"'
    flukso_uci_commit ${authkey} "flukso"
    flukso_exec ${authkey}
}

flukso_uci_sensor() {
    local authkey=$1
    echo "Flukso UCI System Values"
    local auth_url="${URL}/rpc/uci?auth=${authkey}"
    local post='{"method": "foreach", "params": ["flukso", "sensor", "1"], "id": 100}'
    ##local post='{"method": "get", "params": ["flukso", "1"], "id": 100}'
    echo curl -X POST -d ${post} $auth_url
    answer=`curl -X POST -d "${post}" $auth_url 2> /dev/null`
    echo $answer
    json_split ${answer}
}

##### MAIN
#flash_flukso
#flukso_alive
flukso_login
#flukso_uci ${json_authkey}
#flukso_uci_sensor ${json_authkey}
# flukso_sys_date ${json_authkey}
flukso_uci_config1 ${json_authkey}
#flukso_reboot ${json_authkey}

echo "Flusko is running"
echo "${flukso_serial};${install_date};${json_result_device};${json_result_version};${json_result_key}"
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

