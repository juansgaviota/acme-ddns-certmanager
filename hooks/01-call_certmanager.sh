#!/bin/bash
#
# to be installed under /etc/letsencrypt/renewal-hooks/deploy
# call to certmanager.sh when a certificate is created or renewed
#
# certbot stores /path/to/cert/directory in RENEWED_LINEAGE env variable
certmgr="/usr/local/bin/certmanager.sh"
[ -x "${certmgr}" ] && "${certmgr}" install --quiet 