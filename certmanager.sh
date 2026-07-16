#!/bin/bash
#
# Programa de gestión de certificados a través de CertBot
# usando el API ACME de harica.gr mediante Domain Validation
# 
#
Author="Juan Antonio Martínez <juanantonio.martinez@upm.es>"
Version="1.1 2026-07-08"
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
lock_file="${tmp_dir}/certmanager.lock"

# Valores por defecto
verbose=""		# show log in console
quiet="--quiet" # suppress certbot output to console
force=""		# force certbot to renew/create even if not expired
action=""	# Action to perform when this script is executed
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
	[ -n "${verbose}" ] && echo "$*" >&2
}

# send message to log file AND console
error () {
	echo "$*" >&2
	echo "$*" >>${log_file}
}

# finaliza la ejecucion
# $1: codigo de salida (0:ok, else error)
# $2 mensaje de error
die () {
	exitcode=$1; shift
	# en caso de error, lo guardamos en el fichero de logs
	[ "${exitcode}" -ne 0 ] && error "$*"
	# si error o verbose no borramos fichero de logs
	if [ -n "${verbose}" ] || [ "${exitcode}" -eq 0 ] ; then  rm -f "${log_file}"; fi
	# limpiamos fichero de lock.
	rm -rf "${lock_file} ${tmp_dir}"
	exit "${exitcode}"
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
	cert_enabled=$(ini_read "${sites_info}" "$1" "cert_enabled" )
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
parse_creds () {
	trace "enter parse_creds ('$1')"
	user="${1}"
    if [ ! -f "$acme_creds" ]; then
		die 1 "ACME EAB credentials file '$acme_creds' does not exist" 
    elif ! ini_validate "$acme_creds" ; then
		# comprobamos si el fichero .ini es valido
		die 1 "ACME EAB credentials '$acme_creds' is not a valid .ini file" 
    elif ! (ini_list_sections "$acme_creds" | grep -Fq -- "${user}") ; then
		die 1 "User '$user' is not declared in '$acme_creds'"
    else
		echo "User: $user"
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
			die 1 "Incomplete ACME credentials data for user '$user'"
		fi
    fi 
}

# extract ddns info and store in temporary file
get_ddns_creds () {
	if [ ! -f "${ddns_keys}" ]; then
		die 1 "DNS sites conf file \"${ddns_keys}\" does not exist" 
    elif ! ini_validate "${ddns_keys}" ; then
		# comprobamos si el fichero .ini es valido
		die 1 "DNS sites conf file \"${ddns_keys}\"is not a valid .ini file" 
    elif ! (ini_list_sections "${ddns_keys}" | grep -Fq -- "${ddns_credentials}") ; then
		die 1 "DNS section \"${ddns_credentials}\" is not declared in \"${ddns_keys}\""
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
		# PENDING: try to send cert via email to cert owner
		return
	fi
	fromdir="/etc/letsencrypt/live/${1}/"
	[ -n "${cert_path}" ] && \
		${SCP} "${fromdir}/cert.pem" "${cert_host}":"${cert_path}/${1}_cert.pem"
	[ -n "${key_path}" ] && \
		${SCP} "${fromdir}/privkey.pem" "${cert_host}":"${key_path}/${1}_key.pem"
	[ -n "${chain_path}" ] && \
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
# TODO: handle two ways of lists:
# - short: just enumerate certs from "sites.ini"
# - long: on each site call certbot to retrieve cert info
do_list () {
	trace "Enter do_list()"

	for entry in $(ini_list_sections "${sites_info}") ; do
		[ "$entry" = "default" ] && continue
		a=$(ini_read "${sites_info}" "$entry" "cert_enabled") 
		ena="enabled"
		[ "$a" -eq 0 ] && ena="disabled"
		echo -e "\nCertificate '${entry}' is ${ena}"
		# en modo verboso presentamos info de los certificados enabled
		if [ -n "${verbose}" ]; then
			[ "$a" -eq 0 ] && continue
			certbot certificates --cert-name "${entry}" 2>/dev/null
		fi
	done
}

# Create/renew a certificate
# $1: certificate CN name (section in ini file)
do_create () {
	trace "Enter do_create( '$1' )"

	# parse sites ini file to retrieve certificate and credentials
	parse_site "$1"
	if [ "${cert_enabled}" -eq 0 ]; then
		error "Create: El certificado \"${1}\" está deshabilitado. "
		return
	fi 
	parse_creds "${acme_credentials}"
	
	# indicamos el CN y los SubjectAlternateNames
	domains="-d $1 "
	[ -n "${cert_alt_names}" ] && domains="-d ${1} -d ${cert_alt_names/,/ -d /}"
	
	# extract ddns credentials from ddns_keys file. Notice perms
	ddns_temp="${tmp_dir}/ddns_create.$$.ini"
	get_ddns_creds > "${ddns_temp}" && chmod 640 "${ddns_temp}"

	# On LetsEncrypt remove eab-xxx related vars
	[ -n "${eab-kid}" ]	&& eab_data="--eab-kid ${acme_kid} --eab-hmac-key ${acme_hmac_key}"

	# on verbose mode, show certbot commands
	[ -n "${verbose}"  ] && set -x

	# call to certbot
	certbot certonly \
		  ${quiet} \
		--keep-until-expiring \
		--logs-dir ${log_dir} \
		--dns-rfc2136 \
		--dns-rfc2136-credentials "${ddns_temp}" \
		--dns-rfc2136-propagation-seconds 30 \
		--preferred-challenges=dns-01 \
		--server "${acme_server}" \
		  ${eab_data} \
		--cert-name "$1" \
		  ${domains} \
		  ${force} \
		--email "${acme_email}"

	set +x

	# si se ha solicitado, copiamos los certificados 
	# al servidor destino
	[ "${install}" -eq 1 ] && install_certificate "$1"

	# borramos fichero temporal de configuración ddns
	rm -f "${ddns_temp}"
}

# delete a certificate
# $1 name of certificate to be deleted
do_delete () {
	trace "Enter do_delete( '$1' )"

	# parse sites ini file to retrieve certificate info
	parse_site "$1"
	if [ "${cert_enabled}" -eq 0 ]; then
		error "Delete: El certificado \"${1}\" está deshabilitado. "
		return
	fi 
	parse_creds "${acme_credentials}"

	# create temp file with ddns keys. Notice permissions
	ddns_temp="${tmp_dir}/ddns_delete.$$.ini"
	get_ddns_creds > "${ddns_temp}" && chmod 640 "${ddns_temp}"

	# Revoke certificate (not really needed, but...)
    do_revoke "$1"

	# On LetsEncrypt remove eab-xxx related vars
	[ -n "${eab-kid}" ] && eab_data="--eab-kid ${acme_kid} --eab-hmac-key ${acme_hmac_key}"

	# on verbose mode, show certbot commands
	[ -n "${verbose}"  ] && set -x

	# and call certbot to remove. 
    certbot delete \
		  ${quiet} \
        --logs-dir ${log_dir} \
        --dns-rfc2136 \
        --dns-rfc2136-credentials "${ddns_temp}" \
        --dns-rfc2136-propagation-seconds 30 \
        --preferred-challenges=dns-01 \
        --server "${acme_server}" \
		  ${eab_data} \
        --email "${acme_email}" \
        --cert-name "$1"

	set +x

	# Si install está activado, borramos el certificado en el host
	[ "${install}" -eq 1 ] && remove_certificate "$1"

	# Eliminamos fichero temporal de claves ddns
	rm -f "${ddns_temp}"

	# finalmente elimina la seccion asociada del fichero de configuración de sites
	# o mejor: marcamos la seccion como disable (por si acaso)
	# ini_remove_section "${sites_info}" "$1"
	ini_write "${sites_info}" "${1}" "cert_enabled" 0

}

# revoke certificate
# $1 name of certificate to be revoked
do_revoke () {
	trace "Enter do_revoke( '$1' )"

	# parse sites ini file to retrieve certificate info
	parse_site "$1"
	if [ "${cert_enabled}" -eq 0 ]; then
		error "Revoke: El certificado \"${1}\" está deshabilitado. "
		return
	fi 
	parse_creds "${acme_credentials}"
	
	# create temp file with ddns keys with proper perms
	ddns_temp="${tmp_dir}/ddns_revoke.$$.ini"
	get_ddns_creds > "${ddns_temp}" && chmod 644 "${ddns_temp}"

	# On LetsEncrypt remove eab-xxx related vars
	[ -n "${eab-kid}" ] && eab_data="--eab-kid ${acme_kid} --eab-hmac-key ${acme_hmac_key}"

	# on verbose mode, show certbot commands
	set -x

	# call to certbot
    certbot revoke \
		  ${quiet} \
        --logs-dir ${log_dir} \
        --dns-rfc2136 \
        --dns-rfc2136-credentials "${ddns_temp}" \
        --dns-rfc2136-propagation-seconds 30 \
        --preferred-challenges=dns-01 \
        --server "${acme_server}" \
		  ${eab_data} \
        --email "${acme_email}" \
        --cert-name "$1"

	set +x

	# Eliminamos fichero temporal de claves ddns
	rm -f "${ddns_temp}"

	# disable entry from sites file
	ini_write "${sites_info}" "$1" "cert_enabled" 0
}

# Force certificate renewal
# 20260707: la operacion "renew" no acepta dominio ni alternate names,
#           solamente el nombre (CN) del certificado a renovar
# $1 name of certificate to be renoved
do_renove () {
	trace "Enter do_renove( \"$1\" )"
    
	# parse sites ini file to retrieve certificate info
    parse_site "$1"
	if [ "${cert_enabled}" -eq 0 ]; then
		error "Renove: El certificado \"${1}\" está deshabilitado. "
		return
	fi 
	parse_creds "${acme_credentials}"

	# create temp file with ddns keys. Set proper perms
	ddns_temp="${tmp_dir}/ddns_renove.$$.ini"
	get_ddns_creds > "${ddns_temp}" && chmod 640 "${ddns_temp}"

    # call to certbot. On letsencrypt remove eab- related variables
	[ -n "${eab-kid}" ] && eab_data="--eab-kid ${acme_kid} --eab-hmac-key ${acme_hmac_key}"

	# on verbose mode, show certbot commands
	[ -n "${verbose}"  ] && set -x

    certbot renew \
		  ${quiet} \
		--force-renewal \
        --logs-dir ${log_dir} \
        --dns-rfc2136 \
        --dns-rfc2136-credentials "${ddns_temp}" \
        --dns-rfc2136-propagation-seconds 30 \
        --preferred-challenges=dns-01 \
        --server "${acme_server}" \
		  ${eab_data} \
        --cert-name "$1" \
        --email "${acme_email}"

	set +x
	
    # si se ha solicitado, copiamos los certificados 
    # al servidor destino
    [ "${install}" -eq 1 ] && install_certificate "$1"

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
			# use create instead to remove, as renove is forced 
			do_create "$entry"
		fi
	done
}

# Allow/Block cert handling in sites conf .ini file
# $1: cert_name
# #2: 0:disabled 1:enabled
do_enable () {
	if ! ini_section_exists "${sites_info}" "$1" ; then
		die 1 "Certificate '$1' is not declared in ${sites_info}"
	else
		ini_write "${sites_info}" "$1" "cert_enabled" "$2"
	fi
}

# show usage and options
usage () {
	echo ""
	echo "Certificate management with certbot/DNS-01 validation"
	echo "Version: $Version"
	echo "Author: $Author"
	echo "License: $License"
	echo "Available docs: ${DOCDIR}"
	echo ""
	echo "Usage: $0 options"
	echo "  Options:"
	echo "  -? | -h | --help        show usage and exit"
	echo "  -v | --verbose          Send certmanager/certbot logs to console (def: don't)"
	echo "  -l | --list             List current certificates"
	echo "  -f | --force            Force certbot to renew/create even if not expired"
	echo "  -c | --create <name>    Create/renove certificate <name>"
	echo "  -d | --delete <name>    Delete certificate <name>"
	echo "  -R | --revoke <name>    Revoke certificate <name>"
	echo "  -E | --enable <name>    Mark certificate <name> as active in conf file"
	echo "  -D | --disable <name>   Mark certificate <name> as inactive in conf file"
	echo "  -a | --renove-all       Renew all certs next to expire (30 days or less)"
	echo "  -r | --renove <name>    Force renove certificate <name>"
	echo "  -m | --mail <addr>      Send log via mail to addr"
	echo "  -i | --install          Install/remove certificate into (remote) server"
	echo "                          (default is do not install )"
	echo ""
}

#
################## comienzo del programa ##############
#

# Creamos (si no están ya creados) los directorios de logs y temporales
mkdir -p "${log_dir}" "${tmp_dir}"
chown root:root "${log_dir}" "${tmp_dir}"
chmod 750 "${log_dir}" "${tmp_dir}"

# Generamos un fichero de bloqueo para evitar ejecucion simulGtanea
# de este script
if ! lockfile -r 0 "${lock_file}" ; then
        error "Hay un 'certmanager' en ejecucion"
        error "Si lo anterior no es correcto, borre el fichero '${lock_file}' y pruebe de nuevo"
		exit 1
fi

# 
# analizamos argumentos de la linea de comandos
while [ "Z${1}" != "Z" ]; do
    case "Z${1}" in
	"Z-?" | "Z-h" | "Z--help" ) 
		usage; die 0 
		;;
	"Z-v" | "Z--verbose" ) 
		verbose="--verbose"
		quiet=""
		shift
		;;
	"Z-q" | "Z--quiet" )
		verbose="" ;
		quiet="--quiet"
		shift
		;;
	"Z-i" | "Z--install" ) 
		install=1 ; shift 
		;;
	"Z-m" | "Z--mail" ) 
		shift; mailto=1 ; shift 
		;;
	"Z-f" | "Z--force" ) 
		force="--force-renuewal" ;	shift
		;;
	"Z-E" | "Z--enable" ) 
		action="enable"; enabled=1 ; 
		shift; cert_name=$1; shift
		;;
	"Z-D" | "Z--disable" ) 
		action="enable"; enabled=0 ;
		shift; cert_name=$1; shift
		;;
	"Z-l" | "Z--list" ) 
		[ "$action" != "" ] && die 1 "Doble comando: '${action}' y 'list'" 
		action="list"; shift
		;;
	"Z-c"  | "Z--create" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'create'" 
		action="create"; shift;
		cert_name=$1; shift;
		;;
	"Z-d"  | "Z--delete" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'delete'"
		action="delete"; shift;
		cert_name=$1; shift;
		;;
	"Z-R"  | "Z--revoke" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'revoke'"
		action="revoke"; shift;
		cert_name=$1; shift;
		;;
	"Z-r"  | "Z--renove" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'renove'"
		action="renove"; shift;
		cert_name=$1; shift;
		;;
	"Z-a"  | "Z--renove-all" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'renove-all"
		action="renove-all"; shift;
		;;
	* )
		error "CertManager: Parametros incorrectos"
		usage
		die 0
    esac
done

# prevent execution of this script if any command fails, 
# or if any command in a pipeline fails
set -euo pipefail

# Verificamos que sea el usuario "root" quien ejecuta el programa
if [ $UID -ne 0 ]; then
       die 1 "Debe ejecutar este script como root" 
fi

# check owner and permissions of conf files. on error, abort
for i in "${acme_creds}" "${ddns_keys}" "${sites_info}"; do
	if [ ! -f "$i" ]; then
		die 1 "File '$i' does not exist"
	fi
	if ! stat -c "%A %u %g" "$i" | grep -Fq -- '-rw-r----- 0 0'; then
		die 1 "File '$i' is not owned by root or has wrong permissions. Must be '-rw-r----- 1 root root'"
	fi
done

# check and load .ini file parser library
if [ ! -f "${ini_parser}" ]; then
	die 1 "Ini Parser library file '${ini_parser}' does not exist. Abort"
else
	ZSH_VERSION=${ZSH_VERSION:-""}  # avoid zsh warning about source
	# shellcheck disable=SC1090
	# shellcheck source=/dev/null
	source "${ini_parser}"
fi

# An action must be requested
if [ "Z${action}" = "Z" ]; then
	die 1 "No action requested. Use '$0 --help' to see options" 
fi

# Check for DDNS options and destination host/paths .ini file
if [ ! -f "$sites_info" ]; then
	die 1 "DNS and certs destination info file '$sites_info' does not exist" 
elif ! ini_validate "$sites_info" ; then
	die "DNS and certs destination info '$sites_info' is not a valid .ini file" 
fi

# Everything seems ok. Check action
case "$action" in
	"list" ) do_list ;;
	"create" ) do_create "${cert_name}" ;;
	"delete" ) do_delete "${cert_name}" ;;
	"revoke" ) do_revoke "${cert_name}" ;;
	"renove" ) do_renove "${cert_name}" ;;
	"renove-all" ) do_renove_all ;;
	"enable" ) do_enable "${cert_name}" ${enabled};;
esac

# si se ha definido, mandar correo al CdC
if [ -n "${mailto}" ]; then
	fecha=$(/bin/date +%Y%m%d_%H%M)
	cat "${log_file}" |\
	  	mail -s "Informe de ejecución de certmanager ${fecha}" "${mailto}"
fi

# eso es todo, amigos
log "Proceso completado"
die 0
