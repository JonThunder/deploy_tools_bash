#!/bin/bash
DIR0=$(dirname "$0")
main() {
  BUNDLE=${1:-bundle-prod}
  source deploy_tools.bash
  rsync -a "$BUNDLE/var_www"/ /var/www
  post_apache_deploy
}
cd "$DIR0" && main "$@"
