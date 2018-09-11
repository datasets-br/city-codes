((REVISAR))
Preparo das abreviações de 3 letras:
1. Incluir abreiações Anatel
2. incluir por estado.

Preparo das abreviações de SP trazidas de  https://vdocuments.mx/tabela-distancias.html como DER, ver https://github.com/datasets-br/city-codes/issues/32

Preparo dos dados Anatel e DDD

```sh
psql -h remotehost -d remote_mydb -U myuser -c " \
   COPY (SELECT * FROM dataset.vjmeta_summary) TO STDOUT \
   " > ./relative_path/file.json
```
Revisar se dá para fazer a mesma coisa (STDIN) com  FOREGIN.

----

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

Todas as contagens precisam ser iguais à primeira, senão é sinal de algo errado.

### Comparando com outros dados do IBGE
Nomes e UFs atribuidas podem ser conferidos. As diferenças surgem em alguns nomes, talvez por falta de atualização no IBGE:

```
SELECT c."idIBGE", c.name nome_suposto, c.state as uf, i.nome nome_ibge,
   concat('[',"wdId",'](http://wikidata.org/entity/',"wdId",')') as Wikidata
FROM io.citybr c INNER JOIN ibge i ON i.id::text=c."idIBGE"
WHERE c.name!=i.nome;
```

 idIBGE  |       nome_suposto        | uf |        nome_ibge        |                    wikidata                     
---------|---------------------------|----|-------------------------|-------------------------------------------------
 1720499 | São Valério da Natividade | TO | São Valério             | [Q1801542](http://wikidata.org/entity/Q1801542)
 2401305 | Campo Grande              | RN | Augusto Severo          | [Q1802671](http://wikidata.org/entity/Q1802671)
 2405306 | Boa Saúde                 | RN | Januário Cicco          | [Q1802783](http://wikidata.org/entity/Q1802783)
 2408409 | Olho-d'Água do Borges     | RN | Olho d'Água do Borges   | [Q1802421](http://wikidata.org/entity/Q1802421)
 2917334 | Iuiú                      | BA | Iuiu                    | [Q1795133](http://wikidata.org/entity/Q1795133)
 2922250 | Muquém de São Francisco   | BA | Muquém do São Francisco | [Q1793568](http://wikidata.org/entity/Q1793568)
 2928505 | Santa Teresinha           | BA | Santa Terezinha         | [Q1795259](http://wikidata.org/entity/Q1795259)
 3147808 | Passa-Vinte               | MG | Passa Vinte             | [Q1791701](http://wikidata.org/entity/Q1791701)
 3150539 | Pingo-d'Água              | MG | Pingo d'Água            | [Q1789616](http://wikidata.org/entity/Q1789616)
 3506607 | Biritiba-Mirim            | SP | Biritiba Mirim          | [Q518845](http://wikidata.org/entity/Q518845)
 3522158 | Itaóca                    | SP | Itaoca                  | [Q1760856](http://wikidata.org/entity/Q1760856)

(11 registros)

## Carga complementar Anatel
O autor e mantenedor dos dados é a Gerência de Certificação e Numeração da Anatel (orcn@anatel.gov.br). A última atualização foi em 	19 de Maio de 2017.  Fonte: http://dados.gov.br/dataset/codigos-nacionais-cn

Os dados da fonte foram convertidos para UTF8, CSV padrão (com ",") e cabeçalho normalizado para o singular (

## Análise complementar Éder-Wikidata
Usando inicialização prévia do [SQL-unifier](https://github.com/datasets-br/sql-unifier) com *database trydatasets* e city-codes original.

```sh
echo "create table eder (qid text, ibge bigint, osm_relid bigint);" | psql -d trydatasets -U postgres -c 
psql -d trydatasets -U postgres -c "COPY eder FROM STDIN CSV HEADER" < wikidata-eder.csv
```

SELECT state,lexlabel,wdid as peter,eder.qid as eder 
FROM dataset.vw2_br_city_codes c INNER JOIN eder 
  ON eder.ibge=c.idibge::bigint and wdid!=qid
;
SELECT state,lexlabel,wdid as peter,eder.qid as eder, idibge, ibge 
FROM dataset.vw2_br_city_codes c INNER JOIN eder 
  ON eder.ibge!=c.idibge::bigint and wdid=qid
;

