-- Generating backups of JSON-Wikidata --

<?php
// usage: php dumpWikidata.php  flagOpcionalQuandoFixErr
// ou php src/dumpWikidata.php chk 

// CONFIGS
$url_tpl = 'https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=';
$UF='';
$localCsv = true; //false;
$stopAt=0;

$saveFolder = realpath( dirname(__FILE__)."/../../data/dump_wikidata" );
$url = $localCsv
     ? "$saveFolder/../br-city-codes.csv"
     : 'https://github.com/datasets-br/city-codes/raw/master/data/br-city-codes.csv'
;
$fixErr = '';
$filter_ibge=[];
if ($argc>=2){
 if ($argc>3 && $argv[1]=='list-ibge') {
    foreach($argv as $x) if (preg_match('/^\d+$/',$x))
     	$filter_ibge[]=$x;
 } else $fixErr = ($argv[1]=='chk')? 'CHECK WIKIDATA': 'FIX-ERR';
}
print "\n USANDO $fixErr $url";


// LOAD DATA:
$R = []; // [fname]= wdId
$R_ibge=[]; //
if (($handle = fopen($url, "r")) !== FALSE) {
   for($i=0; ($row=fgetcsv($handle)) && (!$stopAt || $i<$stopAt); $i++)
      if ($i && (!$UF ||$row[1]==$UF)) {
        $idx = "$row[1]-".lex2filename($row[4]);
	if ( count($filter_ibge)<2 || in_array($row[3],$filter_ibge) ) {
		$R[$idx]=$row[2];
		// cols  0=name, 1=state, 2=wdId, 3=idIBGE, 4=lexLabel
		$R_ibge[$idx] = $row[3];
	} // set R
      }
} else
   exit("\nERRO ao abrir planilha das cidades em \n\t$url\n");


if ($fixErr) {
  $err_IBGElst=[];
  foreach($R as $fname=>$wdId) {
	  $fs = splitFilename($fname,true);
	  if ($fixErr=='FIX-ERR') {
		  if ($fs[2]>50) unset($R[$fname]);
	  } else {  // CHECK WIKIDATA
		$idIbge = $R_ibge[$fname];
		if ($idIbge && $fs[2]>50) {
			if ( !preg_grep("/\"Q155\"/",file($fs[0])) ) { // country (P17) Brazil (Q155)
				print "\n -- Error-type-8, atribuição $wdId (ao IBGE $idIbge) não é nem sequer BR!";
				$err_IBGElst[$idIbge]=8;
			} elseif ( !preg_grep("/Q3184121/",file($fs[0])) ) { // instance of municipality of Brazil
				print "\n -- Error-type-7, atribuição $wdId (ao IBGE $idIbge) não é município-BR!";
				$err_IBGElst[$idIbge]=7;
			} elseif ( !preg_grep("/$idIbge/",file($fs[0])) ) {
                                $aux  = preg_grep( "/\"P1585\"/i", file($fs[0]) );
				$errType = 1+$aux;
				$err_IBGElst[$idIbge]=$errType;
				print "\n -- Error-type-$errType, não achou ID IBGE ($idIbge) em $wdId: ";
				print $aux? 'CÓDIGO WD ERRADO!': 'não tem P1585.';
			} elseif ( !preg_grep("/\"P131\"/",file($fs[0])) ) { // vincula cidade com seu estado
				print "\n -- Error-type-3, sem estado em $wdId (IBGE $idIbge)";
				$err_IBGElst[$idIbge]=3;
			} elseif ( !preg_grep("/\"P473\"/",file($fs[0])) ) { // area code (DDD), pre-requisitos são P131 e country (Q155)
				print "\n -- Error-type-4, sem DDD em $wdId (IBGE $idIbge)";
				$err_IBGElst[$idIbge]=4;
			}
		} else {
			$err_IBGElst[$idIbge]=9;
			print "\n -- Error-type-9, falta arquivo $wdId para conferir ID IBGE ($idIbge).";
		}
	  }// fixErr
	} // for
   if ($fixErr=='CHECK WIKIDATA') {
     $ERRtype=[
	1=>'códigos WD trocados', 2=>'sem P1585',3=>'faltou P131 do estado', 4=>'faltou DDD',
        7=>'erros primários de WD', 8=>'arquivo Wikidata estranho', 9=>'sem arquivo Wikidata'
     ];
     $lst = "('".join("','",array_keys($err_IBGElst))."')";
     $ERRs="\n---- ERROS BY TYPE:";
     foreach( array_count_values(array_values($err_IBGElst))  as $errType=>$num )
     	$ERRs .= "\n\tError-type-$errType, {$ERRtype[$errType]}: $num";
     $lst_graves = [];
     foreach($err_IBGElst as $ibge=>$err) if ($err>=8) $lst_graves[] = $ibge;
     $lst_graves = "('".join("','",$lst_graves)."')";
     die("$ERRs\n".
         "\nItens com falha por respectivo código IBGE= $lst".
         "\n\nItens com falha mais grave = $lst_graves".
         "\n--- FIM ----\n"
     );
   }
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
