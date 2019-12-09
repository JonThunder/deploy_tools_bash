unbase64() {
    if [[ -z ${BASE64_DECODE_FLAG:-} ]] ; then
        BASE64_DECODE_FLAG=D
        if ! echo ego= | base64 -$BASE64_DECODE_FLAG >/dev/null 2>&1 ; then
            BASE64_DECODE_FLAG=d
        fi
        export BASE64_DECODE_FLAG
    fi
    base64 -$BASE64_DECODE_FLAG "$@"
}
regex_period_escape() {
    local email=$1
    printf '%s' "$email" | sed 's/\./\\./g'
}
sanitize_value_for_shell() {
    printf '%s' "$1" | sed 's/[\$]/\\$/g' | sed 's/[!]/\\!/g'
}
sanitize_regexp() {
    local x=$1
    local y=$2
    local delim='/';
    local delim_hex=$(printf '%s' "$delim" | od -t x1 | head -1 | awk '{print $2}');
    local delim_posix_regex="\x$delim_hex"
    if printf '%s' "$y" | grep -P "$delim_posix_regex" >/dev/null 2>&1 ; then
        delim=','
        delim_hex=$(printf '%s' "$delim" | od -t x1 | head -1 | awk '{print $2}');
        delim_posix_regex="\x$delim_hex"
        if printf '%s' "$y" | grep -P "$delim_posix_regex" >/dev/null 2>&1 ; then
          delim='|'
        fi ;
    fi ;
    printf '%s\n' "$delim"
}
safe_sed() {
    local tmpf=$(mktemp)
    local x=$1
    local y=$2
    local f=$3
    local delim=$(sanitize_regexp "$x" "$y")
    cat "$f" > $tmpf
    sed "s${delim}$x${delim}$y${delim}g" $tmpf > $tmpf.2
    if [[ -s $tmpf.2 ]] ; then
      cat $tmpf.2 > "$f"
      rm $tmpf $tmpf.2
    else
      die "ERROR: safe_sed($x, $y, $f) resulted in empty file ($tmpf.2)"
    fi
}

init_admins() {
  grep '^adm:' /etc/group || groupadd adm
  for admin in $ADMIN_USERS ; do
    if [[ ! -d /home/$admin ]] ; then
      egrep "^$admin:" /etc/group || groupadd $admin
      useradd -m -g apache -G adm,$admin $admin
    fi
    id -Gn $admin | egrep '(^| )apache( |$)' || usermod -g apache -G adm,$admin $admin
  done
}
pkg_installs() {
  yum=''; apt='' ; pkger='';
  if which yum ; then
    yum=yum
    pkger=yum
  elif which apt-get ; then
    apt=apt-get
    pkger=yum
  fi ;
  export DEBIAN_FRONTEND=noninteractive
  if [[ $yum ]] ; then
    if [[ -f /etc/selinux/config ]] ; then
      sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config
      setenforce 0 || true
    fi ;
    yum check-update || yum -y update
    yum -y install epel-release
  elif [[ $apt ]] ; then
    apt-get -y update
    ls /etc/apt/sources.list.d/ansible-ubuntu-ansible-*.list || apt-add-repository ppa:ansible/ansible
  fi ;
  local snap=''
  if [[ $YES_NGROK == true ]] ; then
    snap=snapd
  fi
  $pkger -y install ansible curl wget git unzip jq nodejs npm expect $snap \
  || die "ERROR $?: Failed to $pkger install some initial packages"
  if [[ $yum ]] ; then
    $yum -y install httpd perl-Authen-PAM python-ndg_httpsclient python-urllib3 pyOpenSSL mod_ssl openssl yum-utils
  elif [[ $apt ]] ; then
    $apt -y install apache2 libauthen-pam-perl aptitude libapache2-mod-php
  fi || die "ERROR $?: Failed to $pkger install specific packages"
  [[ -z $EXTRA_PACKAGES ]] || $pkger -y install $EXTRA_PACKAGES
}
prep_ansible() {
  echo 'localhost ansible_connection=local ansible_python_interpreter="/usr/bin/env python"' > /etc/ansible/hosts
  cd /srv/deploy/ansible
  if [[ $DOCKER_USERS ]] && ! egrep '^docker_users:' vars.yml >/dev/null ; then
    ( echo 'docker_users:'
      for u in $DOCKER_USERS ; do
        printf '%s\n' "  - $u"
      done
    ) >> vars.yml
  fi
  safe_sed 'CONFIG_ME_DB_ROOT_P' "$DB_ROOT_P" vars.yml
  if [[ $YES_NGROK == true ]] ; then
    egrep '^firewalld_ports_open:' vars.yml || {
      cat >> vars.yml <<'EOFvy'
firewalld_ports_open:
  - proto: tcp
    port: 4040
EOFvy
    }
  fi
}
run_ansible() {
  cd /srv/deploy/ansible
  prep_ansible
  ansible-galaxy install -r requirements.yml
  ansible-playbook playbook.yml
}
apache_config() {
  true # PLACEHOLDER FUNCTION, replace me in provision.sh with more logic if necessary
}
config_ngrok() {
  if [[ $YES_NGROK == true ]] ; then
    if ! which ngrok ; then
      systemctl enable --now snapd.socket && sleep 10 \
      && snap install ngrok || { sleep 10 ; snap install ngrok ; } \
      || die "ERROR $?: Failed to snap install ngrok"
    fi;
    if [[ -d /srv/vagrant_synced_folder ]] ; then
      d=/srv/vagrant_synced_folder/$DEPLOY_PATH/.ngrok2
      if [[ -d "$d" ]] ; then
        rsync -av "$d/" /home/vagrant/.ngrok2
        sudo rsync -av "$d/" /root/.ngrok2
      else
        echo "WARNING: Found no $d folder (add an .ngrok2 folder with ngrok.yml to have it synced into the VM). (NOTE: DEPLOY_PATH=$DEPLOY_PATH)" 1>&2
      fi
    fi
  fi ;
}
last_steps() {
  if [[ $PROD_DEPLOY == false ]] && [[ -d /srv/vagrant_synced_folder ]] ; then
      f=/srv/vagrant_synced_folder/vm/.gitconfig
      if [[ -f "$f" ]] ; then
        cat "$f" > /home/vagrant/.gitconfig
        chown vagrant /home/vagrant/.gitconfig
      fi
  fi
  cd $FULLDIR0
  f=provision-db.sh
  if [[ -f "$f" ]] ; then
    if [[ ! -f /srv/provisioned/$f.touch ]] ; then
      echo "NOTE: Running $f" 1>&2
      bash "$f" && touch /srv/provisioned/$f.touch
    fi
  else echo "WARNING: Found no $f in PWD $PWD" 1>&2
  fi
  if [[ $yum ]] ; then
    systemctl enable httpd
    f=extra_yum.sh
    if [[ -f "$f" ]] ; then
      if [[ ! -f /srv/provisioned/$f.touch ]] ; then
        echo "NOTE: Running $f" 1>&2
        bash "$f" && touch /srv/provisioned/$f.touch
      fi
    else echo "WARNING: Found no $f in PWD $PWD" 1>&2
    fi
    yum check-update || yum -y update
  elif [[ $apt ]] ; then
    systemctl enable apache2
    # TODO: modenable tls/ssl
    apt-get -y update && apt-get -y upgrade
  fi ;
  provisioned_count=$(cat /srv/provisioned/count 2>/dev/null)
  if [[ $provisioned_count -gt 1 ]] ; then
    bash $FULLDIR0/deploy.sh
  else
    echo "NOTE: Please be sure to restart the vagrant box (vagrant halt; vagrant up) after provisioning for the very first time." 1>&2
    # shutdown -r now
    echo "WARNING: NOT running deploy.sh this time (first time)." 1>&2
  fi ;
}


bundle_dir() {
  local pwd0=${PWD:-$(pwd)}
  local to_dir=$1
  local from_dir=$2
  local stringFixer=${3:-}
  local suffix=$(dirname "$to_dir")
  suffix=$(printf '%s' "$suffix" | sed 's/^.*-//')
  [[ $stringFixer ]] || stringFixer="fix_${suffix}_strings"
  [[ $FIX_STRINGS_IN_FILES ]] || die "ERROR: bundle_dir needs a list of files defined: \$FIX_STRINGS_IN_FILES"
  mkdir -p "$to_dir"
  rsync -a --exclude .git "$from_dir"/ "$to_dir"
  cd "$to_dir"
  for f in $FIX_STRINGS_IN_FILES ; do
    f=$(printf '%s' "$f" | sed 's/^ *//; s/ *$//')
    [[ $f ]] || continue
    [[ ! -e "$f" ]] || $stringFixer "$f"
  done
  cd "$pwd0"
}
bundle_git() {
  local pwd0=${PWD:-$(pwd)}
  local dir=$1
  local remoteURL=$2
  local remoteName=${3:-origin}
  local branch=${4:-master}
  local stringFixer=${5:-}
  local suffix=$(dirname "$dir")
  suffix=$(printf '%s' "$suffix" | sed 's/^.*-//')
  [[ $stringFixer ]] || stringFixer="fix_${suffix}_strings"
  [[ $FIX_STRINGS_IN_FILES ]] || die "ERROR: bundle_git needs a list of files defined: \$FIX_STRINGS_IN_FILES"
  
  mkdir -p "$dir"
  cd "$dir"
  egrep '^github\.com ' ~/.ssh/known_hosts || ssh-keyscan github.com >> ~/.ssh/known_hosts
  if [[ ! -d .git ]] ; then
    git init
    git remote add $remoteName $remoteURL
    git fetch $remoteName
    git checkout $branch \
    || ( git checkout $remoteName/$branch && git checkout -b $branch ) \
    || die "ERROR $?: Failed to checkout $branch"
    git checkout -b $branch-$suffix
  else
    git status | tail -1 | egrep '^nothing to commit' || die "ERROR: Bundle $dir has uncommitted changes."
    git checkout $branch-$suffix && git fetch $remoteName && git merge $branch \
    || die "ERROR $?: Failed to update Git bundle $dir branch $branch-$suffix from branch $branch"
  fi
  git status | tail -1 | egrep '^nothing to commit' || die "ERROR: Bundle $dir has uncommitted changes."
  for f in $FIX_STRINGS_IN_FILES ; do
    f=$(printf '%s' "$f" | sed 's/^ *//; s/ *$//')
    [[ $f ]] || continue
    [[ ! -e "$f" ]] || $stringFixer "$f"
  done
  cd "$pwd0"
}
check_ngrok() {
  if [[ $BUNDLE != 'bundle-prod' ]] ; then
    NGROK_HOST=$(curl localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' | awk -F'/' '{print $NF}')
    while [[ -z $NGROK_HOST ]] || [[ $NGROK_HOST == null ]] ; do
      if ps -ef | grep -v ' grep ' | grep '\/ngrok http' > /dev/null ; then
        sleep 5
      else run_ngrok
      fi ;
      echo "NOTE: Re-acquiring NGROK hostname/domain from its API (last time it was '$NGROK_HOST')" 1>&2
      NGROK_HOST=$(curl localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' | awk -F'/' '{print $NF}')
    done
    export NGROK_HOST
  fi
}
run_ngrok() {
    cat > ngrok.sh <<'EOFng'
#!/bin/bash
cd $(dirname "$0")
main() {
    local err="ERROR: Cannot run ngrok without $HOME/.ngrok2/ngrok.yml config"
    err="$err (add 'authtoken: ...' per https://ngrok.com/docs#config-default-location"
    err="$err and https://ngrok.com/docs#getting-started-authtoken)"
    local ncfg=~/.ngrok2/ngrok.yml
    [[ -d ~/.ngrok2 ]] && [[ -f $ncfg ]] || die "$err"
    egrep '^web_addr: ' $ncfg || echo 'web_addr: 0.0.0.0:4040' >> $ncfg
    local pf=ngrok.pid
    local p=$(cat $pf)
    [[ -f $pf ]] && ps -f -p $p | egrep -v '^UID' | egrep $p || { 
      nohup bash -c 'ngrok http 443 --log=stdout > /dev/null 2>&1' \
      > /tmp/ngrok_nohup.log 2>&1 &
      echo $! > ngrok.pid
    }
}
die() { echo "${1:-ERROR}" 1>&2 ; exit ${2:-2} ; }
main "$@"
EOFng
  chmod +x ngrok.sh && ./ngrok.sh || die "ERROR $?: Failed to run ngrok.sh"
  sleep 5
}
post_apache_deploy() {
  true # PLACEHOLDER FUNCTION, replace me in custom_deploy_source.bash with more logic if necessary
}
post_db_deploy() {
  true # PLACEHOLDER FUNCTION, replace me in custom_deploy_source.bash with more logic if necessary
}


# # # EXAMPLES

mk_examples() {
  ( mkdir -p deploy && cd deploy
    touch source_me.bash
    mk_source_me
    mk_deploy_script
    mk_vagrantfile_script
    mk_provision_script
    mk_ansible_config
    mk_provision_db_script
    mk_extra_yum_script
    mk_extra_yum_list
    mk_bundle_script
    mk_apache_deploy_script
    mk_deploy_prod_script
    chmod +x deploy.sh
  )
  cp_deploy_tools
}

cp_deploy_tools() {
  SOURCE_ZER0=${BASH_SOURCE[0]}
  cp "$SOURCE_ZER0" ./deploy/ || die "ERROR $?: Failed to cp $SOURCE_ZERO to ./deploy/"
}
