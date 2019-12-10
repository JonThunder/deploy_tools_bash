
post_apache_deploy() {
  mk_index_html
}
mk_index_html() {
  local tmpf=$(mktemp)
  cat > $tmpf <<'EOF'
<html>
  <head>
    <meta http-equiv="refresh" content="0; url=app.html" />
    <script type="text/javascript">
      window.location.href = "app.html"
    </script>
  </head>
  <body>
    <p><a href="app.html">Redirect</a></p>
  </body>
</html>
EOF
  sudo chown $apacheu $tmpf
  [[ -e /var/www/html/index.html ]] || sudo -u $apacheu mv $tmpf /var/www/html/index.html
}
post_db_deploy() {
  mysql my_db1 -B -v -e "INSERT INTO users SET id='$DBU', nick='$DBU' ON DUPLICATE KEY UPDATE nick='$DBU'"
  for u in $ADMIN_USERS ; do
    mysql my_db1 -B -v -e "INSERT INTO users SET id='$u', nick='admin_$u', admin=1 ON DUPLICATE KEY UPDATE nick='admin_$u', admin=1"
  done
}
