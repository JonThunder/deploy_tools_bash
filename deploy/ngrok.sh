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
    local logf=/dev/null
    # logf=/tmp/ngrok.log # DEBUG
    [[ -f $pf ]] && ps -f -p $p | egrep -v '^UID' | egrep $p || {
      nohup bash -c "ngrok http 443 --log=stdout > $logf 2>&1" \
      > /tmp/ngrok_nohup.log 2>&1 &
      echo $! > ngrok.pid
    }
}
die() { echo "${1:-ERROR}" 1>&2 ; exit ${2:-2} ; }
main "$@"
