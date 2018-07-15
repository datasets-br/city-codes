-- Generating backups of JSON-Wikidata --

<?php
// usage: php dumpWikidata.php  flagOpcionalQuandoFixErr
// ou php src/dumpWikidata.php chk 

// CONFIGS
$url_tpl = 'https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=';
$UF='';
$localCsv = false;
$stopAt=0;

$saveFolder = realpath( dirname(__FILE__)."/../../data/dump_wikidata" );
$url = $localCsv
     ? "$saveFolder/../br-city-codes.csv"
     : 'https://github.com/datasets-br/city-codes/raw/master/data/br-city-codes.csv'
;
$fixErr = '';
if ($argc>=2){
 $fixErr = ($argv[1]=='chk')? 'CHECK WIKIDATA': 'FIX-ERR';
}
print "\n USANDO $fixErr $url";


// LOAD DATA:
$R = []; // [fname]= wdId
$R_ibge=[]; //
if (($handle = fopen($url, "r")) !== FALSE) {
   for($i=0; ($row=fgetcsv($handle)) && (!$stopAt || $i<$stopAt); $i++)
      if ($i && (!$UF ||$row[1]==$UF)) {
        $idx = "$row[1]-".lex2filename($row[4]);
        $R[$idx]=$row[2];
        // cols  0=name, 1=state, 2=wdId, 3=idIBGE, 4=lexLabel
        $R_ibge[$idx] = $row[3];
      }
} else
   exit("\nERRO ao abrir planilha das cidades em \n\t$url\n");

if ($fixErr) { 
  foreach($R as $fname=>$wdId) {
	  $fs = splitFilename($fname,true);
	  if ($fixErr=='FIX-ERR') {
		  if ($fs[2]>50) unset($R[$fname]);
	  } else {  // CHECK WIKIDATA
		$idIbge = $R_ibge[$fname];
		if ($idIbge && $fs[2]>50) {
			if (!preg_grep("/$idIbge/i",file($fs[0]) )) {
				print "\n -- Não achou ID IBGE ($idIbge) em $wdId: ";
				print preg_grep("/P1585/i",file($fs[0]) )? 'CÓDIGO ERRADO!': 'não tem P1585.';
			}
		} else print "\n -- Falta arquivo $wdId para conferir ID IBGE ($idIbge).";
	  }// fixErr
	} // for
   if ($fixErr=='CHECK WIKIDATA') die("\n --- FIM ----\n");
} //if fixErr
// WGET AND SAVE JSON:
$i=1;
$n=count($R);
$ERR=[];
foreach($R as $fname=>$wdId) {
  print "\n\t($i of $n) $fname: ";
  $json = file_get_contents("$url_tpl$wdId");
  if ($json) {
    $fs = splitFilename($fname);
     if ( !file_exists($fs[1]) )  mkdir($fs[1]);
     $out = json_stdWikidata($json);
     if ($out) {
         $savedBytes = file_put_contents(  $fs[0],  $out  );
         print "saved ($savedBytes bytes) with fresh $wdId";
     } else
         ERRset($fname,"invalid Wikidata structure");
  } else
    ERRset($fname,"empty json");
  $i++;
}

if (count($ERR)) { print "\n ----------- ERRORS ---------\n"; foreach($ERR as $msg) print "\n * $msg"; }


///// LIB

function ERRset($fname,$msg) {
   global $ERR;
   $msg = "ERROR, $msg for $fname.";
   print $msg;
   $ERR[] = $msg;
}

function json_stdWikidata($jstr) {
  if (!trim($jstr)) return '';
  $j = json_decode($jstr,JSON_BIGINT_AS_STRING|JSON_OBJECT_AS_ARRAY);
  if ( !isset($j['entities']) ) return '';
  $ks=array_keys($j['entities']);
  $j = $j['entities'][$ks[0]];
  if ( !isset($j['claims']) ) return '';
  foreach(['lastrevid','modified','labels','descriptions','title','aliases','sitelinks'] as $r) unset($j[$r]);
  $a = [];
  foreach($j['claims'] as $k=>$r) {
      $a[$k] = [];
      foreach($j['claims'][$k] as $r2)
          $a[$k][] = $r2['mainsnak']['datavalue'];
  }
  $j['claims'] = $a;
  return json_encode($j,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
}

function lex2filename($s) {
	$s=ucwords( str_replace('.',' ',$s) );
	return preg_replace('/ D | /','',$s); // elimina preposicao contraida (bug norma lexml)
}

function splitFilename($f,$checkSize=false) {
    global $saveFolder;
    $uf = substr($f,0,2);
    $fname2 = substr($f,3);
    $saveFolder2 = "$saveFolder/$uf";
    $fp = "$saveFolder2/$fname2.json";
    $size = $checkSize? (file_exists($fp)? filesize($fp): 0): null;
    return [$fp,$saveFolder2,$size];
}

?>

... Check git status and do git add.
