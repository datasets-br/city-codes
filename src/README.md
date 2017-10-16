## Preparation

```sh
php src/pack2sql.php
sh src/cache/makeTmp.sh
PGPASSWORD=postgres psql -h localhost -U postgres test < src/cache/makeTmp.sql
PGPASSWORD=postgres psql -h localhost -U postgres test < src/step01-lib.sql
```

## Original and check Wikidata

1. Get wikitext by (after edit-source interface) copy/paste 
2. See other at [Wiki - Original preparation](https://github.com/datasets-br/city-codes/wiki/Original-preparation)

```sh
php src/wikitext2CSC.php < copy.wiki.txt > test.csv
```


