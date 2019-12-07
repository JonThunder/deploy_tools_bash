# # # USAGE:
# # #   To bootstrap a project that uses this for its deployments, run
# # #     curl https://raw.githubusercontent.com/JonThunder/deploy_tools_bash/master/mk_deploy.sh | bash

die() { echo "${1:-ERROR}" 1>&2 ; exit ${2:-2} ; }
source_files() {
  f=source_me.bash ; [[ -f $f ]] && source $f || echo "WARNING: Found no $f" 1>&2
  f=custom_deploy_source.bash ; [[ ! -f $f ]] || source $f
  if [[ $BUNDLE ]] ; then
    if [[ $BUNDLE == 'bundle-prod' ]] ; then
      if [[ ! -e source_me.prod.bash ]] ; then
        die "ERROR: BUNDLE = $BUNDLE but found no source_me.prod.bash with production-worthy passwords and configurations"
      fi ;
      source ./source_me.prod.bash
    fi
  fi
}
source_files

