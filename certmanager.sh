#!/bin/bash
#
# Programa de gestión de certificados a través de CertBot
# usando el API ACME de harica.gr mediante Domain Validation
# 
#
Author="Juan Antonio Martínez <juanantonio.martinez@upm.es>"
Version="1.2 2026-07-22"
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
LOCKDIR=/var/lock

# Ini parser library script
# https://github.com/lsferreira42/bash-ini-parser
ini_parser=${LIBDIR}/lib_ini.sh

# Fichero .ini que contiene las credenciales de acceso a HARICA-ACME
acme_creds="${CONFDIR}/acme_creds.ini"

# Fichero .ini que contiene los datos de DDNS y de ubicacion para cada certificado
sites_info="${CONFDIR}/sites.ini"

# Fichero .ini que contiene las claves de acceso al servidor DNS para la validación ACME
ddns_keys="${CONFDIR}/ddns_keys.ini"

# Carpeta donde se regeneran las claves temporales para la validación ACME
# certbot guarda en su configuración estos datos a la hora 
# de proceder a la renovación de certificados, por lo que una
# vez generado el fichero no se debe borrar
ddns_dir="${CONFDIR}/ddns"

# directorio de ficheros temporales
tmp_dir="${TMPDIR}"
# registro de eventos y errores del script.
# Se borra al finalizar la ejecución salvo --verbose o error
log_dir="${LOGDIR}"
# fichero de logs
log_file="${log_dir}/cert_manager.$$.log"
# fichero de bloqueo
lock_file="${LOCKDIR}/certmanager.lock"

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
	if [ -n "${verbose}" ] || [ "${exitcode}" -eq 0 ] ; then  
		rm -f "${log_file}"; 
	fi
	# limpiamos fichero de lock.
	rm -rf "${lock_file}" "${tmp_dir}"
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
    elif ! (ini_list_sections "$acme_creds" | grep -q -- "${user}") ; then
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


# Extract ddns credentials from ddns_keys file. Notice perms.
# we regenerate this file to take care on credentials files change
# Certbot will save this file in its configuration for renewall,
# so don't remove it once generated
get_ddns_creds () {
	if [ ! -f "${ddns_keys}" ]; then
		die 1 "DNS sites conf file \"${ddns_keys}\" does not exist" 
    elif ! ini_validate "${ddns_keys}" ; then
		# comprobamos si el fichero .ini es valido
		die 1 "DNS sites conf file \"${ddns_keys}\"is not a valid .ini file" 
    elif ! (ini_list_sections "${ddns_keys}" | grep -q "${ddns_credentials}") ; then
		die 1 "DNS section \"${ddns_credentials}\" is not declared in \"${ddns_keys}\""
    else
		ddns_temp="${ddns_dir}/${ddns_credentials}.ini.tmp"
		# finalmente procesamos los datos de la seccion
		# utilizamos un fichero temporal para evitar problemas de concurrencia
		ini_get_all "${ddns_keys}" "${ddns_credentials}" > "${ddns_temp}"
		cmp -s "${ddns_temp}" "${ddns_dir}/${ddns_credentials}.ini" || \
			mv "${ddns_temp}" "${ddns_dir}/${ddns_credentials}.ini"
		chmod 640 "${ddns_dir}/${ddns_credentials}.ini"
	fi
	echo "${ddns_dir}/${ddns_credentials}.ini"
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
	
	# creamos un fichero temporal con las credenciales DDNS. 
	ddns_temp=$(get_ddns_creds)

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
		--dns-rfc2136-propagation-seconds 45 \
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

	# creamos un fichero temporal con las credenciales DDNS. 
	ddns_temp=$(get_ddns_creds)

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
        --dns-rfc2136-propagation-seconds 45 \
        --preferred-challenges=dns-01 \
        --server "${acme_server}" \
		  ${eab_data} \
        --email "${acme_email}" \
        --cert-name "$1"

	set +x

	# Si install está activado, borramos el certificado en el host
	[ "${install}" -eq 1 ] && remove_certificate "$1"

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
	
	# creamos un fichero temporal con las credenciales DDNS. 
	ddns_temp=$(get_ddns_creds)

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
        --dns-rfc2136-propagation-seconds 45 \
        --preferred-challenges=dns-01 \
        --server "${acme_server}" \
		  ${eab_data} \
        --email "${acme_email}" \
        --cert-name "$1"

	set +x

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
	
	# creamos un fichero temporal con las credenciales DDNS. 
	ddns_temp=$(get_ddns_creds)

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
        --dns-rfc2136-propagation-seconds 45 \
        --preferred-challenges=dns-01 \
        --server "${acme_server}" \
		  ${eab_data} \
        --cert-name "$1" \
        --email "${acme_email}"

	set +x
	
    # si se ha solicitado, copiamos los certificados 
    # al servidor destino
    [ "${install}" -eq 1 ] && install_certificate "$1"

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
		# enable/disable also in certbot configuration
		cb_conf="/etc/letsencrypt/renewal/${1}.conf"
		if [ -f "${cb_conf}" ]; then
			enable="False";  [ "$2" = "1" ] && enable="True"
			ini_write "${cb_conf}" "renewalparams" "autorenove" "${enable}"	
		fi
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
	echo "Usage: $0 <action> [options] [cert_name]"
	echo ""
	echo "  Actions:"
	echo "  list                    List current certificates"
	echo "  create                  Create/renew certificate"
	echo "  delete                  Delete certificate"
	echo "  revoke                  Revoke certificate"
	echo "  renove                  Force certificate renewal"
	echo "  renove-all              Renew all certs next to expire (30 days or less)"
	echo "  enable                  Mark certificate as active in conf file"
	echo "  disable                 Mark certificate as inactive in conf file"
	echo "  install                 Install/remove certificate into (remote) server"
	echo ""
	echo "  Options:"
	echo "  -? | -h | --help        Show usage and exit"
	echo "  -v | --verbose          Send certmanager/certbot logs to console (def: don't)"
	echo "  -l | --list             List current certificates"
	echo "  -f | --force            Force certbot to renew/create even if not expired"
	echo "  -i | --install          copy created/renoved cert. to (remote) server"
	echo "  -m | --mail <addr>      Send log via mail to addr"  
	echo ""
}

#
################## comienzo del programa ##############
#

# Creamos (si no están ya creados) los directorios de logs y temporales
mkdir -p "${log_dir}" "${tmp_dir}" "${ddns_dir}"
chown root:root "${log_dir}" "${tmp_dir}" "${ddns_dir}"
chmod 750 "${log_dir}" "${tmp_dir}" "${ddns_dir}"

# la carpeta ddns_dir debería estar ya creada, 
# pero por si acaso la creamos y ajustamos permisos
mkdir -p "${ddns_dir}"
chown -R root:root "${ddns_dir}"
chmod 640 "${ddns_dir}"/*.ini 2>/dev/null

# Generamos un fichero de bloqueo para evitar ejecucion simulGtanea
# de este script
# do not call die here, as it will remove lock file
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
		usage; die 0 ""
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
	"Z-m" | "Z--mail" ) 
		shift; mailto=1 ; shift 
		;;
	"Z-f" | "Z--force" ) 
		force="--force-renewal" ; shift
		;;
	"Z-i" | "Z--install" )
		install=1 ; shift	
		;;
	"Zenable" ) 
		[ "$action" != "" ] && die 1 "Doble comando: '${action}' y 'enable'" 
		action="enable"; enabled=1 ; shift
		;;
	"Zdisable" ) 
		[ "$action" != "" ] && die 1 "Doble comando: '${action}' y 'disable'"
		action="disable"; enabled=0 ; shift
		;;
	"Zlist" ) 
		[ "$action" != "" ] && die 1 "Doble comando: '${action}' y 'list'" 
		action="list"; shift
		;;
	"Zcreate" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'create'" 
		action="create"; shift
		;;
	"Zdelete" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'delete'"
		action="delete"; shift
		;;
	"Zrevoke" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'revoke'"
		action="revoke"; shift
		;;
	"Zrenove" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'renove'"
		action="renove"; shift
		;;
	"Zrenove-all" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'renove-all"
		action="renove-all"; shift;
		;;
	"Zinstall" )
		[ "$action" != "" ] && die 1 "Doble comando '${action}' y 'renove-all"
		action="install"; shift;
		;;
	* )
		cert_name="$1"; shift
		;;
    esac
done

# Verificamos que sea el usuario "root" quien ejecuta el programa
if [ $UID -ne 0 ]; then
       die 1 "Debe ejecutar este script como root" 
fi

# check owner and permissions of conf files. on error, abort
for i in "${acme_creds}" "${ddns_keys}" "${sites_info}"; do
	if [ ! -f "$i" ]; then
		die 1 "File '$i' does not exist"
	fi
	if ! stat -c "%A %u %g" "$i" | grep -q -- '-rw-r----- 0 0'; then
		die 1 "File '$i' is not owned by root or has wrong permissions."
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
	die 1 "DNS and certs destination info '$sites_info' is not a valid .ini file" 
fi

# Everything seems ok. Check action
done=0
case "$action" in
	"list" ) do_list; done=1 ;;
	"renove-all" ) do_renove_all; done=1;;
esac

if [ ${done} -eq 0 ]; then
	# si la accion requiere un nombre de certificado,
	# comprobamos que se haya dado
	[ -z "${cert_name}" ] && die 1 "No certificate name provided. Use '$0 --help' to see options"
	case "$action" in
		"create" ) do_create "${cert_name}" ;;
		"delete" ) do_delete "${cert_name}" ;;
		"revoke" ) do_revoke "${cert_name}" ;;
		"renove" ) do_renove "${cert_name}" ;;
		"enable" ) do_enable "${cert_name}" ${enabled};;
		"install" ) install_certificate "${cert_name}" ;;
	esac
fi

# si se ha definido, mandar correo al CdC
if [ -n "${mailto}" ]; then
	fecha=$(/bin/date +%Y%m%d_%H%M)
	cat "${log_file}" |\
	  	mail -s "Informe de ejecución de certmanager ${fecha}" "${mailto}"
fi

# eso es todo, amigos
rm -rf "${lock_file}" "${tmp_dir}"
log "Proceso completado"
die 0 ""
