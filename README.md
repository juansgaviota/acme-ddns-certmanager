# Acme-ddns-certmanager

Utilidad para gestión centralizada y distribución de certificados generados con ACME, certbot y basada en validación DNS-01

## Descripción:

Este script permite centralizar en un único servidor la solicitud, y renovación de certificados mediante certbot/ACME mediante validación por DNS, sin necesidad de que el servidor tenga que estar accesible por HTTP

Asímismo se controla la copia y distribución de los certificados obtenidos a cada servidor que los requiera

Se pueden manejar certificados de múltiples hosts, múltiples servidores DNS, así como declarar las claves de acceso al ddns-update de cada servidor dns y las credenciales ACME que utilizará cada certificado

## Estructura:
- certmanager.sh
    Script de gestión
- lib_ini.sh:
    Biblioteca de gestión de ficheros .ini
- tsig2ini.sh:
    Utilidad para conversión de ficheros creados con tsig-genkey
    al formato .ini utilizado por certmanager
- etc/acme_creds.ini
    Fichero de credenciales de acceso del usuario ACME
- etc/ddns_keys.ini
    Fichero de configuración de acceso por DDNS a los diferentes servidores
    de DNS
- etc/cert_list.ini
    Fichero de declaración de diversos certificados a gestionar por la aplicación

## Instalación
Para instalar la aplicación
- Descargar y descomprimir el fichero desde github
- Como usuario "root" ejecutar *install.sh*
- Seguir las instrucciones para configurar los diversos ficheros de configuración, así como configurar DNS para que permita validación DNS-01

**IMPORTANTE** los ficheros bajo la carpeta /etc/certmanager deben estar con permisos root:root y protegidos contra lectura/escritura pública

## Ejecución

Las diversas opciones de ejecución se pueden obtener mediante
> certmanager --help
```
HARICA/Certbot cert management via ACME API with DNS-01 validation
Version: 1.0 2026-05-27
Author: Juan Antonio Martínez <juanantonio.martinez@upm.es>
License: MIT (https://opensource.org/license/mit)

Usage: ./certmanager.sh options
  Options:
  -? | -h | --help        show usage and exit
  -v | --verbose          Verbose log to console
  -q | --quiet            Do not send output to console (but errors)
  -l | --list             List current certificates
  -c | --create <name>    Create/renove certificate <name>
  -d | --delete <name>    Delete certificate <name>
  -R | --revoke <name>    Revoke certificate <name>
  -E | --enable <name>    Mark certificate <name> as active in sites file
  -D | --disable <name>   Mark certificate <name> as inactive in sites file
  -a | --renove-all       Renew all certificates next to expire
  -r | --renove <name>    Force renove certificate <name>
  -e | --expire <days>    Renew when <days> before expiration
                          (def: 30 days)
  -m | --mail             Send log via mail to admin
  -i | --install          Install certificate to (remote) server
                          (default is do not install )
```
## Configuración

### Fichero de credenciales ACME (acme-creds.ini)
```
# acme_creds.ini
# Fichero .ini que contiene las credenciales de acceso vía ACME
# tal y como aparecen en la web de Harica CertManager
#
# se pueden declarar varios usuarios. 
# Si no se define usuario en la linea de comandos
# se usan las credenciales del usuario "default"
#
[default]
acme_kid = "ACME EAB user identification key"
acme_hmac_key = "ACME EAB user hmac key"
acme_server = "https://acme-v02.harica.gr/acme/codigo_del_usuario/directory"
acme_email = "direccion.de.correo@example.com"
#
# letsencrypt no utiliza credenciales (utiliza credenciales generados internamente en el cliente certbot), por lo que podemos dejar kid y hmac_key
# vacios
[letsencrypt]
acme_kid = ""
acme_hmac_key = ""
acme_server = "https://acme-v02.api.letsencrypt.org/directory"
acme_email = "email.del.usuario@example.com"
# ...
[user1]
# ...
#
```
### Configuración DDNS ( plugin python3-certbot-dns-rfc2136 )

En CertManager se usa el plugin certbot-dns-rfc2136 para acceder
a cada servidor dns y añadir los campos TXT que se requieren para la validación ACME DNS-01.
El plugin utiliza un fichero en formato .ini que contiene los los
datos necesarios para poder acceder al servidor y proceder a un dnsupdate

CertManager obtiene dichos datos del fichero **/etc/certmanager/ddns-keys.ini**
que contiene las diversas claves de acceso a los distintos servidores/zonas DNS para las que se van a generar certificados

El fichero **ddns-keys.ini** se genera con la utilidad *tsig2ini.sh*, a partir de la
salida del comando *tsig-keygen*, utilizado para la generación de claves
en el DNS

Ejemplo de utilización:
- Generar clave y guardar en el servidor dns

`root@dns-server# tsig-keygen -a hmac-sha256 "ddns-key" > /etc/bind/ddns-key.conf`

- Con la utilidad tsig2ini.sh generar datos para el fichero ddns-keys.ini

`root@certmgrhost# tsig2ini.sh dns.server.ip.addr /etc/bind/ddns-key.conf >> /etc/certmanager/ddns_keys.ini`

- En el fichero de zona nos aseguraremos que los campos CAA están correctamente
  configurados para admitir el emisor de certificados que vayamos a utilizar

- Configurar el servidor DNS para que admita dns dinámico

`root@dnsserver# vi /etc/bind/named.conf.local`
```
...
include "/etc/bind/ddns-key.conf"
...
zone "example.es" {
        type master;
        file "/var/spool/bind/db/example.es.db";
	allow-update {
        // direccion ip del host donde se ejecuta certmanager
		certmanager.host.ip.addr;
        // nombre de la clave que hemos definido en el fichero ddns-key.conf
		key "ddns-key";
	};
	//update-policy {
	//	grant ddns-key name _acme-challenge.lab.dit.upm.es. TXT;
	//	grant ddns-key name _acme-challenge.host1.lab.dit.upm.es. TXT;
	//	grant ddns-key name _acme-challenge.host2.lab.dit.upm.es. TXT;
	//};

};
...
```
En el ejemplo vemos que se pueden usar las opciones "allow-update", especificando host y clave, o bien la opción "update-policy" que permite un ajuste más fino por dominios y campos que se puedan actualizar

La estructura del fichero de claves ddns utilizado por certmanager.sh es la siguiente

```
# Fichero ddns_keys.ini
[key1]
# Target DNS server (IPv4 or IPv6 address, not a hostname)
dns_rfc2136_server = "dns.server.ip.addr"
# Target DNS port
dns_rfc2136_port = 53
# TSIG key name
dns_rfc2136_name = "dns-key"
# TSIG key secret
dns_rfc2136_secret = "dns-key-secret"
# TSIG key algorithm
dns_rfc2136_algorithm = "MAC-SHA256"
# TSIG sign SOA query (optional, default: false)
dns_rfc2136_sign_query = false

[key2]
...

```

### Configuración de la lista de certificados a gestionar

En el fichero **sites.ini** se indican todos los datos para poder
gestionar y distribuir cada uno de los certificados. Esto incluye
- Datos del certificado
- Credenciales acme
- Datos de acceso al dns dinámico
- Información para instalación en servidor destino
- Estado habilitado/deshabilitado de la entrada de este certificado

El fichero tiene la estructura siguiente:

```
# Fichero sites.ini
# 
# la seccion "default" contiene definiciones globales
# que se aplican a todas las secciones, salvo que sean sobreescritas
#
[default]
# Ubicacion de cada elemento del certificado en el host destino
# Si no están definidos, el certificado no se intenta distribuir
key_path = "/etc/ssl/private/
cert_path = "/etc/ssl/certs/
chain_path = "/usr/share/ca-certificates/

#
# Lista de certificados que se gestionan
#
# El nombre de la seccion debe coincidir con el CommonName (CN) del certificado
[name.dit.upm.es]
### flag que indica si esta entrada está o no habilitada (Requerido)
cert_enabled=1
#
### Datos del certificado
# Lista separada por comas de SubjectAlternativeNames (Type DNS). (Opcional)
# certbot siempre incluye el CN en esta lista
# Actualmente NO se permiten wildcards
cert_alt_names = ""
### credenciales de acceso al DDNS mediante nsupdate (ddns_keys.ini Requerido)
ddns_credentials = "key1"
### Credenciales de acreditación ACME (fichero acme_creds.ini Requerido)
acme_credentials = "user1"
#
# Datos de instalación del certificado en el host destino
# Nombre del host en el que se va a ubicar el certificado. (Requerido)
cert_host = "host.domain.upm.es"
# Si no están definidos, el certificado no se intenta distribuir
key_path = "/etc/ssl/private/
cert_path = "/etc/ssl/certs/
chain_path = "/usr/share/ca-certificates/

[www.lab.dit.upm.es]
cert_host = "host.domain.upm.es"
cert_alt_names = ""
cert_enabled = 0
```


