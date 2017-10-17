/**
 * ASSERTIONS - conferindo consistência dos CSVs IBGE com projeto,  
 * ou seja (ver step2 no src/cache) /tmp/tmpcsv/br_city_codes.csv
 * com /tmp/dtb_2015/RELATORIO_DTB_BRASIL_MUNICIPIO.csv
 */

\echo '-- ASSERT 1.1: must be n=n_ids, n2=n2_ids, n=n2, n2_ids=n_ids'
 SELECT count(*) as n, count(distinct idibge) as n_ids FROM tmpcsv_br_city_codes;
 SELECT count(*) as n2, count(distinct "idIBGE") as n2_ids FROM tmpvw_ibge_municipios;

\echo '-- ASSERT 1.2: must be empty. All IDs must be in both'
 SELECT * FROM tmpcsv_br_city_codes WHERE idibge NOT IN (select "idIBGE" from tmpvw_ibge_municipios);

\echo '-- ASSERT 1.3: must be ZERO. All <state,lexlabel> must be in both'
 SELECT count(*) from tmpcsv_br_city_codes where state||lexlabel NOT IN (select state||"lexLabel" from tmpvw_ibge_municipios);
\echo '  -- ... when not zero, check and fix the problem:'
 SELECT i.name as name_ibge, c.name,c.state, c.lexlabel, c.wdid,c.idibge
 FROM tmpcsv_br_city_codes c INNER JOIN tmpvw_ibge_municipios i ON i."idIBGE"=c.idibge
 WHERE c.state||c.lexlabel NOT IN (select state||"lexLabel" from tmpvw_ibge_municipios t)
 ;


