-- Generating backups of JSON-Wikidata --

<?php
// CONFIGS
$url = 'https://github.com/datasets-br/city-codes/raw/master/data/br-city-codes.csv'; // 0=name,1=state,2=wdId,3=idIBGE,4=lexLabel
$url_tpl = 'https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=';
$UF='SP';
$saveFolder = dirname(__FILE__)."/../../data/wikidata";

// LOAD DATA:
$R = []; // [fname]= wdId
if (($handle = fopen($url, "r")) !== FALSE) {
   for($i=0; ($row=fgetcsv($handle)); $i++) if ($i && (!$UF ||$row[1]==$UF))  $R["$row[1]-".lex2filename($row[4])]=$row[2];
} else
   exit("\nERRO ao abrir planilha das cidades em \n\t$url\n");

// WGET AND SAVE JSON:
$i=1;
$n=count($R);
foreach($R as $fname=>$wdId) {
  print "\n\t($i of $n) $fname: ";
  $json = file_get_contents("$url_tpl$wdId");
  if ($json) { 
     $savedBytes = file_put_contents("$saveFolder/$fname.json",$json);
    print "saved ($savedBytes bytes) with fresh $wdId";
  } else
    print "ERROR, empty json for $fname.";
  $i++;
}

///// LIB

function lex2filename($s) {
	$s=ucwords( str_replace('.',' ',$s) );
	return preg_replace('/ | D /','',$s); // elimina preposicao contraida (bug norma lexml)
}

?>

... Check git status and do git add.

