#!/bin/sh -x
BASE_DIR=`cd $(dirname $0)/.. && pwd`
CONFIG_FILE=$BASE_DIR/config/ca.template

ROOT_NAME="rootca"
INTERMEDIATE_NAME='intermediate'

ROOT_DAYS="7300"
INTERMEDIATE_DAYS="1800"

STORE_PASSWORD="123456"
BASE_DN='/O=example.com/OU=int'

ROOT_SUBJECT="CN=hfedev-mesh.istio.dev.infra.webex.com"
INTERMEDIATE_SUBJECT="CN=hfedev02.hfedev-mesh.istio.dev.infra.webex.com"

ACTION=$1

if [ -z $3 ]; then
   export CA_HOME="$BASE_DIR/certificates"
   echo "CA Home is not set, using default $CA_HOME"
else
   export CA_HOME=$3
fi

export CA_ROOT=$CA_HOME/$CA_NAME
export CA_INTERMEDIATE=$CA_HOME/$INTERMEDIATE

function createCA () {
   ca_name=$1
   subject=$2
   days=$3
   is_root=$4
   folder=$BASE_DIR/certificates/$ca_name
   if [ -d $folder ]; then
       timestamp=$(date "+%Y%m%d%H%M%S")
       echo "CA ${ca_name} exists, rename to ${ca_name}${timestamp}"
       mv ${folder} ${folder}${timestamp}
   fi
   mkdir -p ${folder}
   cd ${folder}
   mkdir certs private crl requests
   chmod 700 private
   echo 01 > serial
   touch index.txt
   touch index.txt.attr
   # Generate CA. The private key is stored "private" sub folder, which configured in conf file. Also a public certificate geneated with pem format
   # Generate new key and self-sign public certificate
   if [ ${is_root} -eq 1 ]; then
     x509_directive='-x509'
     out="cacert.pem"
   else
     x509_directive=''
     out="cert.csr"
   fi
   openssl req ${x509_directive}  -config ${CONFIG_FILE} -newkey rsa:2048  -days ${days} -out ${out} -subj ${subject} -nodes 2>/dev/null
   if [ $? -ne 0 ]; then
     echo "failed to generate CA ${ca_name}"
     return 1
   fi
   echo "generate CA ${ca_name} is done"
}

function generateCertificate()  {
   local cert_name=$1
   if [ -d $CA_HOME/$cert_name ]; then
       echo "Certificate $cert_name exist, remove it"
       rm -rf $CA_HOME/$cert_name
   else 
       echo "Generate Certificate $cert_name"
       mkdir -p $CA_HOME/$cert_name
       cd $CA_HOME/$cert_name
       #Generate Key
       openssl genrsa -out key.pem 2048
       #Generate CSR
       openssl req -new -key key.pem -out cert.csr -outform PEM -subj "${BASE_DN}/OU=Server Certificates/CN=${cert_name}/" -nodes
       #Sign Certificate with Root CA        
       #signCertificate $CA_HOME/$cert_name/cert.csr
   fi
}

function signCertificate() {
   local ca_home=$1
   local cert_home=$2
   local purpose=$3
   cd $ca_home
   case ${purpose} in
       0) echo "intermediate"
       extensions='root_ca_extensions'
       out='cacert.pem'
       ;;
       1) echo "server auth & client auth"
       extensions='certificate_extensions'
       out='cert.pem'
       ;;
       2) echo "client auth only"
       extensions='client_ca_extensions'
       out='cert.pem'
       ;;
       3) echo "server auth only"
       extensions='server_ca_extensions'
       out='cert.pem'
       ;;
   esac
   openssl ca -config $CONFIG_FILE -in ${cert_home}/cert.csr -out  $cert_home/${out} -notext -batch -extensions ${extensions}
}


function printCertificate() {
  local cer_name=$1
  echo "Print Certificate... $CA_HOME"
  openssl x509 -in $CA_HOME/$cer_name/cert.pem -noout -text
}


function exportToJKS() {
   local cert_name=$1
   local cert_home=$CA_HOME/$cert_name
   echo "Cert Home: $cert_home"
   cd $cert_home
   if [ -f keystore ]; then
       echo "found keystore, override it"
       rm -f keystore
   fi
   openssl pkcs12 -export -in cert.pem -inkey key.pem -passout pass:"$STORE_PASSWORD" > server.p12 
   $JAVA_HOME/bin/keytool -importkeystore -srckeystore server.p12 -srcstorepass $STORE_PASSWORD -destkeystore keystore -srcstoretype pkcs12 -deststoretype pkcs12  -deststorepass $STORE_PASSWORD
   $JAVA_HOME/bin/keytool -changealias -keystore keystore -storepass $STORE_PASSWORD -alias 1 -destalias server
   
   $JAVA_HOME/bin/keytool -import -trustcacerts -alias rootca -file $CA_HOME/rootca/cacert.pem -keystore truststore -storepass $STORE_PASSWORD -noprompt
   $JAVA_HOME/bin/keytool -import -trustcacerts -alias intermediate -file $CA_HOME/intermediate/cacert.pem -keystore truststore -storepass $STORE_PASSWORD -noprompt
     
}

case $1 in
1) echo "Create Root"
   createCA ${ROOT_NAME} ${ROOT_SUBJECT} ${ROOT_DAYS} 1
   ;;
2) echo "Create Intermediate"
   createCA ${INTERMEDIATE_NAME} ${INTERMEDIATE_SUBJECT} ${INTERMEDIATE_DAYS} 0
   signCertificate ${BASE_DIR}/certificates/${ROOT_NAME}  ${BASE_DIR}/certificates/${INTERMEDIATE_NAME} 0
   ;;
3) echo "Geneate Server Certificate for $2"
   generateCertificate $2
   signCertificate ${BASE_DIR}/certificates/${INTERMEDIATE_NAME}  ${BASE_DIR}/certificates/$2 1
   ;;
4) echo "Print Certificate"
   printCertificate $2
   ;;
5) echo "Export to JKS"
   exportToJKS $2
   ;;
6) echo "Batch From file"
   batchFromFile $2
   ;;
   
esac

