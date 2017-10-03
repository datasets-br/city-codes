<?php
/**
 * Transforma as linhas do wikitext (fontes da edição) de
 *    https://pt.wikipedia.org/wiki/Lista_de_munic%C3%ADpios_do_Brasil
 * em arquivo CSV com ID-Wikidata, nome da cidade e estado.  
 *
 * Uso:   php src/wikitext2CSC.php < test.wiki.txt | more
 *
 */


$urlApi = 'https://pt.wikipedia.org/w/api.php?action=query&prop=pageprops&ppprop=wikibase_item&redirects=1&format=json&titles=';

print "state,name,wdid";  	// head

$txt = file_get_contents('php://stdin');

preg_replace_callback(
   '/\*\s*\[\[([^\]]+)\]\]\s*\(([A-Z][A-Z])\)/s',  	// parsing all "* [[name etc]] (UF)" strings
   function ($m) {
	global $urlApi;
	$pos = strpos($m[1], '|');
	if ($pos === false)
		$wname=$name=$m[1];
	else {
		$wname = substr($m[1],0,$pos); 		// get complete title
		$name  = substr($m[1],$pos+1);
	}
	$state_name = "$m[2],$name";
	$url    = $urlApi.str_replace(' ','_',$wname);
	$wdid='';
	$j = file_get_contents($url);			// get Wikidata-ID
	if (  preg_match('|wikibase_item"\s*:\s*"(Q\d+)|s', $j, $m)  ) // parsing JSON
		$wdid=$m[1];
	else $wdid ='??';
	print "\n$state_name,$wdid";  			// CSV line
   },
   $txt
);

