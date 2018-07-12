Preparo dos dados Anatel e DDD

## Carga a partir do PDF Anatel2013

```sh
wget http://portal.embratel.com.br/fazum21/pdf/codigos_ddd.pdf
pdftotext -layout codigos_ddd.pdf # gera codigos_ddd.txt
grep -P "^..\s+...\s+" codigos_ddd.txt \   # debug correu bem
  | awk -F'   +' 'BEGIN { OFS = "," }{ print $1,$2,tolower($3),$5; }' \
  > anatel2013.txt
wc -l anatel2013.txt  # 4471
rm codigos_ddd.*
```
Pelo número não contempla todos os municípios, ainda assim é uma

------

O texto compilado (atualizado até 2015) da [Resolução Anatel nº 263, de 8 de junho de 2001](http://www.anatel.gov.br/legislacao/resolucoes/16-2001/383-resolucao-263) fornece a listagem completa.

São 67 macro-regiões do DDD, encabeçadas ("chaves" do DDD) pelas cidades principais:
```
DDD 11 – São Paulo – SP
DDD 12 – São José dos Campos – SP
DDD 13 – Santos – SP
...
DDD 98 – São Luís – MA
DDD 99 – Imperatriz – MA
```
Ver arquivo `anatel-ddd_chave.csv` que permitirá indicar as cidades eleitas como chave de referência do DDD.

## Preparo da resolução do PGCN
*Resolução Anatel nº 263, de 8 de junho de 2001*.  Ver também [planilha limpa](https://docs.google.com/spreadsheets/d/1C6Z9UsGID_9ITFytud5rwQRelRIXHmZmAn5Zia-kdF8/edit?usp=sharing). Passo-a-passo da obtenção da planilha:

1. `wget http://www.anatel.gov.br/legislacao/resolucoes/16-2001/383-resolucao-263`
2. Elininar todas as ocorrências de `<span style="text-decoration: line-through;">\d\d</span>`
3. Limpar as linhas contendo regex `(\d\d)\s*<br\s*/?>.+`
4. Limpar todos os "Incluído..." da coluna de nomes.
5. Ler HTML no navegador e copiar/colar para planilha.
6. Limpar resíduos.
7 Baixar CSV, ver anatel-res263de2001-pgcn-compilado2017.csv


NOVO, usando io_console:
1. `cp  data/*.csv data/dump_etc/*.csv /tmp`
2. `COPY io.anatel263 FROM '/tmp/anatel-res263de2001-pgcn-compilado2017.csv' CSV HEADER;`
3. idem para anatel-ddd_chave.csv

Foi gerado por fim o seguinte script de casamento:
```sql
-- SOLUCAO correta:
COPY (
  WITH dd AS (
    SELECT DISTINCT c.name, c.state, ddd.ddd
    FROM dataset.vw8_anatel_ddd as ddd INNER JOIN dataset.vw2_br_city_codes_tojoin_synonyms c
      ON c.state=ddd.uf AND c.lexlabel_join=ddd.namelex AND NOT(c.is_original)
  )
  SELECT name, state, wdid as "wdId", idibge as "idIBGE",
       lexlabel as "lexLabel", creation, extinction,
       postalcode_ranges as "postalCode_ranges",
       CASE WHEN ddd IS NULL
            THEN (SELECT ddd FROM dd WHERE dd.name=t.name AND dd.state=t.state)
            ELSE ddd
       END,
       notes
  FROM (
     SELECT c.name, c.state, c.wdid, c.idibge, c.lexlabel, c.creation, c.extinction,
       c.postalcode_ranges, ddd.ddd, c.notes
     FROM dataset.vw8_anatel_ddd as ddd RIGHT JOIN dataset.vw2_br_city_codes c
       ON c.state=ddd.uf AND c.lexlabel=ddd.namelex
  ) t ORDER BY std_collate(name), name, state, 3
) TO '/tmp/test_good.csv' CSV HEADER;
```
Resultou em apenas 12 casamentos por sinônimos conhecidos:

```
Bom Jesus de Goiás,GO,Q891725,5203500,bom.jesus.goias,,,,64,
Brazópolis,MG,Q1749826,3108909,brazopolis,,,,35,
Dona Eusébia,MG,Q1756805,3122900,dona.eusebia,,,,32,
Iguaracy,PE,Q2010845,2606903,iguaracy,,,,87,
Itapajé,CE,Q2021022,2306306,itapaje,,,[62600-000 62609-999],85,
Joca Claudino,PB,Q2098422,2513653,joca.claudino,,,[58928-000 58929-999],83,
Paraty,RJ,Q926729,3303807,paraty,,,,24,
Poxoréu,MT,Q1920318,5107008,poxoreu,,,[78800-000 78809-999],66,
Santa Izabel do Pará,PA,Q2008554,1506500,santa.izabel.para,,,,91,
São Vicente do Seridó,PB,Q2008358,2515401,sao.vicente.serido,,,[58158-000 58159-999],83,
Tacima,PB,Q1816133,2516409,tacima,,,[58240-000 58249-999],83,
Trajano de Moraes,RJ,Q1803189,3305901,trajano.moraes,,,,22,
```
... falta conferir o restante que ficou sem DDD.
