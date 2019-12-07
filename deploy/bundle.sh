#!/bin/bash

# # # NOTE: $BUNDLE is usually 'bundle-test' or 'bundle-prod' or similar.
# # #   The $BUNDLE suffix (test or prod, for example) affects a few decisions:
# # #   For example NGROK is not expected to be running for bundle-prod.
# # #   The file deploy_tools.bash defines bundle_git() - that clones a git repo,
# # #   checks out a branch, and fixes strings in the files: It expects
# # #   $FIX_STRINGS_IN_FILES to be defined (perhaps in source_me.bash)
# # #   and it runs fix_${suffix}_strings (like fix_test_strings when
# # #   $BUNDLE is 'bundle-test').

DIR0=$(dirname "$0")
main() {
  BUNDLE=${1:-bundle-test}
  source deploy_tools.bash
  init
  local pwd0=${PWD:-$(pwd)}
  set -x

  # Use a Git URL:
  bundle_git $BUNDLE/server_code git@github.com:user/my_app_server_code.git origin "$SERVER_BRANCH" # $SERVER_BRANCH defined in source_me.bash
  # Or a relative path:
  #   Suppose you have my_app_browser_code and my_deployment_repo in the same folder and my_deployment_repo
  #   has testVM-project1/deploy. Then this relative path to my_app_browser_code will work for
  #   my_deployment_repo/testVM-project1/deploy/bundle-test/client_code
  #   with DEPLOY_PATH=my_deployment_repo/testVM-project1 and DEPLOY_UP_LEVELS=../..
  bundle_git $BUNDLE/client_code ../../../$DEPLOY_UP_LEVELS/my_app_browser_code/.git origin "$CLIENT_BRANCH" # $CLIENT_BRANCH defined in source_me.bash
  
  cd $BUNDLE
  rm -rf var_www || true
  mkdir var_www
  rsync -a --exclude .git server_code/ var_www
  rm -rf var_www/html/static/js || true
  ( cd client_code && ( [[ -d node_modules ]] || npm install ) \
    && npm run build \
    && rsync -a --exclude .git dist/ ../var_www/html
  )
  cd $pwd0
  ( [[ ! -e $BUNDLE.tgz ]] || rm $BUNDLE.tgz )
  tar -czf $BUNDLE.tgz *.sh *.list ansible $BUNDLE/var_www
  # Leaves $BUNDLE.tgz in the same folder as bundle.sh - with $BUNDLE/var_www in it
  # - and also any scripts or ansible config from the same folder as bundle.sh.
}
init() {
  if [[ $BUNDLE == 'bundle-prod' ]] && [[ -z $PROD_HOSTNAME ]] ; then
    die "ERROR: $BUNDLE without PROD_HOSTNAME (consider defining it in source_me.prod.bash or else exporting it before running bundle.sh)"
  fi
  npm --version 2>&1 | egrep '^3\.' || die "ERROR: $PWD / $0 wants npm version 3.x"
  check_ngrok
}
fix_prod_strings() {
  local f=$1
  hostname=${PROD_HOSTNAME:-example.com}
  # Note that PROD_HOSTNAME should be defined in source_me.prod.bash or else exported before invoking deploy.sh or bundle.sh: export PROD_HOSTNAME=example.com; deploy.sh
  safe_sed "example\.com" "$hostname" $f
  safe_sed CONFIG_ME_APPHOSTNAME "$hostname" $f
  safe_sed CONFIG_ME_DB_ROOT_P "$DB_ROOT_P" $f
  # Note that DB_ROOT_P should be defined in source_me.prod.bash.
  # Let's hope it is a different password than the test password from source_me.bash
}
fix_test_strings() {
  local f=$1
  safe_sed "example\.com" "$NGROK_HOST" $f
  safe_sed CONFIG_ME_APPHOSTNAME "$NGROK_HOST" $f
  safe_sed CONFIG_ME_DB_ROOT_P "$DB_ROOT_P" $f
}
cd "$DIR0" && main "$@"
