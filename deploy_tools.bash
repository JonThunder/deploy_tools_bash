

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
  if [[ $DOCKER_USERS ]] ; then
    ( echo 'docker_users:'
      for u in $DOCKER_USERS ; do
        printf '%s\n' "  - $u"
      done
    ) >> vars.yml
  fi
  cd /srv/deploy/ansible
  safe_sed 'CONFIG_ME_DB_ROOT_P' "$DB_ROOT_P" vars.yml
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


bundle_git() {
  local pwd0=${PWD:-$(pwd)}
  local dir=$1
  local remoteURL=$2
  local remoteName=${3:-origin}
  local branch=${4:-master}
  local stringFixer=${5:-fix_test_strings}
  local suffix=$(dirname "$dir")
  suffix=$(printf '%s' "$suffix" | sed 's/^.*-//')
  [[ $stringFixer ]] || stringFixer="fix_${suffix}_strings"
  [[ $FIX_STRINGS_IN_FILES ]] || die "ERROR: bundle_git needs a list of files defined: \$FIX_STRINGS_IN_FILES"
  
  mkdir -p "$dir"
  cd "$dir"
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
  true # PLACEHOLDER FUNCTION, replace me in apache-deploy.sh with more logic if necessary
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
# # # Example source_me.bash:
mk_source_me() {
  cat > source_me.bash <<'EOF'

ADMIN_USERS="user1"
DOCKER_USERS="vagrant $ADMIN_USERS"
DATABASES='my_db1'
DB_ROOT_P='databaseR00tPW' # For example
DBU='my_dbu1'
DBUP='databaseY00$3rPW'
FIX_STRINGS_IN_FILES="html/index.php
"

EOF
} # END: mk_source_me(): source_me.bash

# # # Example deploy.sh:
mk_deploy_script() {
  cat > deploy.sh <<'EOF'
#!/bin/bash
# # # USAGE:
# # #   deploy.sh # Normal test use
# # #   PROD_DEPLOY=true deploy.sh # Deploy for production
# # #   DEPLOY_PATH=deployments/testVM DEPLOY_UP_LEVELS=../.. deploy.sh # Deploy a test path deployments/testVM/deploy
# # #
# # #   Where DEPLOY_PATH is the path from your project root to the deploy folder
# # #   and DEPLOY_UP_LEVELS is the levels "up" from it: For example,
# # #   for a DEPLOY_PATH like deployments/testVM, the DEPLOY_UP_LEVELS would be
# # #   '../..' (two levels up).

export PROD_DEPLOY=${PROD_DEPLOY:-false}
export DEPLOY_PATH=${DEPLOY_PATH:-.}
export DEPLOY_UP_LEVELS=${DEPLOY_UP_LEVELS:-.}
DIR0=$(dirname "$0")
main() {
  init;
  if [[ $PROD_DEPLOY == true ]] ; then
    if egrep '^(CENTOS|REDHAT)' /etc/os-release && hostname | egrep '^(example.com|staging.tbd)' ; then # NOTE: Change the allowable hostnames ... unless you're managing example.com and staging.tbd
      sudo bash ./apache-deploy.sh bundle-prod
    else
      echo "WARNING: I checked the OS release name and hostname: I do not know this server. Not deploying here."
      echo "NOTE: Attempting to bundle-prod from here..."
      bash ./bundle.sh bundle-prod || die "ERROR $?: Failed to bundle-prod"
      echo "NOTE: Please transfer the bundle-prod.tgz file and deploy-prod.sh to /tmp on the target server and run deploy-prod.sh (or deploy-prod.sh /path/some-other-bundle.tgz)" 1>&2
    fi
  else
    if [[ $WITHIN_VM == true ]] ; then
      deploy_code_in_vm
    else
      deploy_vm
    fi ;
  fi ;
}
die() { echo "${1:-ERROR}" 1>&2 ; exit ${2:-2} ; }
init() {
  WITHIN_VM=${WITHIN_VM:-}
  which vagrant >/dev/null 2>&1 || {
    if [[ $WITHIN_VM == true ]] ; then
      if ! grep ^flags /proc/cpuinfo | grep ' hypervisor ' >/dev/null ; then
        die "ERROR: WITHIN_VM flag says we are already in a Virtual Machine ($WITHIN_VM) - but /proc/cpuinfo makes no mention of hypervisor"
      fi
    else
      die "ERROR: Please install vagrant and a virtual machine provider (like VirtualBox)"
    fi
  }
  if [[ $WITHIN_VM != true ]] ; then
    if [[ ! -d ../.ngrok2 ]] ; then
      if [[ -d ~/.ngrok2 ]] ; then
        cp -rp ~/.ngrok2 ../.ngrok2
      fi
    fi
    if [[ ! -d ../.ngrok2 ]] ; then
      echo "WARNING: Ngrok won't work without a .ngrok2 folder with ngrok.yml defining authtoken"
    fi
    if [[ ! -f ../.gitconfig ]] && [[ -f ~/.gitconfig ]] ; then
      cp ~/.gitconfig ../
    fi
  fi
}
deploy_code_in_vm() {
  set -exu
  # # NOTE: Consider adding a line like the following to make it easier on bundle.sh:
  # [[ -d ../client_code ]] || (cd .. && git clone git@bitbucket.com:user/my_app_client_code.git) || die "ERROR $?: Failed to obtain client_code in $PWD"
  bash ./bundle.sh bundle-test
  sudo bash ./apache-deploy.sh bundle-test
  echo "SUCCESS" 1>&2
  echo "(Bundling for prod now...)" 1>&2
  [[ -d bundle-prod/web/node_modules ]] || cp -rp bundle-test/web/node_modules bundle-prod/web/node_modules
  bash ./bundle.sh bundle-prod
  echo "(Done with prod.)" 1>&2
}
vagrant_ssh_deploy() {
  prov=/srv/vagrant_synced_folder/$DEPLOY_PATH/deploy/deploy.sh
  vagrant ssh -c "(bash $prov | tee $prov.log) 2> >(tee -a $prov.err >&2)"
}
deploy_vm() {
  # # NOTE: Consider adding a line like the following to make it easier on bundle.sh:
  # [[ -d ../client_code ]] || (cd .. && git clone git@bitbucket.com:user/my_app_client_code.git) || die "ERROR $?: Failed to obtain client_code in $PWD"
  if is_running ; then
    vagrant_ssh_deploy
  else
    vagrant up --provision
    provisioned_count=$(cat .count 2>/dev/null)
    [[ $provisioned_count ]] && provisioned_count=$((provisioned_count + 1)) \
    || provisioned_count=1
    echo $provisioned_count > .count
    if [[ $provisioned_count -lt 2 ]] ; then
      vagrant halt ; vagrant up ; vagrant_ssh_deploy
    fi ;
  fi ;
}
is_running() {
  vagrant status | awk 'f;/Current machine states:/{f=1}' | awk 'f<2;/^$/{f++}' | grep '^default ' | egrep ' running( |$)' > /dev/null
}
is_running() {
  vagrant status | awk 'f;/Current machine states:/{f=1}' | awk 'f<2;/^$/{f++}' | grep '^default ' | egrep ' running( |$)' > /dev/null
}
cd "$DIR0" && main "$@"

EOF
} # END: mk_deploy_script(): deploy.sh

# # # Example ../Vagrantfile:
mk_vagrantfile_script() {
  cat > ../Vagrantfile <<'EOF'
# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure("2") do |config|
  config.vm.box = "generic/centos7"
  config.vm.network "forwarded_port", guest: 10000, host: 10000 # webmin
  config.vm.network "forwarded_port", guest: 4040, host: 4041 # ngrok
  config.vm.network "forwarded_port", guest: 8080, host: 8082 # npm run dev
  config.vm.network "forwarded_port", guest: 80, host: 8081 # Apache HTTPD
  config.vm.network "forwarded_port", guest: 443, host: 4431 # Apache HTTPD
  config.vm.synced_folder "./", "/srv/vagrant_synced_folder"
  config.vm.provision "shell", inline: <<-SHELL
      exp='export WITHIN_VM=true'
      exp=$(echo -e "$exp\nexport DEPLOY_PATH=.")
      exp=$(echo -e "$exp\nexport DEPLOY_UP_LEVELS=.")
      f=/etc/profile.d/vagrant.sh
      [[ -f $f ]] || echo "$exp" >> $f
      source "$f"
      prov=/srv/vagrant_synced_folder/./deploy/provision.sh
      (bash "$prov" | tee "$prov.log") 2> >(tee -a "$prov.err" >&2)
  SHELL
end

EOF
} # END: mk_vagrantfile_script(): ../Vagrantfile

# # # Example provision.sh:
mk_provision_script() {
  cat > provision.sh <<'EOF'
#!/bin/bash

# # # USAGE:
# # #   provision.sh # To deploy normally (with ngrok)
# # #   PROD_DEPLOY=true provision.sh # To deploy to production (no ngrok)

export PROD_DEPLOY=${PROD_DEPLOY:-false}
BUNDLE=${BUNDLE:-}

PWD0=${PWD:-$(pwd)}
DIR0=$(dirname "$0")
FULLDIR0=$(cd $DIR0 && pwd)

YES_NGROK=true
if [[ $PROD_DEPLOY == true ]] ; then
  YES_NGROK=false
  # NOTE: You can add other "YES_" variables here like YES_DEBUG_APP and add logic to deploy some test-only or dev-only debug tool.
  [[ $BUNDLE ]] || BUNDLE='bundle-prod'
fi ;
[[ $BUNDLE ]] || BUNDLE='bundle-test'

main() {
  init
  pkg_installs
  init_admins
  run_ansible
  apache_config
  config_ngrok
  last_steps
}
init() {
  source deploy_tools.bash
  mkdir -p /srv/provisioned
  provisioned_count=$(cat /srv/provisioned/count 2>/dev/null)
  [[ $provisioned_count ]] && provisioned_count=$((provisioned_count + 1)) \
  || provisioned_count=1
  echo $provisioned_count > /srv/provisioned/count
  if [[ ! -d /srv/deploy ]] ; then
    if [[ ! -d /srv/vagrant_synced_folder ]] ; then
      die "ERROR: Failed to find /srv/deploy folder (or even the /srv/vagrant_synced_folder). How do you intend to deploy to this server? How are you running this script ($0)?"
    fi
    cp -rp "$DIR0"/ /srv/deploy || die "ERROR $?: Failed to cp $DIR0 to /srv/deploy"
  fi ;
}
# # # NOTE: Define EXTRA_PACKAGES or else redefine pkg_installs to control OS package installation.
# # #   Also, at the end of last_steps, a script called extra_yum.sh will be run, if it exists (and if you are provisioning a yum server).
# # # NOTE: prep_ansible(), invoked by run_ansible, is also a good one to consider overriding

cd "$DIR0" && main "$@"

EOF
} # END: mk_provision_script(): provision.sh

# # # Example ansible config:
mk_ansible_config() {
  mkdir -p ansible
  cat > ansible/playbook.yml <<'EOF'
---
- hosts: localhost
  vars_files:
    - vars.yml
  roles:
    - role: geerlingguy.repo-epel
    - role: geerlingguy.repo-remi
    - role: geerlingguy.apache
    - role: geerlingguy.mysql
    - role: geerlingguy.php-mysql
    - role: geerlingguy.docker
    - role: geerlingguy.composer
    # - role: geerlingguy.java
    - role: semuadmin.webmin
    - role: oasis_roles.firewalld

EOF
# END: playbook.yml
  cat > ansible/requirements.yml <<'EOF'
---
- src: geerlingguy.repo-epel
- src: geerlingguy.repo-remi
- src: geerlingguy.apache
- src: geerlingguy.mysql
- src: geerlingguy.php-mysql
- src: geerlingguy.docker
- src: geerlingguy.composer
# - src: geerlingguy.java
- src: semuadmin.webmin
- src: oasis_roles.firewalld
# - src: devoinc.systemd_service

EOF
# END: requirements.yml
  cat > ansible/vars.yml <<'EOF'
---
# geerlingguy.apache https://galaxy.ansible.com/geerlingguy/apache
apache_ports_configuration_items:
  - regexp: "^ *AllowOverride"
    line: "    AllowOverride  All"
# XXX TODO Was this necessary?

# geerlingguy.docker https://galaxy.ansible.com/geerlingguy/docker
docker_compose_version: "1.25.0"

# geerlingguy.mysql https://galaxy.ansible.com/geerlingguy/mysql
mysql_root_username: root
mysql_root_password: 'CONFIG_ME_DB_ROOT_P'
# # The mysql_users are handled in another script (provision-db.sh)
# mysql_users:
#   - name: webmaster
#     host: localhost
#     . . .
#   - name: webmaster
#     host: '172.*'
#     . . .

# geerlingguy.php https://galaxy.ansible.com/geerlingguy/php
php_default_version_debian: "7.2"
# php_enablerepo: "remi-php56"
php_enablerepo: "remi-php72"
# phpmyadmin_enablerepo: "remi-php56"
phpmyadmin_enablerepo: "remi-php72"
php_packages_extra:
# # TODO QQQ: Were all these commented lines important?
#   - php56-php-pecl-xdebug
#   - php72-php-cli
#   - php72-php-common
#   - php72-php-gd
#   - php72-php-json
#   - php72-php-mbstring
#   - php72-php-mysqlnd
#   - php72-php-opcache
#   - php72-php-pdo
  - php-pecl-mcrypt

# geerlingguy.pip https://galaxy.ansible.com/geerlingguy/pip
pip_install_packages:
  - name: docker

# semuadmin.webmin https://galaxy.ansible.com/semuadmin/webmin
firewalld_enable: true
install_utilities: true

# oasis_roles.firewalld https://galaxy.ansible.com/oasis_roles/firewalld
firewalld_services:
  - http
  - https
  # - mysql # TODO: Uncomment if you need external access to MySQL server

EOF
# END: vars.yml
} # END: mk_ansible_config()

# # # Example provision-db.sh:
mk_provision_db_script() {
  cat > provision-db.sh <<'EOF'
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

EOF
} # END: mk_provision_db_script(): provision-db.sh

# # # Example extra_yum.sh:
mk_extra_yum_script() {
  cat > extra_yum.sh <<'EOF'
#!/bin/bash
DIR0=$(dirname "$0")
BASE=$(basename "$0")
main() {
  badf=/srv/provisioned/bad_extra_packages.txt ;
  [[ -d /srv/provisioned ]] || mkdir -p /srv/provisioned
  [[ -e $BASE.list ]] || die "ERROR: $0 expects a file named $0.list"
  while read p ; do
    if [[ -z $p ]] ; then continue ; fi
    if ! yum -y install $p ; then
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

EOF
} # END: mk_extra_yum_script(): extra_yum.sh

# # # Example extra_yum.sh.list:
mk_extra_yum_list() {
  cat > extra_yum.sh.list <<'EOF'
zip


EOF
} # END: mk_extra_yum_list(): extra_yum.sh.list

# # # Example bundle.sh:
mk_bundle_script() {
  cat > bundle.sh <<'EOF'
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
  bundle_git $BUNDLE/server_code git@github.com:user/my_app_server_code.git origin "$SERVER_BRANCH" # $SERVER_BRANCH defined in source_me.bash

  bundle_git $BUNDLE/client_code git@github.com:user/my_app_browser_code.git origin "$CLIENT_BRANCH" # $CLIENT_BRANCH defined in source_me.bash
  
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

EOF
} # END: mk_bundle_script(): bundle.sh

# # # Example apache-deploy.sh:
mk_apache_deploy_script() {
  cat > apache-deploy.sh <<'EOF'
#!/bin/bash
DIR0=$(dirname "$0")
main() {
  BUNDLE=${1:-bundle-prod}
  source deploy_tools.bash
  rsync -a "$BUNDLE/var_www"/ /var/www
  post_apache_deploy
}
cd "$DIR0" && main "$@"

EOF
} # END: mk_apache_deploy_script(): apache-deploy.sh

# # # Example deploy-prod.sh:
mk_deploy_prod_script() {
  cat > deploy-prod.sh <<'EOF'
#!/bin/bash
main() {
  BUNDLE=${1:-bundle-prod}
  local bundle_f=${1:-/tmp/$BUNDLE.tgz}
  mkdir -p /tmp/deploy
  cd /tmp/deploy && tar -xzf "$bundle_f"
  if [[ ! -d /srv/deploy ]] ; then
    mkdir -p /srv
    mv /tmp/deploy /srv/deploy
  else
    if which rsync >/dev/null 2>&1 ; then
      rsync -a --exclude .git /tmp/deploy/ /srv/deploy
    else
      date=$(date -u +'%Y%m%dT%H%M%S)
      mv /srv/deploy /srv/deploy.bak$date
      mv /tmp/deploy /srv/deploy
    fi
  fi
  PROD_DEPLOY=true bash /srv/deploy/provision.sh
}
main "$@"

EOF
} # END: mk_deploy_prod_script(): deploy-prod.sh

