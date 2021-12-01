#!/bin/bash
#**************************************************************************
#  Copyright International Business Machines Corp, 2018. 
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#**************************************************************************

function randomPort() {
    local PORT_START=3333
    local PORT_RANGE=60000
    local FLOOR=0
    local PORT=0

    while [ $PORT -le $FLOOR ]; do
        PORT=$RANDOM
        let PORT%=$PORT_RANGE
    done

    let PORT=$PORT+$PORT_START
    echo "$PORT"
}

export LANG=C
export LC_ALL=C
# Wraper to Tensorboard for use with LSF Application Center 
# arg1 = LOGDIR
# arg2 = PORT

if [ $# -lt 1 ] ; then
	echo "Expecting at least a log directory argument"
	exit 2
fi

LOGDIR=$1
if [ $# -eq 1 ] ; then
	lcv=0
	found_free_port=0
	while [ $found_free_port -eq 0  ] && [ $lcv -lt 100 ] ; do
        	let lcv=$lcv+1
		PORT=$(randomPort)
		out=`netstat -tln | grep ":$PORT "`
		result=$?
                if [ $result -eq 1 ]; then
                        found_free_port=1
                fi
	done
	if [ $found_free_port -eq 0 ] ; then
		echo "Could not find free port in $lcv tries."
		exit 3
	fi
else
	PORT=$2
fi


# generate an html file for user to access Tensorboard
EXE_HOST=`hostname`
htmlf="click_url_$LSB_JOBID.html"
echo "<html>" > $htmlf
echo "<body>" >> $htmlf
echo "<head>" >> $htmlf
echo "<title>Redirect to Tensorboard</title>" >> $htmlf
echo "<meta http-equiv=\"refresh\" content=\"0; url='http://$EXE_HOST:$PORT'\">" >> $htmlf
#echo -n "'http://$EXE_HOST:$PORT'>" >> $htmlf
#echo '"' >> $htmlf
#echo '<a href="http://'$EXE_HOST':'$PORT'">'$EXE_HOST':'$PORT'</a>' >> $htmlf 
echo "<meta name=\"keywords\" content=\"automatic redirection\">" >> $htmlf
echo "</head>" >> $htmlf
echo "<body>" >> $htmlf
echo "Click the URL below to access Tensorboard on " >> $htmlf
#echo '<a href="http://'$EXE_HOST':'$PORT'">'$EXE_HOST':'$PORT'</a>' >> $htmlf 
echo "<a href=\"http://$EXE_HOST:$PORT\">$EXE_HOST:$PORT</a>" >> $htmlf 
echo "</body>" >> $htmlf
echo "</html>" >> $htmlf

# Use new PAC 10.2.0.6 joblink capabilitiy
#echo "http://%H:$PORT" > .joblink
echo "http://$EXE_HOST:$PORT" > .joblink

/usr/local/bin/tensorboard --logdir $LOGDIR --port $PORT

