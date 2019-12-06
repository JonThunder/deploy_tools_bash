#!/bin/bash
main() {
  BUNDLE=${1:-bundle-prod}
  local bundle_f=${1:-/tmp/$BUNDLE.tgz}
  mkdir -p /tmp/deploy
  cd /tmp/deploy && tar -xzf "$bundle_f"
  if [[ ! -d /srv/deploy ]] ; then
    mkdir -p /srv
    mv /tmp/deploy /srv/deploy
  else
    if which rsync >/dev/null 2>&1 ; then
      rsync -a --exclude .git /tmp/deploy/ /srv/deploy
    else
      date=$(date -u +'%Y%m%dT%H%M%S)
      mv /srv/deploy /srv/deploy.bak$date
      mv /tmp/deploy /srv/deploy
    fi
  fi
  PROD_DEPLOY=true bash /srv/deploy/provision.sh
}
main "$@"
