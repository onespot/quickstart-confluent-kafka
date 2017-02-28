#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Specifically, this script is intended SOLELY to support the Confluent
# Quick Start offering in Amazon Web Services. It is not recommended
# for use in any other production environment.
#
#
#
#
# Simple script to retrieve jar files from a known S3 location or
# top-level HTTP.  The jars are stored to 
# $CP_HOME/share/java/kafka-connect-extras .
#	NOTE: script must be run as user capable of creating/writing
#	to that directory.
#
# We try to be a bit smart about retrieving using S3 tooling (if
# possible) or simple curl logic (when S3 fails) to retrieve from 
# the S3 bucket.
#	NOTE: curl logic depends upon the presense of a file "jars.lst".
#
# Input (env vars)
#	S3_REGION (default is us-west-2)
#	CP_VERSION (default is 3.1.1)
#	
# usage:
#	retrieve-connect-jars.sh <s3_bucket | URL>
#		Retrieval from S3 bucket will be directly from that bucket
#			if there is a trailing '/', otherwise from 
#			"<bucket>/connectors/<ver>"
#		Retrieval from URL will be direct from that location
#
# examples
#	retrieve-connect-jars.sh s3://confluent-cft-devel
#	retrieve-connect-jars.sh s3://my-extra-connectors/
#	retrieve-connect-jars.sh https://public-web-service.com/connector-archive
#

THIS_SCRIPT=`readlink -f $0`
SCRIPTDIR=`dirname ${THIS_SCRIPT}`

LOG=/tmp/cp-retrieve-connect-jars.log

if [ -f /tmp/cversion ] ; then
	CP_VERSION=$(cat /tmp/cversion)
else
	CP_VERSION=${CP_VERSION:-3.1.1}
fi

S3_REGION=${S3_REGION:-us-west-2}
CP_HOME=${CP_HOME:-/opt/confluent-$CP_VERSION}
[ ! -d $CP_HOME ] && CP_HOME=/opt/confluent 

CONNECTOR_JAR_SRC=${1:-s3://confluent-cft-devel}
LFILE=${LFILE:-jars.lst}
TARGET_DIR=/tmp/cdownload_$$

do_s3_retrieval() {
	S3_TOP="${1%/}/"
	aws s3 cp --recursive ${S3_TOP} $TARGET_DIR/
	[ $? -ne 0 ] && return 1

	rm -f $TARGET_DIR/${LFILE} 
	if [ ! -f $TARGET_DIR/${LFILE} ] ; then
		cd $TARGET_DIR; ls > $TARGET_DIR/${LFILE} 
	fi
	return 0
}

# Curl against Amazon buckets is unhappy with double '/' characters,
# so we always strip off the trailing one.
do_curl_retrieval() {
	SRC_URL=${1%/}
	curl -f -s ${SRC_URL}/${LFILE} -o $TARGET_DIR/${LFILE} 
	[ $? -ne 0 ] && return 1

	for f in $(cat $TARGET_DIR/${LFILE}) ; do
		[ -n "$f" ] && curl -f -s ${SRC_URL}/$f -o $TARGET_DIR/$f
	done
}

set -x

##### Execution Logic starts here 

main()
{
    echo "$0 script started at "`date` >> $LOG

	mkdir -p $TARGET_DIR

		# If S3 is specified, download from there.   
		# If that fails (most likely due to issues with aws tool), simply
		# fall back to a curl retrieval.
		#
	if [ -z "${CONNECTOR_JAR_SRC%s3:*}" ] ; then
		if [ -z "${CONNECTOR_JAR_SRC##*/}" ] ; then
			S3_SRC="${CONNECTOR_JAR_SRC}"
		else
			S3_SRC="${CONNECTOR_JAR_SRC}/connectors/${CP_VERSION//./}"
		fi
		S3_BUCKET=${S3_SRC#s3://}
		S3_BUCKET=${S3_BUCKET%%/*}
		HTTP_SRC=https://s3-${S3_REGION}.amazonaws.com/${S3_SRC#s3://}

		do_s3_retrieval ${S3_SRC}
		if [ $? -ne 0 ] ; then
			do_curl_retrieval ${HTTP_SRC}
		fi
	fi

		# If HTTP or HTTPS is specified, download from there.   
		# Users _may_ have not directly specified the sub-directory, so
		# we'll try the default "connectors/<ver>" if necessary
		#
	if [ -z "${CONNECTOR_JAR_SRC%http://*}" -o -z "${CONNECTOR_JAR_SRC%https://*}" ] ; then
		do_curl_retrieval ${CONNECTOR_JAR_SRC}
		if [ $? -ne 0 ] ; then
			do_curl_retrieval ${CONNECTOR_JAR_SRC}/connectors/${CP_VERSION//./}
		fi
	fi


		# If the jars.lst file ($LFILE) exists, we were successful in 
		# our download.  We can copy stuff into place.
		#
	if [ -f $TARGET_DIR/${LFILE} ] ; then
		mkdir -p $CP_HOME/share/java/kafka-connect-extras
		cp $TARGET_DIR/*.jar $CP_HOME/share/java/kafka-connect-extras
		[ $? -eq 0 ] && rm -f ${TARGET_DIR}/* && rmdir ${TARGET_DIR}

		chown -R --reference $CP_HOME/share/java $CP_HOME/share/java/kafka-connect-extras 
	fi

	echo "$0 script finished at "`date` >> $LOG
}


main $@
exitCode=$?

set +x
