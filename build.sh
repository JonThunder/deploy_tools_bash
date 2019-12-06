#!/bin/bash
# # # USAGE: build.sh $DEPLOY_PATH $DEPLOY_UP_LEVELS
# # #   Where DEPLOY_PATH is the path from your project root to the deploy folder
# # #   and DEPLOY_UP_LEVELS is the levels "up" from it: For example,
# # #   for a DEPLOY_PATH like deployments/testVM, the DEPLOY_UP_LEVELS would be
# # #   '../..' (two levels up).
# # #   Defaults: DEPLOY_PATH='.'; DEPLOY_UP_LEVELS='.'
DIR0=$(dirname "$0")
main() {
  local DEPLOY_PATH=${1:-.}
  local DEPLOY_UP_LEVELS=${2:-.}
  source deploy/deploy_tools.head2.bash
  cp deploy/deploy.sh.template deploy/deploy.sh
  cp Vagrantfile.template Vagrantfile
  for f in Vagrantfile deploy/deploy.sh ; do
    safe_sed CONFIG_ME_DEPLOY_PATH "$DEPLOY_PATH" "$f"
    safe_sed CONFIG_ME_DEPLOY_UP_LEVELS "$DEPLOY_UP_LEVELS" "$f"
  done
  ( cat deploy/deploy_tools.head1.bash
    cat deploy/deploy_tools.head2.bash
    mk_script "deploy.sh" mk_deploy_script
    mk_script "../Vagrantfile" mk_vagrantfile_script
    mk_script "provision.sh" mk_provision_script
    echo "# # # Example ansible config:"
    echo "mk_ansible_config() {"
    echo "  mkdir -p ansible"
    mk_ansible_script "playbook.yml"
    mk_ansible_script "requirements.yml"
    mk_ansible_script "vars.yml"
    echo -e "} # END: mk_ansible_config()\n"
    mk_script "provision-db.sh" mk_provision_db_script
    mk_script "extra_yum.sh" mk_extra_yum_script
    mk_script "extra_yum.sh.list" mk_extra_yum_list
    mk_script "bundle.sh" mk_bundle_script
    mk_script "apache-deploy.sh" mk_apache_deploy_script
    mk_script "deploy-prod.sh" mk_deploy_prod_script
    cat deploy/deploy_tools.foot.bash
  ) > deploy_tools.bash
  cp -f deploy_tools.bash deploy/
}
mk_script() {
  local file=$1
  local function=$2
  local no_header=${3:-} # '' or 'no_header'
  if [[ ! -f deploy/$file ]] ; then
    echo "WARNING: Found no such file as deploy/$file (for function $function)" 1>&2
    return 1;
  fi
  [[ $no_header ]] || echo "# # # Example $file:"
  echo "$function() {"
  echo "  cat > $file <<'EOF'"
  cat deploy/$file
  echo -e "EOF\n} # END: $function(): $file\n"
}
mk_ansible_script() {
  local file=$1
  if [[ ! -f deploy/ansible/$file ]] ; then
    echo "WARNING: Found no such file as deploy/ansible/$file" 1>&2
    return 1;
  fi
  echo "  cat > ansible/$file <<'EOF'"
  cat deploy/ansible/$file
  echo -e "EOF\n# END: $file"
}
cd "$DIR0" && main "$@"
