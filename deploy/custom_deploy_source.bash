
post_apache_deploy() {
  mk_index_html
}
mk_index_html() {
    [[ -e /var/www/html/index.html ]] || cat > /var/www/html/index.html <<'EOF'
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
}
