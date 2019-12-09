#!/bin/bash

# # # USAGE: db-deploy.sh # Deploys *.sql files from $BUNDLE/db_sql to mysql
# # #        db-deploy.sh bundle-test # Deploys *.sql files from bundle-test/db_sql to mysql (overrides any other defined $BUNDLE)
# # # NOTE: $BUNDLE defaults to bundle-prod
# # # NOTE: if ./db_sql_large exists (relative to db-deploy.sh), it loads *.sql.gz and *.sql files from there first

PWD0=${PWD:-$(pwd)}
DIR0=$(dirname "$0")
main() {
  BUNDLE=${1:-bundle-prod}
  source deploy_tools.bash
  tmpf=$(mktemp)
  err=$(echo 0 | tee $tmpf)
  db_sql_large
  db_sql
}
db_sql_large() {
  local pwd0=${PWD:-$(pwd)}
  local touchf=/srv/provisioned/db_done_loading_large_sources.touch
  if [[ -d ./db_sql_large ]] \
    && [[ ! -f $touchf ]] \
  ; then
    cd ./db_sql_large
    load_db_files '.sql.gz' '\.sql\.gz' 'gunzip -c'
    load_db_files '.sql' '\.sql' 'cat'
    touch $touchf
    cd "$pwd0"
  fi ;
}
db_sql() {
  local pwd0=${PWD:-$(pwd)}
  local e
  if [[ -d "$BUNDLE/db_sql" ]] ; then
    cd "$BUNDLE/db_sql" || die "ERROR $?: Failed to cd $BUNDLE/db_sql"
    load_db_files '.structure.sql' '\.structure\.sql' 'cat'
    load_db_files '.sql' '\.sql' 'cat'
    cd "$pwd0"
  fi ;
}
load_db_files() {
  local ls_suffix=$1
  local sed_strip_suffix=$2
  local stdout_dump=${3:-cat}
  errf=${errf:-}
  local _errf=${errf:-$(mktemp)}
  local e
  ls *$ls_suffix | while read f ; do
    local db=$(printf '%s' "$f" | sed "s/$sed_strip_suffix\$//")
    echo "NOTE: Loading $f into database $db" 1>&2
    if ! $stdout_dump "$f" | mysql $db ; then
      e=$?
      echo "ERROR $e: Failed to gunzip and mysql load $f"
      printf '%s' "$e" > $_errf
    fi
  done
  err=$(cat $_errf)
  [[ $errf ]] || rm "$_errf"
  [[ $err -eq 0 ]] || die "ERROR $err: Failed to $stdout_dump *$ls_suffix files into mysql"
}
cd "$DIR0" && main "$@"
