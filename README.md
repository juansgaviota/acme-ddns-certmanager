# CertManager

Utilidad para gestión centralizada y distribución de certificados generados con API ACME, certbot mediante validación DNS-01

## Descripción

Este script permite centralizar en un único servidor la solicitud, y renovación de certificados mediante certbot/ACME mediante validación por DNS, sin necesidad de que el servidor tenga que estar accesible por HTTPs

Asímismo se controla la copia y distribución de los certificados obtenidos a cada servidor que los requiera

Se pueden manejar certificados de múltiples hosts, múltiples servidores DNS, así como declarar las claves de acceso al ddns-update de cada servidor dns y las credenciales ACME que utilizará cada certificado

Las operaciones se realizan consultando un ficheros de configuración de certificados (**sites.ini**), que a su vez utiliza las configuraciones de gestión del DNS y credenciales ACME de los ficheros asociados

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
    Fichero de credenciales de acceso ACME de los diversos usuarios
- etc/ddns_keys.ini
    Fichero de configuración de acceso por DDNS a los diferentes servidores
    de DNS
- etc/sites.ini
    Fichero de declaración de diversos certificados a gestionar por la aplicación

## Instalación

**NOTA**: Esta aplicación ha sido instalada y probada en sistemas Debian-13 y Ubuntu-24.04. Es posible que otras distribuciones de linux requieran otros paquetes y/o modos de instalación

### Requisitos previos

CertManager requiere de *certbot* >= 4.0 para su ejecución, así como del plugin *python3-certbot-dns-rfc2136*

En sistemas Debian 12 o superior, los paquetes vienen incluídos en la distribución base:
> sudo apt install -y certbot python3-certbot-dns-rfc2136

En sistemas Ubuntu, es necesario instalar los paquetes mediante *snap*, pues la versión que viene en la distribución base está desactualizada y no es operativa:
> sudo snap install certbot certbot-dns-rfc2136

Para generar (Opcional) la versión HTML de este documento en la carpeta
de documentación, es preciso instalar el paquete *md2html*
> sudo apt install md2html

Para la distribución de los certificados a la máquina destino, se precisa de paquete openssh-client en el equipo donde se instale CertManager. Así mismo el equipo destino
deberá tener instalado openssh-server y configurado de manera que se permita el acceso sin contraseña, esto es: por clave pública/privada (en el fichero **/root/.ssh/authorized_keys**)
> sudo apt install ssh

En los casos en que no es posible la distribución automática del certificado, los datos se envian por correo electrónico al solicitante. Para poder realizar esta tarea es necesaria la instalación del paquete *sendemail* ( no confundir con "sendmail" )
> sudo apt install sendemail

### Descarga e instalación

Para instalar la aplicación:

- Descargar y descomprimir el fichero desde github
    > wget <https://github.com/jonsito/acme-ddns-certmanager/archive/refs/heads/main.zip>
    > unzip main.zip

- Alternativamente, si se dispone de "git" se puede clonar el repositorio
    > git clone <https://github.com/jonsito/acme-ddns-certmanager.git>

- Como usuario "root" ejecutar *install.sh*

- Una vez instalado, seguir las instrucciones para personalizar los diversos ficheros de configuración, así como configurar DNS para que permita validación DNS-01  
**IMPORTANTE** los ficheros bajo la carpeta /etc/certmanager deben estar con permisos root:root y protegidos contra lectura/escritura pública (640)

- (opcional) La instalación de certbot programa automáticamente un timer para ejecutar dicha aplicación de manera periódica. Puesto que en este caso certbot se ejecuta desde CertManager, hay que desactivar dicho timer:
    > sudo systemctl disable --now certbot.timer

## Ejecución

Las diversas opciones de ejecución se pueden obtener mediante
> certmanager --help

```text
Certificate management with certbot/DNS-01 validation
Version: 1.2 2026-07-22
Author: Juan Antonio Martínez <juanantonio.martinez@upm.es>
License: MIT (https://opensource.org/license/mit)
Available docs: /usr/share/doc/certmanager

Usage: ./certmanager.sh <action> [options] [cert_name]

  Actions:
  list                List current certificates
  create              Create/renew certificate
  delete              Delete certificate
  revoke              Revoke certificate
  renove              Force certificate renewal
  renove-all          Renew all certs next to expire (30 days or less)
  enable              Mark certificate as active in conf file
  disable             Mark certificate as inactive in conf file
  install             Install/remove certificate into (remote) server

  Options:
  -? | -h | --help    Show usage and exit
  -v | --verbose      Send certmanager/certbot logs to console (def: don't)
  -l | --list         List current certificates
  -f | --force        Force certbot to renew/create even if not expired
  -i | --install      Install created/renoved cert. into server (def: don't)
  -m | --mail <addr>  Send log via mail to addr

```

### Descripción de las diversas opciones y operaciones

***-h -? --help***  
    Muestra las información de versión y diversas opciones

***-v --verbose***
    Vuelca la información de ejecución tanto en el fichero de logs como en pantalla

***-q --quiet***  
    No presenta mensajes en pantalla (salvo error en la ejecución)

***-f --force***
    Si el certificado existe y no está próximo a caducar, indica a la opción --create que
    debe forzar su re-creación. Esta opción es necesaria en el caso en que queramos cambiar las credenciales del usuario que ha creado el certificado

***-m --mail address***  
    Envia por correo electrónico al destinatario indicado el fichero de registro de ejecución de la aplicación  
    Para que este envío tenga lugar, deberá tener la aplicación **mail** instalada en el equipo, así como estar correctamente configurado el envío de correo

***-i --install***
    Se procede a instalar en la máquina destino el certificado asociado
    a una operación de create/renove
    En el caso de que la operación sea ''delete'' este flag indica que el fichero debe ser eliminado de la máquina destino

***list***  
    Muestra la lista de certificados registrados en el fichero sites.ini, así como
    su estado habilitado/deshabilitado
    Si se incluye la opción **--verbose** muestra además la información del certificado (si está habilitado)

***create***  
    Crea el certificado con el nombre indicado. Dicho nombre debe corresponder a una sección del fichero **sites.ini**  
    Si el certificado está creado y está próximo (30 días o menos) a expirar, se procede a la renovación de éste  
    Si el certificado está marcado como **disabled** en el fichero **sites.ini** , el proceso de creación/renovación no se realiza. No obstante, si se especifica **--install**
    y el certificado ya existe, se procederá a su instalación en la máquina destino

***delete***  
    Borra el certificado dado, y lo marca como **disabled** en el fichero de configuración  
    No se revoca el certificado, por lo que salvo que se indique --install, el certificado
    seguirá siendo válido hasta que caduque  
    Si se indica la opción --install, se procede también al borrado en el equipo destino  

***revoke***  
    Procede a la revocación del certificado, y lo marca como **disabled** en el fichero de configuración **sites.ini**

***enable | disable***  
    Procede a habilitar/deshabilitar la entrada correspondiente en el fichero **sites.ini**

***renove***  
    Si el certificado está marcado como **enabled** se procede a su renovación, con independencia de la fecha de expiración

***renove-all***  
    Recorre la lista de certificados marcados como **enabled** en el fichero de configuración, y procede a su renovación si están proximos a expirar ( o ya están expirados )

***install***  
    Se procede a la distribución de los certificados a su máquina destino, tal y como se indica en el fichero **sites.ini**
    No se crean ni renuevan certificados, solo se distribuye el ya existente
    La distribución se realiza mediante el comando **ssh** por lo que el equipo destino deberá tener habilitado el servicio **sshd** y permitir el acceso por pares de claves publico/privada. ( fichero **authorized_keys**)

## Configuración

### Fichero de credenciales ACME (acme-creds.ini)

En este fichero se guardan las diversas credenciales de uso del API ACME para conectarse al proveedor de certificados. La forma de obtener estas credenciales depende del proveedor:

- *LetsEncrypt* no requiere de credenciales para trabajar con certbot,
pues usa autenticación interna. No obstante en el fichero acme-creds.ini necesitaremos una entrada para esta conexión (ver fichero de ejemplo)
- Para el caso de *HARICA*, el usuario debe:
  - Conectarse a la Web de Gestión de Harica <https://cm.harica.gr/Login>
  - Iniciar sesión con su usuario/contraseña (academic login)
  - En la pestaña "ACME" crear una cuenta ACME EAB
  - Desplegando la vista de información de la cuenta, aparecen
    los datos de *KeyID*, *HMAC Key* y *Server URL*, que deberán incorporarse a este fichero **acme_creds.ini**

El siguiente ejemplo ilustra una configuración típica:

```ini
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
Uso: **tsig2ini.sh dnsipaddr dns-keyfile.conf**

Ejemplo de utilización:

- Generar clave y guardar en el servidor dns

    > root@dns-server# tsig-keygen -a hmac-sha256 "ddns-key" > /etc/bind/ddns-key.conf

- Con la utilidad tsig2ini.sh generar datos para el fichero ddns-keys.ini

    >root@certmgrhost# tsig2ini.sh dns.server.ip.addr /etc/bind/ddns-key.conf >> /etc/certmanager/ddns_keys.ini

- En el fichero de zona nos aseguraremos que los campos CAA están correctamente
  configurados para admitir el emisor de certificados que vayamos a utilizar:

  >cat zone.example.com.db

```text
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

```text
  example.com. IN CAA 0 issue "example.net; \
     accounturi=https://example.net/account/1234; \
     validationmethods=dns-01"
```

   Consultar cada caso concreto y editar la zona DNS acorde con dicho proveedor

- En el fichero named.conf.local, incluímos en la zona los datos necesarios para poder admitir DNS updates

    >root@dnsserver# vi /etc/bind/named.conf.local

```text
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
    //  grant ddns-key name _acme-challenge.lab.dit.upm.es. TXT;
    //  grant ddns-key name _acme-challenge.host1.lab.dit.upm.es. TXT;
    //  grant ddns-key name _acme-challenge.host2.lab.dit.upm.es. TXT;
    //};
};
...
```

En el ejemplo anterior vemos que se pueden usar las opciones "allow-update", especificando host y clave, o bien la opción "update-policy" que permite un ajuste más fino por dominios y campos que se puedan actualizar

La estructura del fichero de utilizado por CertManager para gestionar las claves de gestión de DNS updates es la siguiente

```ini
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
- Email del solicitante
- Credenciales acme
- Credenciales de acceso al dns dinámico
- Información para instalación en servidor destino
- Estado habilitado/deshabilitado de la entrada de este certificado

El fichero tiene la estructura siguiente:

```ini
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
key_path = "/etc/ssl/private/"
cert_path = "/etc/ssl/certs/"
chain_path = "/usr/share/ca-certificates/"

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
# Direccion de correo del solicitante del certificado
cert_requester = "owner.mail@domain.upm.es"
# Si no están definidos, el certificado no se intenta distribuir
key_path = "/etc/ssl/private/"
cert_path = "/etc/ssl/certs/"
chain_path = "/usr/share/ca-certificates/"

[www.sub.example.com]
cert_host = "host.sub.example.com"
cert_alt_names = ""
cert_enabled = 0
```

### Configuración de las notificaciones por correo

Cuando no es posible realizar una instalación automática de los certificados
debido a que no existen paths de instalación definidos, ''certmanager.sh'' empaqueta los certificados en un fichero ''.tar.gz'' y lo envía por correo al solicitante del certificado.
Para podere realizar esta acción es preciso definir el mailer y las credenciales del usuario que va a enviar el correo.

Para ello editaremos el fichero /etc/certmanager/mailer.ini, indicando los parámetros
adecuados

```text
[mailer]
smtp_server = "localhost"
smtp_port = 587
smtp_username = "user@example.com"
smtp_password = "password"
```

Si este fichero no existe o está incompleto, no se ejecuta acción alguna

## Renovación automática de certificados

CertManager puede utilizarse para renovar y distribuir automáticamente los
certificados. Para ello utilizaremos el servicio **cron**, editando el fichero *crontab* correspondiente

Por ejemplo para procesar semanalmente, y en su caso renovar los certificados próximos a caducar antes de 30 días, generaremos una línea en el crontab
tal que sigue:

> crontab -e

```text
...
0 6 * * 0 /usr/local/bin/certmanager.sh --renove-all --install --mail <certadmin@example.com>
...
```

**NOTA** certbot instala por defecto un timer para la renovación automática de certificados. Es preciso deshabilitar este timer para poder utilizar correctamente CertManager.
Consultar el apartado de Instalación para proceder
