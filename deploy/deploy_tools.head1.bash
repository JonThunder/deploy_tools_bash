# # # USAGE:
# # #   To bootstrap a project that uses this for its deployments, run
# # #     curl https://raw.githubusercontent.com/JonThunder/deploy_tools_bash/master/mk_deploy.sh | bash

if ! LC_ALL=C type -t final | grep '^function$' ; then
  final() { true ; }
fi
die() { echo "${1:-ERROR}" 1>&2 ; final; exit ${2:-2} ; }
