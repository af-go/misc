#!/bin/bash
BASE_DIR=`cd $(dirname $0)/.. && pwd`
cat $BASE_DIR/certificates/intermediate/private/cakey.pem  $BASE_DIR/certificates/intermediate/cacert.pem > $BASE_DIR/intermediate.pem

data=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' $BASE_DIR/intermediate.pem)


echo "{" > $BASE_DIR/bundle.json
echo "  \"pem_bundle\": \"${data}\"" >> $BASE_DIR/bundle.json
echo "}" >> $BASE_DIR/bundle.json



