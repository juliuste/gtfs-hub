#!/bin/bash

export GTFS_DIR=$DATA_DIR/gtfs
export GTFS_VALIDATED_DIR=$DATA_DIR/gtfs_validated
export GTFS_SOURCES_CSV=./config/gtfs-feeds.csv
export REPORT_PUBLISH_DIR=$DATA_DIR/www/
export SUMMARY_FILE=$GTFS_DIR/index.html


function augment_shapes {
  # extract gtfs
  # TODO GTFS fixes should go into gtfs-rules
  rm -rf "$GTFS_DIR/$1.gtfs"
  unzip -o -d $GTFS_DIR/$1.gtfs $GTFS_DIR/$1.gtfs.zip

  if [ "$1" == "VVS" ]; then
    # remove errornous transfers
    echo "Fixing VVS..."
    rm $GTFS_DIR/$1.gtfs/transfers.txt
  fi
  # call pfaedle
  docker run --rm -v "$HOST_DATA":/data:rw mfdz/pfaedle --inplace -x /data/osm/$2 /data/gtfs/$1.gtfs
  # zip and move gtfs-out
  zip -j $GTFS_DIR/$1.with_shapes.gtfs.zip $GTFS_DIR/$1.gtfs/*.txt
}

function download_and_check {
  export GTFS_FILE=$GTFS_DIR/$1.gtfs.zip
  echo Download $2 to $GTFS_FILE
  downloadurl=$2

  if [ -f $GTFS_FILE ]; then
    if [ "$1" == "HVV" ] || [ "$1" == "VBB" ] ; then
      echo "Ignore $1 as no appropriate http headers are returned"
      response='304'
    else
      echo "Checking update for $downloadurl"
      # if file already exists, we only want to download, if newer, hence we add -z flag to compare for file date
      # FIXME: Enabling this check performs a download, but does not set response_code (?)
      # if [[ $1 =~ ^(VBB|HVV)$ ]]; then
      # HVV and VBB dont send time stamps, so we ignore don't download them
      # TODO: we could store the url used for downloading and download, if it changed...
      response=$(curl -k -H 'User-Agent: C url' -R -L -w '%{http_code}' -o $GTFS_FILE -z $GTFS_FILE $downloadurl)
      # fi
      #response=$(curl -R -L -w '%{http_code}' -o $GTFS_FILE -z $GTFS_FILE $downloadurl)
    fi
  else
    echo "First download"
    response=$(curl -k -H 'User-Agent: C url' -R -L -w "%{http_code}" -o $GTFS_FILE $downloadurl)
  fi
  echo "Resulting http_code: $response"

    case "$response" in
        200) if [ "$1" != "DELFI" ]; then
               docker run -t -v $HOST_DATA/gtfs:/gtfs -e GTFSVTOR_OPTS=-Xmx8G mfdz/gtfsvtor -o /gtfs/gtfsvtor_$1.html -l 1000 /gtfs/$1.gtfs.zip 2>&1 | tail -1 > /$GTFS_DIR/$1.gtfsvtor.log 
             else
               docker run -t -v $HOST_DATA/gtfs:/gtfs -e GTFSVTOR_OPTS=-Xmx8G mfdz/gtfsvtor -o /gtfs/gtfsvtor_$1.html -l 1000 /gtfs/$1.gtfs.zip 2>&1 | tail -1 > /$GTFS_DIR/$1.gtfsvtor.log 
               echo "Patching DELFI..."
               rm -rf "$GTFS_DIR/$1.gtfs"
               unzip -o -d $GTFS_DIR/$1.gtfs $GTFS_DIR/$1.gtfs.zip
               sed -i 's/"","Europe/"https:\/\/www.delfi.de\/","Europe/' $GTFS_DIR/$1.gtfs/agency.txt
               zip -j $GTFS_DIR/$1.gtfs.zip $GTFS_DIR/$1.gtfs/*
             fi
             if [ "$7" != "Nein" ]; then
               echo "Augment shapes for $1 using file $7"
               augment_shapes $1 $7
             fi
             ;;
        301) printf "Received: HTTP $response (file moved permanently) ==> $url\n" ;;
        304) printf "Received: HTTP $response (file unchanged) ==> $url\n" ;;
        404) printf "Received: HTTP $response (file not found) ==> $url\n" ;;
          *) printf "Received: HTTP $response ==> $url\n" ;;
  esac

  local ERRORS=""
  local WARNINGS=""
  local ERROR_REGEX='^.* ([1-9][0-9]*) ERROR.*$'
  local WARNING_REGEX='^.* ([0-9]*) WARNING.*$'
  if [[ `cat $GTFS_DIR/$1.gtfsvtor.log` =~ $ERROR_REGEX ]]; then
    ERRORS=${BASH_REMATCH[1]}
  fi
  # We temporarilly copy gtfs files even if they have errors, as GTFSVTOR is not 100% backward compatible 
  # and more restrictive than feedvalidator, i.e. https://github.com/mecatran/gtfsvtor/issues/36  
  #else
    # We copy original file as well as potentially shape-enhanced file to validated dir, even if the last is not explicitly validated
  cp -p $GTFS_DIR/$1\.*gtfs.zip $GTFS_VALIDATED_DIR
  #fi
  if [[ `cat $GTFS_DIR/$1.gtfsvtor.log` =~ $WARNING_REGEX ]]; then
    WARNINGS=${BASH_REMATCH[1]}
  fi

  echo "<tr>
          <td><a href='$4'>$1</a></td>
          <td>`date -r $GTFS_DIR/$1.gtfs.zip  +%Y-%m-%d`</td>
          <td>$5</td>
          <td>$6</td>
          <td><a href="$2">Download</a></td>
          <td><a href="gtfsvtor_$1.html">Report</a></td>
          <td class='errors'>$ERRORS</td>
          <td class='warnings'>$WARNINGS</td>
        </tr>" >> $SUMMARY_FILE
}

mkdir -p $GTFS_DIR
mkdir -p $GTFS_VALIDATED_DIR
mkdir -p $REPORT_PUBLISH_DIR
echo "<html><head>
<meta charset='utf-8'/>
<meta name='viewport' content='width=device-width, initial-scale=1.0, user-scalable=no'/>
<style>
.errors { text-align: right; color: rgb(255, 0, 0); }
.warnings { text-align: right; color: rgb(255, 120, 0) }
</style>
<title>GTFS-Publikationen</title></head>
<body><h1>GTFS-Publikationen</h1>
<p>Nachfolgend sind f&uuml;r die uns derzeit bekannten GTFS-Ver&ouml;ffentlichungen deutscher Verkehrsunternehmen und- verb&uuml;nde die
Ergebnisse der GTFSVTOR-Pr&uuml;fung mit dem <a href="https://github.com/mecatran/gtfsvtor">Mecatran GTFSVTOR</a> Validator von Laurent Grégoire aufgelistet.</p>
<p><b>HINWEIS</b>: Einige Verkehrsverb&uuml;nde ver&ouml;ffentlichen Datens&auml;tze derzeit unter einer versionsbezogenen URL. VBB und HVV rufen wir nicht automatisiert ab,
da Last-Modified/If-Modified-Since derzeit nicht unterst&uuml;tzt werden bzw. der Datensatz nicht unter eine permanten URL bereitgestellt wird.
F&uuml;r diese k&ouml;nnen wir nicht automatisch die aktuellste Version pr&uuml;fen und hier listen. Wir freuen uns &uuml;ber einen Hinweis, sollte es aktuellere Daten oder auch
weitere Datenquellen geben.</p>
<p>Feedback bitte an "hb at mfdz de"</p>
<table><tr>
  <th>Verbund</th>
  <th>Datum</th>
  <th>Lizenz</th>
  <th>Namensnennung</th>
  <th>Download</th>
  <th>Validierung</th>
  <th>Fehler</th>
  <th>Warnungen</th>
</tr>" > $SUMMARY_FILE



while IFS=';' read -r name lizenz nammensnennung permanent downloadurl infourl email addshapes
do
  if ! [ "$name" == "shortname" ]; then # ignore first line
    download_and_check $name $downloadurl $permanent $infourl "$lizenz" "$nammensnennung" "$addshapes"
  fi
done < $GTFS_SOURCES_CSV

echo "</table>

<p>Unter <a href='https://www.github.com/mfdz/GTFS-Issues'>github/mfdz/GTFS-Issues</a> sind weitere Probleme oder Erweiterungswünsche
dokumentiert.</p>
<p>Weitere Informationen:</p>
<ul>
  <li><a href='https://github.com/mfdz/gtfs-hub/'>GitHub-Repository dieser Seite</a></li>
  <li><a href='https://developers.google.com/transit/gtfs/reference/'>GTFS-Spezifikation</a></li>
  <li><a href='https://gtfs.org/best-practices/'>GTFS Best Practices</a></li>
  <li><a href='https://developers.google.com/transit/gtfs/reference/gtfs-extensions'>Google GTFS Extensions</a></li>
</ul>

</body></html>" >> $SUMMARY_FILE


cp $GTFS_DIR/*.html $REPORT_PUBLISH_DIR/
