# CertManager

Utilidad para gestión centralizada y distribución de certificados generados con API ACME, certbot mediante validación DNS-01

## Descripción

Este script permite centralizar en un único servidor la solicitud, y renovación de certificados mediante certbot/ACME mediante validación por DNS, sin necesidad de que el servidor tenga que estar accesible por HTTPs

Asímismo se controla la copia y distribución de los certificados obtenidos a cada servidor que los requiera

Se pueden manejar certificados de múltiples hosts, múltiples servidores DNS, así como declarar las claves de acceso al ddns-update de cada servidor dns y las credenciales ACME que utilizará cada certificado

## Estructura
- certmanager.sh
    Script de gestión
- lib_ini.sh:
    Biblioteca de gestión de ficheros .ini
- tsig2ini.sh:
    Utilidad para conversión de ficheros creados con tsig-genkey
    al formato .ini utilizado por certmanager
- install.sh
    Programa de (des)instalación de la aplicación
- etc/acme_creds.ini
    Fichero de credenciales de acceso del usuario ACME
- etc/ddns_keys.ini
    Fichero de configuración de acceso por DDNS a los diferentes servidores
    de DNS
- etc/cert_list.ini
    Fichero de declaración de diversos certificados a gestionar por la aplicación

## Instalación
**NOTA**: Esta aplicación ha sido instalada y probada en sistemas Debian-13 y Ubuntu-24.04. Es posible que otras distribuciones de linux requieran otros paquetes y/o modos de instalación

### Requisitos previos

CertManager requiere de *certbot* >= 4.4 para su ejecución, así como del plugin *python3-certbot-dns-rfc2136*

En sistemas Debian 12 o superior, los paquetes vienen incluídos en la distribución base:
> sudo apt install -y certbot python3-certbot-dns-rfc2136

En sistemas Ubuntu, es necesario instalar los paquetes mediante *snap*, pues la versión que viene en la distribución base está desactualizada y no es operativa:
> sudo snap install certbot certbot-dns-rfc2136

Para generar (Opcional) la versión HTML de este documento en la carpeta 
de documentación, es preciso instalar el paquete *md2html*
> sudo apt install md2html

### Descarga e instalación

Para instalar la aplicación:

- Descargar y descomprimir el fichero desde github
    > wget https://github.com/jonsito/acme-ddns-certmanager/archive/refs/heads/main.zip

    > unzip main.zip

- Alternativamente, si se dispone de "git" se puede clonar el repositorio
    > git clone https://github.com/jonsito/acme-ddns-certmanager.git

- Como usuario "root" ejecutar *install.sh*

- Una vez instalado, seguir las instrucciones para personalizar los diversos ficheros de configuración, así como configurar DNS para que permita validación DNS-01
**IMPORTANTE** los ficheros bajo la carpeta /etc/certmanager deben estar con permisos root:root y protegidos contra lectura/escritura pública

- La instalación de certbot programa automáticamente un timer para ejecutar dicha aplicación de manera periódica. Puesto que en este caso certbot se ejecuta desde CertManager, hay que desactivar dicho timer:
    > sudo systemctl disable --now certbot.timer

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
  -a | --renove-all       Renew all certificates next to expire (30 days or less)
  -r | --renove <name>    Force renove certificate <name>
  -m | --mail <dest>      Send log via mail to <dest>
  -i | --install          Install certificate to (remote) server
                          (default is do not install)
```

## Configuración

### Fichero de credenciales ACME (acme-creds.ini)

En este fichero se guardan las diversas credenciales de uso del API ACME para conectarse al proveedor de certificados. La forma de obtener estas credenciales depende del proveedor:

- *LetsEncrypt* no requiere de credenciales para trabajar con certbot, 
pues usa autenticación interna. No obstante en el fichero acme-creds.ini necesitaremos una entrada para esta conexión (ver fichero de ejemplo)
- Para el caso de *HARICA*, el usuario debe:
    - Conectarse a la Web de Gestión de Harica https://cm.harica.gr/Login
    - Iniciar sesión con su usuario/contraseña (academic login)
    - En la pestaña "ACME" crear una cuenta ACME EAB
    - Desplegando la vista de información de la cuenta, aparecen
    los datos de *KeyID*, *HMAC Key* y *Server URL*, que deberán incorporarse
    a este fichero **acme_creds.ini**

El siguiente ejemplo ilustra una configuración típica:
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
# letsencrypt no utiliza credenciales (utiliza credenciales generados
# internamente en el cliente certbot), por lo que podemos dejar kid y
# hmac_key vacios
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
Es importante recordar que CertManager asocia certificados con usuarios; esto es, las operaciones relacionadas con un determinado certificado, se realizarán con las credenciales ACME de dicho usuario. Si manualmente se cambia el usuario en el fichero *sites.ini*, es posible que las operaciones de renove,delete o revoke con certificados emitidos por Harica resulten en error

### Configuración DNS ( plugin python3-certbot-dns-rfc2136 )

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

    > root@dns-server# tsig-keygen -a hmac-sha256 "ddns-key" > /etc/bind/ddns-key.conf

- Con la utilidad tsig2ini.sh generar datos para el fichero ddns-keys.ini

    >root@certmgrhost# tsig2ini.sh dns.server.ip.addr /etc/bind/ddns-key.conf >> /etc/certmanager/ddns_keys.ini

- En el fichero de zona nos aseguraremos que los campos CAA están correctamente
  configurados para admitir el emisor de certificados que vayamos a utilizar:

  >cat zone.example.com.db

```
  ...
 ; declaracion de CA's autorizadas para emitir certificados para example.com
 IN CAA 0 issue "harica.gr"
 IN CAA 0 issue "letsencrypt.org"
 IN CAA 0 issue "fnmt.es"
 IN CAA 0 issue "sectigo.com"
 IN CAA 0 issue "digicert.com"
 ; no permitir wildcard certificates
 IN CAA 0 issuewild ";"
 ; en caso de abuso, avisar
 IN CAA 0 iodef "mailto:dnsmaster@example.com"
  ...
```
  Algunas autoridades de certificación piden datos adicionales para los RR de tipo CAA, para poder realizar validación de origen de solicitud del certificado:
```
  example.com. IN CAA 0 issue "example.net; \
     accounturi=https://example.net/account/1234; \
     validationmethods=dns-01"
```
   Consultar cada caso concreto y editar la zona DNS acorde con dicho proveedor

- En el fichero named.conf.local, incluímos en la zona los datos necesarios para poder admitir DNS updates

    >root@dnsserver# vi /etc/bind/named.conf.local

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

En el ejemplo anterior vemos que se pueden usar las opciones "allow-update", especificando host y clave, o bien la opción "update-policy" que permite un ajuste más fino por dominios y campos que se puedan actualizar

La estructura del fichero de utilizado por CertManager para gestionar las claves de gestión de DNS updates es la siguiente

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
# Target DNS server (IPv4 or IPv6 address, not a hostname)
dns_rfc2136_server = ....
...

```
La opción *dns_rfc2136_sign_query* con valor true indica que se debe verificar que el servidor indicado es el SOA de la zona. Lo normal es dejarlo en false

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
# credenciales de acceso acme y ddns
acme_credentials = "default"
ddns_credentials = "ddns-key"
# Ubicacion de cada elemento del certificado en el host destino
# Si no están definidos, el certificado no se intenta distribuir
key_path = "/etc/ssl/private/
cert_path = "/etc/ssl/certs/
chain_path = "/usr/share/ca-certificates/

#
# Lista de certificados que se gestionan
#
# El nombre de la seccion debe coincidir con el CommonName (CN) del certificado
[name.example.com]
### flag que indica si esta entrada está o no habilitada (Requerido)
cert_enabled=1
#
### Datos del certificado
# Lista separada por comas de SubjectAlternativeNames (Type DNS). (Opcional)
# certbot siempre incluye el CN en esta lista
# Actualmente NO se permiten wildcards
cert_alt_names = ""
### credenciales de acceso al DDNS mediante nsupdate (fichero ddns_keys.ini Requerido)
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

[www.sub.example.com]
cert_host = "host.sub.example.com"
cert_alt_names = ""
cert_enabled = 0
```

## Renovación automática de certificados

CertManager puede utilizarse para renovar y distribuir automáticamente los
certificados. Para ello utilizaremos el servicio **cron**, editando el fichero *crontab* correspondiente

Por ejemplo para procesar semanalmente, y en su caso renovar los certificados próximos a caducar antes de 30 días, generaremos una línea en el crontab
tal que sigue:

> crontab -e

```
...
0 6 * * 0 /usr/local/bin/certmanager.sh --renove-all --expire 30 --install --mail <certadmin@example.com>
...
```
**NOTA** certbot instala por defecto un timer para la renovación automática de certificados. Es preciso deshabilitar este timer para poder utilizar correctamente CertManager.
Consultar el apartado de Instalación para proceder.

