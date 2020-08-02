#! /bin/bash

#------------------------------------------------
function echoColorRed() {
	echo -e "\e[1;31m" $1 "\e[0m"
}
function echoColorYellow() {
	echo -e "\e[1;33m" $1 "\e[0m"
}
function echoColorGreen() {
	echo -e "\e[1;32m" $1 "\e[0m"
}

function color()(set -o pipefail;"$@" 2>&1>&3|sed $'s,.*,\e[31m&\e[m,'>&2)3>&1

#------------------------------------------------
function rmImage() {
	docker stop   $1	> /dev/null 2>&1 
	docker rm -f  $1	> /dev/null 2>&1 
	docker rmi -f $1    	> /dev/null 2>&1 
	echo "Removing $1 ..."
}
#------------------------------------------------
function clean() {
rm -rf xinetd_src
rm -rf xinetd_opt
rm Dockerfile.dev
rm Dockerfile.gol
rm SERVICE_GOL
rm service.py
rm xinetd.conf
docker rmi -f `docker images | grep "none" | awk '{ print $3}'` > /dev/null 2>&1 
}
#************** START **************************
#------------------------------------------------
if [ -z "${1}" ]
then
   _self="${0##*/}"
    echoColorRed "ERROR:" 
    echoColorYellow "usage ${_self} xinet_src.zip"
   exit
fi

echoColorGreen "-----------------------------------"
echo
echoColorGreen	"${0##*/}"
echo
export SRC_FILE_PATH="${PWD}/${1}"
echoColorGreen   "SOURCE FILE PATH: ${SRC_FILE_PATH}"
export SRC_FILE="$(basename -- ${SRC_FILE_PATH})"
echoColorGreen   "SOURCE FILE: ${SRC_FILE}"
export SRC_FILE_NAME="${SRC_FILE%???????}"
echoColorGreen   "SOURCE FILE NAME: ${SRC_FILE_NAME}"
echo
echoColorGreen  "-----------------------------------"

clean 
mkdir ${PWD}/xinetd_opt
mkdir ${PWD}/xinetd_src 

color tar xvf ${SRC_FILE_PATH} -C ${PWD}/xinetd_src 

echo "
FROM 	alpine
RUN		apk	add gcc g++ make autoconf bash
RUN		echo \"#! /bin/bash\" > /build.sh
RUN		echo \"./configure --prefix=/opt/${SRC_FILE_NAME}  && make && make install \" >> build.sh
RUN		chmod u+x /build.sh
WORKDIR	/root/${SRC_FILE_NAME}
" > Dockerfile.dev

rmImage alpine-dev
echoColorYellow "=================================="
echoColorYellow "Build Develeopment Image"
echoColorYellow "=================================="
color docker build --squash-all -t alpine-dev -f Dockerfile.dev 
echoColorYellow "=================================="

echoColorGreen "Building xinetd"
echoColorGreen "==================================="
color docker run --rm -v ${PWD}/xinetd_src:/root:Z -v ${PWD}/xinetd_opt:/opt/:Z alpine-dev /build.sh
echoColorGreen "==================================="

rmImage alpine-dev

echo "
FROM	alpine
RUN     apk add python3 py-pip
COPY	xinetd_opt  /opt
COPY	xinetd.conf /opt/${SRC_FILE_NAME}/etc
RUN	rm /opt/${SRC_FILE_NAME}/etc/xinetd.d/*
COPY    SERVICE_GOL /opt/${SRC_FILE_NAME}/etc/xinetd.d
RUN	mkdir /opt/${SRC_FILE_NAME}/service
RUN	mkdir /opt/${SRC_FILE_NAME}/var
COPY    service.py  /opt/${SRC_FILE_NAME}/service
RUN     chmod u+x /opt/${SRC_FILE_NAME}/service/service.py
RUN     adduser -u 1000 --disabled-password --disabled-password  gol
RUN	chown -R gol:gol /opt/${SRC_FILE_NAME}
USER    gol
WORKDIR /opt/${SRC_FILE_NAME}
EXPOSE  5555:5555
CMD      "/opt/${SRC_FILE_NAME}/sbin/xinetd -dontfork -filelog /opt/${SRC_FILE_NAME}/var/xinetd.log -f /opt/${SRC_FILE_NAME}/etc/xinetd.conf" 
" > Dockerfile.gol

color cp `find  xinetd_src/ -name "xinetd.conf" -print` .

sed -i "s|/etc/xinetd.d|/opt/${SRC_FILE_NAME}/etc/xinetd.d|" xinetd.conf

echo "service gol_service
{
    type           = UNLISTED
    protocol       = tcp
    disable        = no
    port           = 5555
    flags          = REUSE
    socket_type    = stream
    wait           = no
    user           = gol
    server         = /opt/${SRC_FILE_NAME}/service/service.py
    log_on_failure += USERID
}
" > SERVICE_GOL

echo "#!/usr/bin/python3
import sys
request = ''
while True:
  data = sys.stdin.readline().strip()
  request = request + data + '<br>'
  if data == \"\":
    print ('HTTP/1.0 200 OK')
    print ('')
    print ('<html><body><p>'+request+'</p></body></html>')
    sys.stdout.flush()
    break;
" > service.py

echoColorGreen "Bulding final xinetd image ....."
echoColorGreen "==========================================="
color docker build --squash-all -t xinetd-gol -f Dockerfile.gol
echoColorGreen "==========================================="


echo "#! /bin/bash

docker stop xinetd-gol  > /dev/null 2>&1 
docker rm -f xinetd-gol  > /dev/null 2>&1 
docker run --ip 10.88.0.100 --name=\"xinetd-gol\" -d xinetd-gol
docker logs xinetd-gol

" > runXinetdService.sh

chmod u+x runXinetdService.sh

clean




