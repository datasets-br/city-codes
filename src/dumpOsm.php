-- Generating DUMPS --

grep P402 data/wikidata/SP/* | wc -l

<?php
// usage: php dumpWikidata.php  [geo][err]

// CONFIGS
  $urlWd_tpl = 'https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=';
  $urlOsm_tpl = 'http://polygons.openstreetmap.fr/get_geojson.py?id=';
  $UF=''; $localCsv = false;  $stopAt=0;

$saveFolder = realpath( dirname(__FILE__)."/../data" );
$url = $localCsv
     ? "$saveFolder/br-city-codes.csv"
     : 'https://github.com/datasets-br/city-codes/raw/master/data/br-city-codes.csv'
;
 // cols 0=subdivision, 1=name_prefix, 2=name, 3=id, 4=idIBGE, 5=wdId, 6=lexLabel
 $uf_idx=0; $wdId_idx = 5;  $lexLabel_idx = 6;

$modos = ['geo'=>'GEO', 'err'=>'FIX-ERR', 'pretty-wd'=>'PRETTY-WIKIDATA', 'pretty-osm'=>'PRETTY-OSM'];
$modo = ($argc>=2)?    $argv[1]: '';
if (isset($modos[$modo])) $modo=$modos[$modo];
else die("\nERRO modo $modo desconhecido, use: ". join(', ',array_keys($modos)). "\n");

$ext = ($modo=='GEO')? 'geojson': 'json';
print "\n USANDO $modo $url ... \n";


// LOAD DATA:
$R = []; // [fname]= wdId
if (($handle = fopen($url, "r")) !== FALSE) {
   for($i=0; ($row=fgetcsv($handle)) && (!$stopAt || $i<$stopAt); $i++) 
      if ($i && (!$UF ||$row[1]==$UF))  $R["$row[1]-".lex2filename($row[4])]=$row[2];
       // cols  0=name, 1=state, 2=wdId, 3=idIBGE, 4=lexLabel
} else
   exit("\nERRO ao abrir planilha das cidades em \n\t$url\n");

if ($modo=='FIX-ERR') foreach($R as $fname=>$wdId) {
  $fs = splitFilename($fname,true); //   [$fp,$uf,$fname2,$saveFolder2,$size];
  if ($fs[4]>50) unset($R[$fname]);
  //print "\n-- debug  $saveFolder/dump_wikidata/$fs[1]/$fs[2].json";
}

// WGET AND SAVE JSON:
$i=1;
$n=count($R);
$ERR=[];

switch($modo) {
case 'PRETTY-WIKIDATA':
   foreach($R as $fname=>$wdId) {
      $fs = splitFilename($fname,true); //   [$fp,$uf,$fname2,$saveFolder2,$size];
      $f = "$saveFolder/dump_wikidata/$fs[1]/$fs[2].json";
      if ( file_exists($f) ) {
        $jold = file_get_contents($f);
        $j = json_decode( $jold, JSON_BIGINT_AS_STRING|JSON_OBJECT_AS_ARRAY);
        $jnew = json_encode($j,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
        if ($jold!==$jnew) {
                print "\n-- changing $fname";
                file_put_contents($f,$jnew);
        } else print "\n-- $fname preserved";
      } else print " . ";
   }
   break;


case 'PRETTY-OSM':
   foreach($R as $fname=>$wdId) {
      $fs = splitFilename($fname,true); //   [$fp,$uf,$fname2,$saveFolder2,$size];
      $f = "$saveFolder/dump_osm/$fs[1]/$fs[2].geojson";
      if ( file_exists($f) ) {
        $jold = file_get_contents($f);
        $j = json_decode( $jold, JSON_BIGINT_AS_STRING|JSON_OBJECT_AS_ARRAY);
        $jnew = json_encode($j,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
        if ($jold!==$jnew) {
		print "\n-- changing $fname";
		file_put_contents($f,$jnew);
	} else print "\n-- $fname preserved";
      } else print " . ";
   }
   break;

case '':
case 'FIX-ERR':
	foreach($R as $fname=>$wdId) {
	  print "\n\t($i of $n) $fname: $wdId ";
	  $json = file_get_contents("$urlWd_tpl$wdId");
	  if ($json) {
	     $out = json_stdWikidata($json);
	     if ($out) {
	         $savedBytes = file_put_contents(  "$saveFolder/dump_wikidata/$fname.$ext",  $out  );
	         print "saved ($savedBytes bytes) with fresh $wdId";
	     } else
	         ERRset($fname,"invalid Wikidata structure");
	  } else
	    ERRset($fname,"empty json");
	  $i++;
	}
	break;

case 'GEO':
	foreach($R as $fname=>$wdId) {
	  print "\n\t($i of $n) $fname: $wdId ";
	  $osmId= getOsmId($fname,$wdId); // usa wdId?
	  $json='';
	  if ($osmId) $json = file_get_contents("$urlOsm_tpl$osmId");
	  else ERRset($fname,"no osmId or P402");
	  if ($json) {
	     $out = json_stdOsm($json);
	     if ($out) {
	         $savedBytes = file_put_contents(  "$saveFolder/dump_osm/$fname.$ext",  $out  );
	         print "saved ($savedBytes bytes) with fresh OSM/$osmId";
	     } else
	         ERRset($fname,"invalid OSM structure");
	  } else
	    ERRset($fname,"empty json");
	  $i++;
	}
	break;

default:
	die("\n Modo $modo DESCONHECIDO.\n");

} // end switch


if (count($ERR)) { print "\n ----------- ERRORS ---------\n"; foreach($ERR as $msg) print "\n * $msg"; }


///// LIB

function ERRset($fname,$msg) {
   global $ERR;
   $msg = "ERROR, $msg for $fname.";
   print $msg;
   $ERR[] = $msg;
}

function json_stdOsm($jstr) {
  if (!trim($jstr)) return '';
  $j = json_decode($jstr,JSON_BIGINT_AS_STRING|JSON_OBJECT_AS_ARRAY);
  if ( !isset($j['type']) ) return '';
  return json_encode($j,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
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

function getOsmId($fname) {
  global $saveFolder;
  $f = "$saveFolder/dump_wikidata/$fname.json";
  $j = json_decode( file_get_contents($f), JSON_BIGINT_AS_STRING|JSON_OBJECT_AS_ARRAY);
  if (isset($j['claims']['P402'][0]['value']) )
	return $j['claims']['P402'][0]['value'];
  else
	return 0;
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
    return [$fp,$uf,$fname2,$saveFolder2,$size];
}

?>

... Check git status and do git add.


