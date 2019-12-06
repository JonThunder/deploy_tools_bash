#!/bin/bash
DIR0=$(dirname "$0")
main() {
  source deploy_tools.bash
  set -x
  # if [[ ! -e /root/.mylogin.cnf ]] && [[ $DB_ROOT_P ]] && which mysql_config_editor ; then
  f=/root/.my.cnf
  if which mysql_config_editor 2>/dev/null; then
    f=/root/.mylogin.cnf
  fi
  if [[ ! -e $f ]] && [[ $DB_ROOT_P ]] ; then
    if which mysql_config_editor 2>/dev/null; then
      unbuffer expect -c "
      spawn mysql_config_editor set --host=localhost --user=root --password
      expect -nocase \"Enter password:\" {send \"$DB_ROOT_P\r\"; interact}
      "
    else
      echo '[client]' > $f
      echo "user=$DBU" >> $f
      echo "password=$DBUP" >> $f
    fi ;
  fi ;
  if [[ -d /home/vagrant ]] ; then
    local f2=/home/vagrant/$(basename "$f")
    if [[ ! -e "$f2" ]] ; then
      echo "NOTE: Copying $f (.my.cnf or .mylogin.cnf) to /home/vagrant/" 1>&2
      cp $f /home/vagrant/
      chown vagrant "$f2"
    fi
  fi
  set -exu

  local PWD0=${PWD:-$(pwd)}
  # for DB in $DB1 $DB2 $DB3 $DB4 ; do
  for DB in $DATABASES ; do
    cd "$PWD0"
    local alreadyDb=false
    if mysql -B -e "USE \`$DB\`" ; then
      alreadyDb=true
    else
      mysql -vvv -e "CREATE DATABASE \`$DB\`"
    fi
    local alreadyUser=$(mysql -B -e "SELECT User FROM mysql.user WHERE User='$DBU'" | tail -1)
    if [[ $alreadyUser != $DBU ]] ; then
      mysql -B -e "CREATE USER '$DBU'@'localhost' IDENTIFIED BY '$DBUP'"
      mysql -B -e "CREATE USER '$DBU'@'172.%' IDENTIFIED BY '$DBUP'"
    fi
    local alreadyGranted=$(mysql -B -e "SHOW GRANTS FOR '$DBU'@'localhost'" | grep "^GRANT ALL PRIVILEGES ON .$DB.\.")
    if [[ -z $alreadyGranted ]] ; then
      mysql -B -e "GRANT ALL ON \`$DB\`.* TO '$DBU'@'localhost' WITH GRANT OPTION"
      mysql -B -e "GRANT ALL ON \`$DB\`.* TO '$DBU'@'172.%' WITH GRANT OPTION"
    fi ;
    if [[ $alreadyDb == false ]] ; then
      local d=/srv/deploy/db_sql/$DB
      if [[ -d "$d" ]] ; then
          cd "$d"
          ls *.structure.sql | while read f ; do mysql "$DB" < "$f" ; done
      fi ;
    fi ;
  done
}
cd "$DIR0" && main "$@"
