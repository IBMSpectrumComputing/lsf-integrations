#!/bin/bash
#**************************************************************************
#  Copyright International Business Machines Corp, 2019. 
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

#
# The script of to start ipython controller and engines, invoked by hpa-ipython.

#start ipython controller
ipcontroller --ip="*" --profile=${IPYTHON_PROFILE} > /dev/null 2>&1 &
# ipcontroller --ip="*" --profile=${IPYTHON_PROFILE} > /tmp/ipython_con.logs 2>&1 &

echo Start ipython controller on $IPYTHON_MASTER successfully.

#start engines on each hosts, using blaunch to start engines
HOST=false
CORE=false
for STR in $LSB_MCPU_HOSTS
do
    if [ $HOST = false ]; then
        HOST_STR=$STR
        HOST=true
    else
        CORE_STR=$STR
        CORE=true
    fi
    if [ $HOST = true ] && [ $CORE = true ]; then
	WORKER_NUM=1
	blaunch -no-wait -z $HOST_STR ${LSF_BINDIR}/hpa-start-ipython-engines.sh ${NUM_ENGINES} ${IPYTHON_PROFILE}
	echo Start ipython ${NUM_ENGINES} engines on $HOST_STR successfully. with $CORE_STR slots.
        HOST=false
        CORE=false
    fi
done

#wait 2 seconds to start engines
sleep 2