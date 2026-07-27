
# Contents and use of hooks files

- This directory contains several examples of post-install/post-renew scripts to be executed on target machine.
They should be copied into remote_machine:/usr/local/bin/certmanager_deploy.sh and personalized as needed

- File '''01-call_certmanager.sh''' is a renewal-hook to certbot, to allow post install/renew operations when using certbot timers.
It should be copied into ''/etc/letsencrypt/renewal-hooks/deploy/'' directory.

- Default action is just call ''certmanager.sh'' with option '''install''', with in turn installs certificates and execute (if any) remote hook
