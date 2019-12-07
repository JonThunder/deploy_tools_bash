# # # USAGE:
# # #   To bootstrap a project that uses this for its deployments, run
# # #     curl https://raw.githubusercontent.com/JonThunder/deploy_tools_bash/master/mk_deploy.sh | bash

die() { echo "${1:-ERROR}" 1>&2 ; exit ${2:-2} ; }

