#!/bin/bash

INSTALL=$(which install)
[ -n "${INSTALL}" ] || INSTALL="install"

conffiles="etc/acme_creds.ini etc/ddns_keys.ini etc/sites.ini"
binfiles="certmanager.sh tsig2ini.sh"
libfiles="lib_ini.sh install.sh"
docfiles="certmanager.LICENSE lib_ini.LICENSE README.md"

error () {
    echo "ERROR: $*"
    exit 1
}

# bash version of "install -u user -g group -m mode source destination"
install () {
    cp -f "${7}" "${8}"
    chown "${2}":"${4}" "${8}"
    chmod "${6}" "${8}"
}

[ "${USER}" = "root" ] || error "Debe ejecutar este script como root"

if [ "Z$1" = "Z-u" ]; then
    # pregunta al usuario antes de proceder a la DES-instalacion
    read -r -p "Pulse Return para desinstalar CertManager o Ctrl-c para cancelar"
    # JAMC 20260716 replace rm -rf to native rm and rmdir to avoid accidental deletion of other files
    [ -d /etc/certmanager ] && rm -rf -- /etc/certmanager
    [ -d /usr/local/lib/certmanager ] && rm -rf -- /usr/local/lib/certmanager
    [ -d /usr/share/doc/certmanager ] && rm -rf -- /usr/share/doc/certmanager
    rm -f /usr/local/bin/{certmanager,tsig2ini}.sh
    echo "CertManager desinstalado"
    exit 0
fi

for i in ${conffiles} ${binfiles} ${libfiles} ${docfiles}; do
    [ -f "$i" ] || error "Fichero ${i} no encontrado"
done

# Comprobamos si certbot y la extensión dns-rfc-2136 están instaladas
which -s certbot || error "Certbot no se encuentra o no está instalado"
certbot plugins 2>/dev/null | grep -q dns-rfc2136 || \
    error "El plugin dns-rfc2136 de Certbot no está instalado"

# banner de presentación
version=$(grep 'Version="' certmanager.sh | sed -e 's/Version="\(.*\)"/\1/g')
echo ""
echo "Instalación de CertManager version $version"
echo "Código fuente: https://github.com/jonsito/acme-ddns-certmanager"
# pregunta al usuario antes de empezar
read -r -p "Pulse Return para comenzar la instalación o Ctrl-c para cancelar"

# Creamos carpetas asociadas
echo "Creando directorios..."
mkdir -p /etc/certmanager/ddns
chmod 750 /etc/certmanager
mkdir -p /usr/share/doc/certmanager
mkdir -p /usr/local/lib/certmanager
mkdir -p /usr/local/bin

echo "Instalando ficheros..."
# configuracion. Preservamos ficheros originales si existen
for i in ${conffiles}; do
    dest=$(basename "$i")
    file="/etc/certmanager/${dest}"
    [ -f "${file}" ] && file="${file}.dist"
    install -o root -g root -m 640 "$i" "${file}"
done
# bibliotecas
for i in ${libfiles}; do
    ${INSTALL} -o root -g root -m 644 "$i" /usr/local/lib/certmanager/"$i"
done
# binarios
for i in ${binfiles}; do
    "${INSTALL}" -o root -g root -m 755 "$i" /usr/local/bin/"$i"
done
# documentacion
for i in ${docfiles}; do
    "${INSTALL}" -o root -g root -m 644 "$i" /usr/share/doc/certmanager/"$i"
done
which -s md2html && md2html -f --github README.md -o /usr/share/doc/certmanager/README.html

echo ""
echo "Instalacion completada."
echo "Instrucciones de configuración y uso en /usr/share/doc/certmanager"
echo "Pulse \"certmanager.sh --help\" para ver opciones"

# esto es todo, amigos
exit 0
