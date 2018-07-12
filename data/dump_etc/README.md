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
1. no shell `cp  data/*.csv data/dump_etc/*.csv /tmp`
2. no sql `COPY io.anatel263 FROM '/tmp/anatel-res263de2001-pgcn-compilado2017.csv' CSV HEADER;`
3. idem para anatel-ddd_chave.csv

Foi gerado por fim o seguinte script de casamento:
```sql
-- SOLUCAO correta:
COPY (select * from io.vw_anatel_first_get) TO '/tmp/test_good.csv' CSV HEADER;
```
Resultou em apenas 12 casamentos por sinônimos conhecidos:

```
Bom Jesus de Goiás,GO,Q891725,5203500,bom.jesus.goias,,,,64,
...
Trajano de Moraes,RJ,Q1803189,3305901,trajano.moraes,,,,22,
```
... falta conferir o restante que ficou sem DDD.

## ASSERTs
Exemplo de verificação rápida:
```sql
select count(*), count(distinct "wdId"), count(distinct "idIBGE"), count(distinct state||"lexLabel")
from io.citybr;
```
todas as contagens precisam ser iguais à primeira, senão é sinal de algo errado.
