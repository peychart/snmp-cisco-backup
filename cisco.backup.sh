#!/bin/bash
# Phil-20140623
# cf.: http://ocean-indien.labo-cisco.com/sauvegarde-dequipements-reseau-avec-snmp/
#
MYNAME=${MYNAME:="cisco.backup.sh"}
postfix=${postfix:="conf"}
community=${community:="community_name"}
tftp_server=${tftp_server:="$(ip addr show dev $(ip route list match 0.0.0.0 | awk 'NR==1 {print $5}') | awk 'NR==3 {print $2}' | cut -d '/' -f1)"}
tftp_dir=${tftp_dir:="/tftpboot"}
SNMPSET=$(which snmpset); [ -z "$SNMPSET" ] && echo "$MYNAME: cmd \"snmpset\" not found..." >&2 && exit 1
MYTMP="/tmp/.$MYNAME.$(date +%Y%m%d.%H%M%S)"
trap "rm -f $MYTMP" 0 1 2 3 5

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

getNewCiscoConfig() { #syntaxe: $0 ip filename
 [ $# -ne 2 -o -z "$(echo $1| egrep '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')" ] && return 1
 cp -f $tftp_dir/$2 $MYTMP; chmod 666 $tftp_dir/$2 || return 2
 n=$(expr $(date +%S) + 1)
 snmpSet ""                                           $1 1.3.6.1.4.1.9.9.96.1.1.1.1.2.$n  integer 1
 snmpSet "[$1]: source file-type = running-config"    $1 1.3.6.1.4.1.9.9.96.1.1.1.1.3.$n  integer 4
 snmpSet "[$1]: destination file-type = network file" $1 1.3.6.1.4.1.9.9.96.1.1.1.1.4.$n  integer 1
 snmpSet "[$1]: tftp server address: $tftp_server"    $1 1.3.6.1.4.1.9.9.96.1.1.1.1.5.$n  address $tftp_server
 snmpSet "[$1]: destination filename: $2"             $1 1.3.6.1.4.1.9.9.96.1.1.1.1.6.$n  string $2
 snmpSet "[$1]: backup done..."                       $1 1.3.6.1.4.1.9.9.96.1.1.1.1.14.$n integer 1
 snmpSet "[$1]: clear the row entry"                  $1 1.3.6.1.4.1.9.9.96.1.1.1.1.14.$n integer 6
 [ -s $tftp_dir/$2 ] && ! cmp -s $tftp_dir/$2 $MYTMP
}

getNewHpConfig() { #syntaxe: $0 ip filename
 [ $# -ne 2 -o -z "$(echo $1| egrep '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')" ] && return 1
 cp -f $tftp_dir/$2 $MYTMP; chmod 666 $tftp_dir/$2 || return 2
 snmpSet "[$1]: Set tftp SNMPv2 OID to 2"             $1 1.3.6.1.4.1.11.2.14.11.5.1.7.1.5.6.0 integer 2
 echo "get running-config $tftp_dir/$2"| tftp $1 >/dev/null
 snmpSet "[$1]: Reset OID to disable tftp"            $1 1.3.6.1.4.1.11.2.14.11.5.1.7.1.5.6.0 integer 1
 [ -s $tftp_dir/$2 ] && ! cmp -s $tftp_dir/$2 $MYTMP
}

printhelp() {
 echo "syntaxe:" >&2
 echo "         $MYNAME [ -d 'tftp_dir' ] [ -c 'rw_community' ]" >&2
 echo "      or" >&2
 echo "         $MYNAME [ -d 'tftp_dir' ] --setupfrom 'dir_list_of_devices'" >&2
 echo "      or" >&2
 echo "         $MYNAME [ -d 'tftp_dir' ] --iptables" >&2
 echo "" >&2
 echo "  Need cisco config: " >&2
 echo "      snmp-server community 'rw_community' RW" >&2
 echo "      snmp-server host 'TFTPD_IP_address' version 2c 'rw_community' config" >&2
 echo "" >&2
 echo "  Need hp config: " >&2
 echo "      snmp-server community 'rw_community' unrestricted" >&2
 echo "" >&2
}

printIptables() { # syntaxe: $0 ipAddress(es)...
 for ip in $*; do
  echo "-A INPUT -p snmp -s $ip -j ACCEPT"
 done
}

# *********************************************************************
# MAIN:
# Analyse des arguments:
opt=""; n=$#; while [ $# -ne 0 ]; do
 case $1 in
  "--help"|"-h")	printhelp; [ $n -ne 1 ] && exit 1; exit 0;;
  "--iptables"|"-i")	shift; opt=iptables;;
  "--setupfrom"|"-s")	shift; opt=$1; shift; [ -z "$opt" ] && printhelp && exit 1;;
  "-d")			shift; tftp_dir=$1;  shift; [ -z "$tftp_dir" ]  && printhelp && exit 1;;
  "-c")			shift; community=$1; shift; [ -z "$community" ] && printhelp && exit 1;;
  *)			printhelp; exit 1;;
 esac
done

case "$opt" in
 ""|"iptables")
  for i in $(ls $tftp_dir| egrep "\.${postfix}$"); do
   [ -z "$(echo $i| sed -e 's/^.*\.//g')" ] && continue
   ip=$(echo $i| sed -e "s/^[^.]*\.//" -e "s/\.${postfix}$//")
   ip=$(getIp $ip)
   [ -z "$ip" ] && echo "Cannot find address of: $i..." >&2 && continue

   if [ -z "$opt" ]; then	# Do the backups from $tftp_dir/<cisco/hp>.<domain_name>.$postfix:
    case "$(echo $i| cut -d'.' -f1)" in
     "cisco")
      getNewCiscoConfig $ip $i && echo $i ;;
     "hp")
      getNewHpConfig $ip $i && echo $i ;;
    esac

   else			# iptables generation:
    printIptables $ip
   fi
  done;;
 *)				# Restore the list of backups in $tftp_dir:
  for i in $(ls $opt); do
   newone=$(echo $i| sed -e "s/^\(.*\..*\.$postfix\).*/\1/")
   [ ! -f $tftp_dir/$newone ] \
    && (umask 000; [ -f $tftp_dir/$newone ] || >$tftp_dir/$newone) \
    && echo "$tftp_dir/$newone backup settled..."
  done
  ;;
esac
exit 0

