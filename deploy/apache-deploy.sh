#!/bin/bash
DIR0=$(dirname "$0")
main() {
  BUNDLE=${1:-bundle-prod}
  source deploy_tools.bash
  local tmpd=$(mktemp -d)
  sudo rsync -a "$BUNDLE/var_www"/ "$tmpd"

  apacheu=apache
  apachegrp=apache
  id vagrant >/dev/null && apachegrp=vagrant || true
  if egrep '^www-data:' /etc/passwd ; then apacheu=www-data ; fi ;
  export apacheu ; export apachegrp
  sudo chown -R $apacheu:$apachegrp "$tmpd"
  sudo chown -R $apacheu:$apachegrp "/var/www/html"

  sudo rsync -a "$tmpd"/ /var/www
  sudo rm -rf "$tmpd"

  post_apache_deploy
}
cd "$DIR0" && main "$@"
