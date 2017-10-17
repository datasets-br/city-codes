## See section "Preparation" at src/README.md

php pack2sql.php
sh  cache/makeTmp.sh
PGPASSWORD=postgres psql -h localhost -U postgres datasets < cache/makeTmp.sql
# and step1
