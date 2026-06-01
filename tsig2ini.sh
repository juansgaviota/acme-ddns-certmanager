#!/bin/bash
#
# Tool to parse tsig-keygen generated files and convert into .ini file
# <C> 2026 Juann Antonio Martínez <juanantonio.martinez@upm.es>
#
# Usage: tsig2ini.sh dnsserver [keyfile [inifile]]
#   if "keyfile" is not given, read data from stdin
#   if "inifile" is not declared, send output to stdout
#

usage () {
    echo "$0" usage:
    echo "    tsig2ini.sh dnsserver [keyfile [inifile]]"
    echo "    dnsserver: ip address (not fqdn) of DNS Server"
    echo "    keyfile: tsig-keygen generated file (or stdin)"
    echo "    inifile: certbot compatible .ini data format"
    echo ""
}

infile="$2"
outfile="$3"
# comprobamos argumentos
[ -z "$3" ] && outfile="/dev/stdout"
[ -z "$2" ] && infile="/dev/stdin"
[ -z "$1" ] && ( usage; exit 1; )

# comprobamos que el servidor venga en formato ipv4
ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
if [[ ! $1 =~ $ip_regex ]]; then
    echo "$1 must be an ipv4 address"
    usage
    exit 1
fi
# extraemos nombre, algoritmo y clave
data=( $(sed -e 's/;//g' "${infile}" | awk '
    BEGIN { key=""; algorithm=""; secret=""; } 
    /key/{ gsub( /"/,"",$2); key=$2;}
    /algorithm/ { algorithm=$2; }
    /secret/ { secret=$2}
    END { printf ("%s\n\"%s\"\n%s\n",key,algorithm,secret); }
'))

cat << __EOF >"${outfile}"
[${data[0]}]
# Target DNS server (IPv4 or IPv6 address, not a hostname)
dns_rfc2136_server = ${1}
# Target DNS port
dns_rfc2136_port = 53
# TSIG key name
dns_rfc2136_name = "${data[0]}"
# TSIG key secret (base64 encoded)
dns_rfc2136_secret = ${data[2]}
# TSIG key algorithm
dns_rfc2136_algorithm = ${data[1]}
# TSIG sign SOA query (optional, default: false)
dns_rfc2136_sign_query = false
__EOF