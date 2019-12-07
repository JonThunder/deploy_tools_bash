#!/bin/bash

# # # USAGE: mk_deploy.sh [ $optionalPathTo_deploy_tools_bash_folder ]

PWD0=${PWD:-$(pwd)}
DIR0=$(dirname "$0")
# if printf '%s' "$0" | egrep '^t?[bcdk]a?sh' >/dev/null ; then
#   DIR0=$PWD0
# fi
FULLDIR0=$(cd "$DIR0" && pwd)
main() {
  deploy_tools_path=${1:-}
  if [[ $deploy_tools_path ]] && [[ -e $deploy_tools_path ]] \
    && [[ ! -d $deploy_tools_path ]] && [[ -f $deploy_tools_path ]] \
    && [[ $(basename "$deploy_tools_path") == deploy_tools.bash ]] ; then
    deploy_tools_path=$(dirname "$deploy_tools_path")
  fi;
  [[ $deploy_tools_path ]] && [[ -d $deploy_tools_path ]] || init
  local sets=$(echo "$-" | sed 's/[is]//g')
  set -exu
  if [[ -z $deploy_tools_path ]] || [[ ! -d $deploy_tools_path ]] ; then
    ( cd "$tmpd" && git clone https://github.com/JonThunder/deploy_tools_bash.git \
      && cd deploy_tools_bash && bash build.sh $DEPLOY_PATH $DEPLOY_UP_LEVELS
    )
    deploy_tools_path="$tmpd/deploy_tools_bash"
  fi ;
  set +exu
  (cd "$DEPLOY_PATH" && source "$deploy_tools_path/deploy_tools.bash" && mk_examples) \
  || die "ERROR $?: Failed to source deploy_tools.bash and run mk_examples"
  set -$sets
  final
}
die() { echo "${1:-ERROR}" 1>&2 ; final ; exit ${2:-2}; }
init() {
  local deploy_dir=$(find * -type d -name .git -prune -o -type d -name deploy | egrep -v "\/\.git\$" | tail -1)
  # echo "deploy_dir=$deploy_dir" 1>&2
  if [[ $deploy_dir ]] ; then
    local rel_ddir=$(realpath --relative-to="$FULLDIR0" $deploy_dir)
    # echo "rel_ddir=$rel_ddir" 1>&2
    DEPLOY_PATH=$(dirname "$rel_ddir")
  else
    DEPLOY_PATH=$(find . -type d -name .git -prune -o -type d -name 'testVM*' | egrep -v "\/\.git\$" | tail -1)
  fi
  DEPLOY_PATH=$(printf '%s' "$DEPLOY_PATH" | sed 's,^\.\/,,')
  if [[ -z $DEPLOY_PATH ]] ; then
    echo "WARNING: Failed to find any 'deploy' folder - or anything named 'testVM*'. Using '.' ($PWD) as the base (that is, creating Vagrantfile here and subfolder 'deploy')." 1>&2
    DEPLOY_PATH='.'
  fi
  [[ $DEPLOY_PATH ]] || die "ERROR: Failed to divine a DEPLOY_PATH"
  DEPLOY_UP_LEVELS='..'
  if [[ $DEPLOY_PATH == '.' ]] ; then
    DEPLOY_UP_LEVELS='.'
  else
    local n=$(echo "$DEPLOY_PATH" | sed 's,[^/],,g' | wc -c);
    local i=1;
    while [[ $i -lt $n ]] ; do DEPLOY_UP_LEVELS="$DEPLOY_UP_LEVELS/.."; i=$((i+1)); done
  fi
  # echo "DEPLOY_PATH=$DEPLOY_PATH" 1>&2
  # echo "DEPLOY_UP_LEVELS=$DEPLOY_UP_LEVELS" 1>&2
  tmpd=$(mktemp -d)
}
final() {
  echo "NOTE: Removing temporary dir $tmpd ($(ls -lart $tmpd))" 1>&2
  rm -rf "$tmpd"
}
cd "$DIR0" && main "$@"
