#!/bin/bash
#
# Programa de gestión de certificados a través de CertBot
# usando el API ACME de harica.gr mediante Domain Validation
# 
#
Author="Juan Antonio Martínez <juanantonio.martinez@upm.es>"
Version="1.0 2026-05-27"
License="MIT (https://opensource.org/license/mit)"
#
# Notice:
# File lib_ini.sh is Copyright (c) 2023, Leandro Ferreira
# https://github.com/lsferreira42/bash-ini-parser

# Opciones para los comandos "ssh" y "scp" y "tar"
SSH="/usr/bin/ssh -n -q -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR "
SCP="/usr/bin/scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR "
# para ejecutar tar remoto con ssh necesitamos mantener abierto stdin
# TARSSH="/usr/bin/ssh -q -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR"

# Directories
CONFDIR="/etc/certmanager"
LIBDIR=/usr/local/lib/certmanager
DOCDIR=/usr/share/doc/certmanager
TMPDIR=/tmp/certmanager
LOGDIR=/var/log/certmanager

# Ini parser library script
# https://github.com/lsferreira42/bash-ini-parser
ini_parser=${LIBDIR}/lib_ini.sh

# Fichero .ini que contiene las credenciales de acceso a HARICA-ACME
acme_creds="${CONFDIR}/acme_creds.ini"

# Fichero .ini que contiene los datos de DDNS y de ubicacion para cada certificado
sites_info="${CONFDIR}/sites.ini"

# Fichero .ini que contiene las claves de acceso al servidor DNS para la validación ACME
ddns_keys="${CONFDIR}/ddns_keys.ini"

# directorio de ficheros temporales
tmp_dir="${TMPDIR}"
log_dir="${LOGDIR}"
# fichero de logs
log_file="${log_dir}/cert_manager.$$.log"
# fichero de bloqueo
lock_file=${tmp_dir}/certmanager.lock

# Valores por defecto
verbose=0	# show log in console
action=""	# Action to perform when this script is executed
user="default"  # user section in credentials file to retrieve data from
mailto=""	# on execution send log to provided mail address
install=0	# re-distribute new created certificates
enabled=1	# mark named site entry enabled/disabled

# variables relacionadas con las credenciales ACME EAB del fchero acme_creds
acme_kid="" 		# EAB user Key ID
acme_hmac_key=""	# HMAC key
acme_server=""		# remote URI to handle certificates
acme_email=""		# email to send notifications to

ddns_credentials=""	# seccion de configuracion DDNS en el fichero ddns_keys.ini
acme_credentials=""	# seccion de configuracion ACME EAB en el fichero acme_creds.ini

# datos de host y carpetas destino donde instalar el certificado
cert_host="" 		# host donde instalar el certificado
key_path="" 		# carpeta donde guardar la clave en el host destino
cert_path="" 		# donde guardar el certificado en el host destino
chain_path="" 		# donde guardar la cadena de certificados

# variables relacionadas con el certificado
cert_name="" 		# CommonName (CN). Debe ser una sección del sites_info
cert_alt_names=""	# SubjectAlternativeNames
cert_enabled="" 	# flag para procesar o no esta seccion del sites_info


# send extra info to log file
trace() {
	echo "$*" >>${log_file}
} 

# send message to log file. When verbose send also to console
log () {
	echo "$*" >>${log_file}
	[ ${verbose} -eq 1 ] && echo "$*" >&2
}

# send message to log file AND console
error() {
	echo "$*" >&2
	echo "$*" >>${log_file}
}

# parse sites ini file to get information from cert
#   $1 certificate CN name (section in ini file)
# returns:
#   0: ok
#   1: site not found
#   2: site is not enabled
#   3: missing data
parse_site () {
        trace "Enter parse_site( \"$1\" )"
	if [ ! -f "${sites_info}" ]; then
		error "DNS and certs destination info file '$sites_info' does not exist"
		return 1
	elif ! ini_validate "${sites_info}" ; then
		error "DNS and certs destination info '$sites_info' is not a valid .ini file"
		return 1
	elif ! ini_section_exists "${sites_info}" "$1" ; then
		error "Certificate '$1' is not declared in ${sites_info}"
		return 1
	fi
	# miramos si esta sección está habilitada para procesar o no el certificado. 
	# Si no lo está, no es un error, pero no se procesa
	cert_enabled=$(ini_read "${sites_info}" "$1" "cert_enabled" ) >&1
	if [ "${cert_enabled}" -ne 1 ];then
		log "Certificate \"$1\" is not enabled"
		return 2
	fi
	# Entrada habilitada. Leemos los valores por defecto
	ddns_credentials=$(ini_read "${sites_info}" "default" "ddns_credentials")
	acme_credentials=$(ini_read "${sites_info}" "default" "acme_credentials")
	key_path=$(ini_read "${sites_info}" "default" "key_path")
	cert_path=$(ini_read "${sites_info}" "default" "cert_path")
	chain_path=$(ini_read "${sites_info}" "default" "chain_path")

	# Leemos ahora los valores especificos del CN dado
	cert_host=$(ini_read "${sites_info}" "$1" "cert_host")
	# el nombre CN del certificado es el mismo que el de la sección
	cert_name="$1"
	cert_alt_names=$(ini_read "${sites_info}" "$1" "cert_alt_names")
	#
	# Ahora buscamos en la seccion solicitada
	# si estos valores no estan definidos, usamos los de por defecto
	#
	# nombre de la seccion donde buscar la dddns-key
    ddns_credentials=$(ini_get_or_default "${sites_info}" "$1" "ddns_credentials" "${ddns_credentials}")
	# credenciales ACME
	acme_credentials=$(ini_get_or_default "${sites_info}" "$1" "acme_credentials" "${acme_credentials}")
	# paths de instalación del certificado en el host destino
	key_path=$(ini_get_or_default "${sites_info}" "$1" "key_path" "${key_path}")
	cert_path=$(ini_get_or_default "${sites_info}" "$1" "cert_path" "${cert_path}")
	chain_path=$(ini_get_or_default "${sites_info}" "$1" "chain_path" "${chain_path}")

	# comprobamos que la clave ddns existan el fichero de credenciales ddns
	if ! ini_section_exists "${ddns_keys}" "${ddns_credentials}"; then
		error "Seccion de configuración DDNS \"$ddns_credentials}\" no existe"
		return 3
	fi
	# comprobamos si las credenciales acme EAB están declaradas en el fichero de credenciales
	if !  ini_section_exists "${acme_creds}" "${acme_credentials}"; then
		error "Seccion de configuración ACME \"$acme_credentials}\" no existe"
		return 3
	fi
	# por ultimo comprobamos que los paths de instalación estén declarados
	# pues son necesarios cuando cert_enabled=1
	if [ -z "${key_path}" ] || [ -z "${cert_path}" ] || [ -z "${chain_path}" ]; then
		error "Los directorios de instalación del certificado no están declarados"
		return 3
	fi
	# todo correcto. retornar OK
	return 0
}

# read and parse ACME EAB credentials .ini file
# $1: user section in the .ini file to read credentials from
parse_creds_file () {
    if [ ! -f "$acme_creds" ]; then
		error "ACME EAB credentials file '$acme_creds' does not exist" >&2
		exit 1
    elif ! ini_validate "$acme_creds" ; then
		# comprobamos si el fichero .ini es valido
		error "ACME EAB credentials '$acme_creds' is not a valid .ini file" >&2
		exit 1
    elif ! (ini_list_sections "$acme_creds" | grep -q "$user") ; then
		error "User '$user' is not declared in '$acme_creds'"
		exit 1;
    else
		# finalmente leemos credenciales
		acme_kid=$(ini_read "$acme_creds" "$user" "acme_kid")
		acme_hmac_key=$(ini_read "$acme_creds" "$user" "acme_hmac_key")
		acme_server=$(ini_read "$acme_creds" "$user" "acme_server")
		acme_email=$(ini_read "$acme_creds" "$user" "acme_email")
		# y comprobamos que esten declaradas
		if [ -z "$acme_kid" ] || [ -z "$acme_hmac_key" ] || [ -z "$acme_server" ] || [ -z "$acme_email" ]; then
			log "acme_kid: $acme_kid"
			log "acme_hmac_key: $acme_hmac_key"
			log "acme_server: $acme_server"
			log "acme_email: $acme_email"
			error "Incomplete ACME credentials data for user '$user'"
			exit 1
		fi
    fi 
}

# extract ddns info and store in temporary file
get_ddns_creds () {
	if [ ! -f "${ddns_keys}" ]; then
		error "DNS sites conf file \"${ddns_keys}\" does not exist" >&2
		exit 1
    elif ! ini_validate "${ddns_keys}" ; then
		# comprobamos si el fichero .ini es valido
		error "DNS sites conf file \"${ddns_keys}\"is not a valid .ini file" >&2
		exit 1
    elif ! (ini_list_sections "${ddns_keys}" | grep -q "${ddns_credentials}") ; then
		error "DNS section \"${ddns_credentials}\" is not declared in \"${ddns_keys}\""
		exit 1;
    else
		# finalmente procesamos los datos de la seccion
		ini_get_all "${ddns_keys}" "${ddns_credentials}"
	fi
	return 0
}

# install certificate in destination server
# if server host is not defined in sites .ini file, notice and ignore
# $1: certificate CN name (section in ini file)
install_certificate () {
        trace "Enter install_certificate( \"$1\" )"
	# parse site. on error notify and return
	if ! parse_site "$1"; then
		log "Install certificate into remote host disabled or not posible"
		return
	fi
	fromdir="/etc/letsencrypt/live/${1}/"
	${SCP} "${fromdir}/cert.pem" "${cert_host}":"${cert_path}/${1}_cert.pem"	
	${SCP} "${fromdir}/key.pem" "${cert_host}":"${key_path}/${1}_key.pem"
	${SCP} "${fromdir}/fullchain.pem" "${cert_host}":"${chain_path}/${1}_chain.pem"
	${SSH} "${cert_host}" update-ca-certificates
}

# remove certificate in destination server
# if server host is not defined in sites .ini file, notice and ignore
# $1 certificate CN name (section in ini file)
remove_certificate () {
	trace "Enter remove_certificate( '$1' )"
	# parse site. on error notify and return
	if ! parse_site "$1"; then
		log "Remove certificate in remote host disabled or not posible"
		return
	fi
	${SSH} "${cert_host}" rm -f "${cert_path}/${1}_cert.pem"
	${SSH} "${cert_host}" rm -f "${key_path}/${1}_key.pem"
	${SSH} "${cert_host}" rm -f "${chain_path}/${1}_chain.pem"
	${SSH} "${cert_host}" update-ca-certificates
}

# List existing certificates
do_list () {
	trace "Enter do_list()"
	certbot certificates \
		--logs_dir ${log_dir} \
		--server "${acme_server}" \
		--eab-kid "${acme_kid}" \
		--eab-hmac-key "${acme_hmac_key}" \
		--email "${acme_email}"
}

# Create/renew a certificate
# $1: certificate CN name (section in ini file)
do_create () {
	trace "Enter do_create( '$1' )"
	# parse sites ini file to retrieve certificate info
	parse_site "$1"
	[ -z "${cert_alt_names}" ] || cert_alt_names="-d ${cert_alt_names}"
	# extract ddns credentials from ddns_keys file
	ddns_temp="${tmp_dir}/ddns_credentials.$$.ini"
	get_ddns_creds > "${ddns_temp}"
	# call to certbot
	certbot certonly \
		--logs_dir ${log_dir} \
		--dns-rfc2136 \
		--dns-rfc2136-credentials "${ddns_temp}" \
		--dns-rfc2136-propagation-seconds 30 \
		--preferred-challenges=dns-01 \
		--server "${acme_server}" \
		--eab-kid "${acme_kid}" \
		--eab-hmac-key "${acme_hmac_key}" \
		--email "${acme_email}" \
		--cert-name "$1" \
		"${cert_alt_names}"

	# si se ha solicitado, copiamos los certificados 
	# al servidor destino
	[ ${install} -eq 1 ] && install_certificate "$1"

	# borramos fichero temporal de configuración ddns
	rm -f "${ddns_temp}"
}

# delete a certificate
# $1 name of certificate to be deleted
do_delete () {
	trace "Enter do_delete( '$1' )"
	# parse sites ini file to retrieve certificate info
	parse_site "$1"
	# create temp file with ddns keys
	ddns_temp="${tmp_dir}/ddns_credentials.$$.ini"
	get_ddns_creds > "${ddns_temp}"
	# revoke certificate (not really needed, but...)
        do_revoke "$1"
	# and call certbot to remove
        certbot delete \
                --logs_dir ${log_dir} \
                --dns-rfc2136 \
                --dns-rfc2136-credentials "${ddns_credentials}" \
                --dns-rfc2136-propagation-seconds 30 \
                --preferred-challenges=dns-01 \
                --server "${acme_server}" \
                --eab-kid "${acme_kid}" \
                --eab-hmac-key "${acme_hmac_key}" \
                --email "${acme_email}" \
                --cert-name "$1"
	
	# Si install está activado, borramos el certificado en el host
	[ ${install} -eq 1 ] && remove_certificate "$1"
	# Eliminamos fichero temporal de claves ddns
	rm -f "${ddns_temp}"
	# finalmente elimina la seccion asociada del fichero de configuración de sites
	ini_remove_section "${sites_info}" "$1"
}

# revoke certificate
# $1 name of certificate to be revoked
do_revoke () {
	trace "Enter do_revoke( '$1' )"
	# parse sites ini file to retrieve certificate info
	parse_site "$1"
	# create temp file with ddns keys
	ddns_temp="${tmp_dir}/ddns_credentials.$$.ini"
	get_ddns_creds > "${ddns_temp}"
	# and call certbot to remove
        certbot revoke \
                --logs_dir ${log_dir} \
                --dns-rfc2136 \
                --dns-rfc2136-credentials "${ddns_credentials}" \
                --dns-rfc2136-propagation-seconds 30 \
                --preferred-challenges=dns-01 \
                --server "${acme_server}" \
                --eab-kid "${acme_kid}" \
                --eab-hmac-key "${acme_hmac_key}" \
                --email "${acme_email}" \
                --cert-name "$1"

	# disable entry from sites file
	ini_write "${sites_info}" "$1" "cert_enabled" 0
	# Eliminamos fichero temporal de claves ddns
	rm -f "${ddns_temp}"
}

# Force certificate renewal
# $1 name of certificate to be renoved
do_renove () {
	trace "Enter do_renove( \"$1\" )"
        # parse sites ini file to retrieve certificate info
        parse_site "$1"
		# create temp file with ddns keys
		ddns_temp="${tmp_dir}/ddns_credentials.$$.ini"
		get_ddns_creds > "${ddns_temp}"
        # call to certbot
        certbot renew \
                --logs_dir ${log_dir} \
                --dns-rfc2136 \
                --dns-rfc2136-credentials "${ddns_credentials}" \
                --dns-rfc2136-propagation-seconds 30 \
                --preferred-challenges=dns-01 \
                --server "${acme_server}" \
                --eab-kid "${acme_kid}" \
                --eab-hmac-key "${acme_hmac_key}" \
                --email "${acme_email}" \
                --cert-name "$1"

        # si se ha solicitado, copiamos los certificados 
        # al servidor destino
        [ ${install} -eq 1 ] && install_certificate "$1"

        # si no verboso borramos fichero temporal de configuración ddns
        [ ${verbose} -eq 0 ] && rm -f "${ddns_credentials}"
		# Eliminamos fichero temporal de claves ddns
		rm -f "${ddns_temp}"
}

# renove all existing certificates
do_renove_all () {
	trace "Enter do_renove_all()"
	for entry in $(ini_list_sections "${sites_info}") ; do
		[ "$entry" = "default" ] && continue
		a=$(ini_read "${sites_info}" "$entry" "cert_enabled") 
		if [ "$a" -eq 0 ]; then
			log "Certificate '${entry}' is disabled. Skip"
		else
			do_renove "$entry"
		fi
	done
}

# Allow/Block cert handling in sites conf .ini file
# $1: cert_name
# #2: 0:disabled 1:enabled
do_enable () {
	if ! ini_section_exists "${sites_info}" "$1" ; then
		error "Certificate '$1' is not declared in ${sites_info}"
		exit 1
	else
		ini_write "${sites_info}" "$1" "cert_enabled" "$2"
	fi
}

# show usage and options
usage () {
	echo "Certificate management with certbot/DNS-01 validation"
	echo "Version: $Version"
	echo "Author: $Author"
	echo "License: $License"
	echo "Available docs: ${DOCDIR}"
	echo ""
	echo "Usage: $0 options"
	echo "  Options:"
	echo "  -? | -h | --help        show usage and exit"
	echo "  -v | --verbose          Verbose log to console"
	echo "  -q | --quiet            Do not send output to console"
	echo "  -l | --list             List current certificates"
	echo "  -c | --create <name>    Create/renove certificate <name>"
	echo "  -d | --delete <name>    Delete certificate <name>"
	echo "  -R | --revoke <name>    Revoke certificate <name>"
	echo "  -E | --enable <name>    Mark certificate <name> as active in conf file"
	echo "  -D | --disable <name>   Mark certificate <name> as inactive in conf file"
	echo "  -a | --renove-all       Renew all certificates next to expiration (30 days or less)"
	echo "  -r | --renove <name>    Force renove certificate <name>"
	echo "  -C | --creds <file>     Path to ACME EAB creadentials .ini file"
	echo "                          (def: '${acme_creds}')"
	echo "  -u | --user <user>      Use ACME credentials for user <user>"
	echo "                          (def: '[default]' section of <creds> file)"
	echo "  -S | --sites <file>     Path to DNS info and install data .ini file"
	echo "                          (def: '${sites_info}')"
	echo "                          Every cert_name must have an entry in this file"
	echo "  -m | --mail             Send log via mail to admin"
	echo "  -i | --install          Install/remove certificate into (remote) server"
	echo "                          (default is do not install )"
	echo ""
}

# limpia el fichero de lock al terminar
at_exit () {
        rm -f "${lock_file}"
}

#
################## comienzo del programa ##############
#

# Creamos (si no están ya creados) los directorios de logs y temporales
mkdir -p "${log_dir}" "${tmp_dir}"

# Generamos un fichero de bloqueo para evitar ejecucion simultanea
# de este script
if ! lockfile -r 0 "${lock_file}" ; then
        echo "Hay un 'certmanager' en ejecucion"
        echo "Si lo anterior no es correcto, borre el fichero '${lock_file}' y pruebe de nuevo"
        exit 1
fi
# Borramos el fichero de bloqueo al finalizar la ejecucion del programa
trap at_exit EXIT

# 
# analizamos argumentos de la linea de comandos
while [ "Z$1" != "Z" ]; do
    case "Z$1" in
	"Z-?" | "Z-h" | "Z--help" ) 
		usage; exit 0 
		;;
	"Z-v" | "Z--verbose" ) 
		verbose=1 ; shift 
		;;
	"Z-q" | "Z--quiet" ) 
		verbose=0 ; shift 
		;;
	"Z-i" | "Z--install" ) 
		install=0 ; shift 
		;;
	"Z-m" | "Z--mail" ) 
		mailto=1 ; shift 
		;;
	"Z-E" | "Z--enable" ) 
		action="enable"; enabled=1 ; shift 
		cert_name=$1; shift
		;;
	"Z-D" | "Z--disable" ) 
		action="enable"; enabled=0 ; shift
		cert_name=$1; shift
		;;
	"Z-l" | "Z--list" ) 
		[ "$action" != "" ] && (echo "Cannot ask for '${action}' and 'list'" >&2; exit 1) 
		action="list"; shift
		;;
	"Z-c"  | "Z--create" )
		[ "$action" != "" ] && (echo "Cannot ask for '${action}' and 'create'" >&2; exit 1) 
		action="create"; shift;
		cert_name=$1; shift;
		;;
	"Z-d"  | "Z--delete" )
		[ "$action" != "" ] && (echo "Cannot ask for '${action}' and 'delete'" >&2; exit 1) 
		action="delete"; shift;
		cert_name=$1; shift;
		;;
	"Z-R"  | "Z--revoke" )
		[ "$action" != "" ] && (echo "Cannot ask for '${action}' and 'revoke'" >&2; exit 1) 
		action="revoke"; shift;
		cert_name=$1; shift;
		;;
	"Z-r"  | "Z--renove" )
		[ "$action" != "" ] && (echo "Cannot ask for '${action}' and 'renove'" >&2; exit 1) 
		action="renove"; shift;
		cert_name=$1; shift;
		;;
	"Z-a"  | "Z--renove-all" )
		[ "$action" != "" ] && (echo "Cannot ask for '${action}' and 'renove-all" >&2; exit 1) 
		action="renove-all"; shift;
		;;
	"Z-C"  | "Z--creds" )
		shift;
		if [ ! -f "$1" ]; then
		   echo "ACME EAB credential file '$1' does not exist" >&2; exit 1
		fi
		acme_creds=$1; shift;
		;;
	"Z-u"  | "Z--user" )
		shift;
		user=$1; shift;
		;;
	"Z-S"  | "Z--sites" )
		shift;
		if [ ! -f "$1" ]; then
		   echo "Sites & DDNS destination info file '$1' does not exist" >&2; exit 1
		fi
		sites_info=$1; shift;
		;;
    esac
done

# Verificamos que sea el usuario "root" quien ejecuta el programa
if [ $UID -ne 0 ]; then
       echo "Debe ejecutar este script como root" >&2
       exit 1
fi

# check and load .ini file parser library
if [ ! -f "${ini_parser}" ]; then
	echo "Ini Parser library file '${ini_parser}' does not exist. Abort" >&2
	exit 1
else
	# shellcheck disable=SC1090
	# shellcheck source=/dev/null
	source "${ini_parser}"
fi

# An action must be requested
if [ "Z${action}" = "Z" ]; then
	echo "No action requested. Use '$0 --help' to see options" >&2
	exit 1;
fi

# check and load ACME credentials from .ini file
parse_creds_file

# Check for DDNS options and destination host/paths .ini file
if [ ! -f "$sites_info" ]; then
	echo "DNS and certs destination info file '$sites_info' does not exist" >&2
	exit 1
elif ! ini_validate "$sites_info" ; then
	echo "DNS and certs destination info '$sites_info' is not a valid .ini file" >&2
	exit 1
fi

# Everything seems ok. Check action
case "$action" in
	"list" ) do_list ;;
	"create" ) do_create "${cert_name}" ;;
	"delete" ) do_delete "${cert_name}" ;;
	"revoke" ) do_revoke "${cert_name}" ;;
	"renove" ) do_renove "${cert_name}" ;;
	"renove-all" ) do_renove_all ;;
	"enable" ) do_enable ${enabled} ;;
esac

# si se ha definido, mandar correo al CdC
if [ ${mailto} -eq 1 ]; then
	fecha=$(/bin/date +%Y%m%d_%H%M)
	cat "${log_file}" |\
	  	mail -s "Informe de ejecución de certmanager ${fecha}" "${mailto}"
fi

# eso es todo, amigos
echo "Proceso completado"
exit 0
