#!/usr/local/bin/php -f
<?php

// NOTA: este script asume que pfsense ya tiene un
// certificado de nombre "fw.mi.comain.com"
// en caso negativo, lo crea y lo inserta, pero
// hay que configurar pfsense desde la web para 
// que lo utilice por defecto 
// en system->advanced->ssl/tls certificate

require_once ("/etc/inc/config.inc");
require_once ("/etc/inc/certs.inc");

// Define paths to the pushed certificate files
$cert_path = '/root/certs/fw.mi.comain.com_fullchain.pem';
$key_path  = '/root/certs/fw.mi.comain.com_key.pem';

// Ensure files exist
if (!file_exists($cert_path) || !file_exists($key_path)) {
    echo "Error: Certificate or key file missing.\n";
    exit(1);
}

// load certificate and key into memory
$cert_content = file_get_contents($cert_path);
$key_content  = file_get_contents($key_path);

// Define a descriptive name for your certificate in pfSense
$cert_name = "fw.mi.comain.com";
$found_descr = false;

// 1. Check if the certificate entry already exists, then update it
if (isset($config['cert']) && is_array($config['cert'])) {
    foreach ($config['cert'] as &$cert) {
        if ($cert['descr'] == $cert_name) {
            $cert['crt'] = base64_encode($cert_content);
            $cert['prv'] = base64_encode($key_content);
            $found_descr = true;
            echo "Updated existing certificate: {$cert_name}\n";
            break;
        }
    }
}

// 2. If it does not exist, create a brand new entry
if (!$found_descr) {
    $new_cert = array(
        'refid' => uniqid(),
        'descr' => $cert_name,
        'crt'   => base64_encode($cert_content),
        'prv'   => base64_encode($key_content)
    );
    $config['cert'][] = $new_cert;
    echo "Created new certificate entry: {$cert_name}\n";
}

// 3. Write configuration changes cleanly to the XML store
write_config("Updated external Let's Encrypt certificate via CLI script.");

// 4. Reload the webConfigurator to apply the new certificate immediately
echo "Restarting WebConfigurator...\n";
exec("/etc/rc.restart_webgui");

// Don't forget to set the new certificate as the default in the pfSense 
// web interface under System -> Advanced -> Admin Access -> SSL/TLS Certificate.
?>
