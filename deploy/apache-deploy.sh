#!/bin/bash
DIR0=$(dirname "$0")
main() {
  BUNDLE=${1:-bundle-prod}
  source deploy_tools.bash
  local tmpd=$(mktemp -d)
  sudo rsync -a "$BUNDLE/var_www"/ "$tmpd"

  local apacheu=apache
  local apachegrp=apache
  id vagrant && apachegrp=vagrant || true
  if egrep '^www-data:' /etc/passwd ; then apacheu=www-data ; fi ;
  sudo chown -R $apacheu:$apachegrp "$tmpd"

  sudo rsync -a "$tmpd"/ /var/www
  sudo rm -rf "$tmpd"

  post_apache_deploy
}
cd "$DIR0" && main "$@"
