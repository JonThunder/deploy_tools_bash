#!/bin/bash

# # # USAGE:
# # #   provision.sh # To deploy normally (with ngrok)
# # #   PROD_DEPLOY=true provision.sh # To deploy to production (no ngrok)

export PROD_DEPLOY=${PROD_DEPLOY:-false}
BUNDLE=${BUNDLE:-}

PWD0=${PWD:-$(pwd)}
DIR0=$(dirname "$0")
FULLDIR0=$(cd $DIR0 && pwd)

YES_NGROK=true
if [[ $PROD_DEPLOY == true ]] ; then
  YES_NGROK=false
  # NOTE: You can add other "YES_" variables here like YES_DEBUG_APP and add logic to deploy some test-only or dev-only debug tool.
  [[ $BUNDLE ]] || BUNDLE='bundle-prod'
fi ;
[[ $BUNDLE ]] || BUNDLE='bundle-test'

main() {
  init
  pkg_installs
  init_admins
  config_ngrok
  run_ansible
  apache_config
  last_steps
  final
}
init() {
  mkdir -p /srv/provisioned
  # touch /srv/provisioned/provisioning.touch # A handy way to check if the provision.sh script is running
  source deploy_tools.bash
  provisioned_count=$(cat /srv/provisioned/count 2>/dev/null)
  [[ $provisioned_count ]] && provisioned_count=$((provisioned_count + 1)) \
  || provisioned_count=1
  echo $provisioned_count > /srv/provisioned/count
  if [[ ! -d /srv/deploy ]] ; then
    if [[ ! -d /srv/vagrant_synced_folder ]] ; then
      die "ERROR: Failed to find /srv/deploy folder (or even the /srv/vagrant_synced_folder). How do you intend to deploy to this server? How are you running this script ($0)?"
    fi
    cp -rp "$DIR0"/ /srv/deploy || die "ERROR $?: Failed to cp $DIR0 to /srv/deploy"
  fi ;
  init_git
}
# # # NOTE: Define EXTRA_PACKAGES or else redefine pkg_installs to control OS package installation.
# # #   Also, at the end of last_steps, a script called extra_yum.sh will be run, if it exists (and if you are provisioning a yum server).
# # # NOTE: prep_ansible(), invoked by run_ansible, is also a good one to consider overriding
final() {
  true
  # f=/srv/provisioned/provisioning.touch [[ ! -f $f ]] || rm $f
}

cd "$DIR0" && main "$@"
