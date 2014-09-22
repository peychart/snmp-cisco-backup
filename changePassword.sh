#!/bin/bash
# Phil-201400922
# cf.: https://supportforums.cisco.com/discussion/10883606/password-recovery-snmp
#
MYNAME=${MYNAME:="changePassword.sh"}
community=${community:="community_name"}
tftp_server=${tftp_server:="$(ip addr show dev $(ip route list match 0.0.0.0 | awk 'NR==1 {print $5}') | awk 'NR==3 {print $2}' | cut -d '/' -f1)"}
tftp_dir=${tftp_dir:="/tftpboot"}
SNMPSET=$(which snmpset); [ -z "$SNMPSET" ] && echo "$MYNAME: cmd \"snmpset\" not found..." >&2 && exit 1
MYTMP="/tmp/.$MYNAME.$(date +%Y%m%d.%H%M%S)"
trap 'rm -f $MYTMP' 0 1 2 3 5

snmpSet() {
 local err=$1; shift
 $SNMPSET -v 1 -c $community $* >/dev/null && sleep 1
 [ $? -ne 0 ] && (echo "^ ERROR ON $err"; echo) >&2 && return 1
}

getIp() {
 [ $# -ne 1 ] && return 1
 echo $1| egrep -s '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
  || host $1| tail -1| grep -sv ' not found:'| cut -d' ' -f4
}

printhelp() {
 echo "syntaxe:" >&2
 echo "         $MYNAME [ -d 'tftp_dir' ] [ -c 'rw_community' ]" >&2
 echo "" >&2
 echo "  Need cisco config: " >&2
 echo "      snmp-server community 'rw_community' RW" >&2
 echo "      snmp-server host 'TFTPD_IP_address' version 2c 'rw_community' config" >&2
 echo "" >&2
 echo "  Need hp config: " >&2
 echo "      snmp-server community 'rw_community' unrestricted" >&2
 echo "" >&2
}

# *********************************************************************
# MAIN:
# Analyse des arguments:
opt=""; n=$#; while [ $# -ne 0 ]; do
 case $1 in
  "--help"|"-h")        printhelp; [ $n -ne 1 ] && exit 1; exit 0;;
  "-d")                 shift; tftp_dir=$1;  shift; [ -z "$tftp_dir" ]  && printhelp && exit 1;;
  "-c")                 shift; community=$1; shift; [ -z "$community" ] && printhelp && exit 1;;
  *)                    [ $# -eq 1 ] && break; printhelp; exit 1;;
 esac
done

IP=$(getIp $1)
[ -z "$IP" ] && printhelp && exit 1

MYTMP="$tftp_dir/.$MYNAME.$(date +%Y%m%d.%H%M%S)"
(echo "username root secret 0 toto"; echo end) >$MYTMP && chmod 666 $MYTMP

snmpSet "Value 5 for createAndWait"                 $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.14.222 i 5
snmpSet "Use of TFTP to transfert the config"       $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.2.222  i 1
snmpSet "To specify that we want to copy a file"    $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.3.222  i 1
snmpSet "The destination will be the runningConfig" $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.4.222  i 4
snmpSet "IP addr where the TFTP service is running" $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.5.222  a $tftp_server
snmpSet "The name of the file where the data is"    $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.6.222  s "$MYTMP"
snmpSet "Activate the row"                          $IP 1.3.6.1.4.1.9.9.96.1.1.1.1.14.222 i 1

