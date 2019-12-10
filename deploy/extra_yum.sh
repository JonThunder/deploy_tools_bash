#!/bin/bash
DIR0=$(dirname "$0")
BASE=$(basename "$0")
main() {
  badf=/srv/provisioned/bad_extra_packages.txt ;
  [[ -d /srv/provisioned ]] || mkdir -p /srv/provisioned
  [[ -e $BASE.list ]] || die "ERROR: $0 expects a file named $0.list"
  while read p ; do
    if [[ -z $p ]] ; then continue ; fi
    if ! yum -y install -q $p ; then
      echo "ERROR $?: Failed to install $p" ;
      printf '%s\n' "$p" >> "$badf"
    else
      printf '%s\n' "$p" >> /srv/provisioned/installable_extra_packages.txt ;
    fi ;
  done < $BASE.list
  [[ -s "$badf" ]] && die "ERROR: Tried but failed to install some packages:$(echo; cat "$badf")" || true
}
die() { echo "${1:-ERROR}" 1>&2 ; exit ${2:-2} ; }
cd "$DIR0" && main "$@"
