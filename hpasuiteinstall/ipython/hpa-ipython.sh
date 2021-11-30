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

# The wrapper script of ipython, to start ipython as an interactive LSF job

# Set environments, modify it to yours
# IPYTHONDIR: A shared directory in LSF cluster is needed for this parameter. IPython stores its files-config, command history and extensions in the directory. 
# Change the directory to yours. E.g.: IPYTHONDIR=/home/fengli/ipython_workdir/
export IPYTHONDIR=@IPYTHONDIR@
# NUM_ENGINES: Define how many engines will be started on each host. The value is 2 by default
export NUM_ENGINES=2
# IPYTHON_PROFILE: Special the profile name of ipython will be used or set it as "default".
export IPYTHON_PROFILE=default
# PARALLEN_SUPPORT: (Y/N) define whether support parallel computing or NOT, by default this value is Y.
export PARALLEN_SUPPORT=Y


function cleanup()
{
	HOST_STR=""
	CORE_STR=""
	for STR in $LSB_MCPU_HOSTS
	do
	    if [ "$HOST_STR" = "" ]; then
		HOST_STR=$STR
	    else
		CORE_STR=$STR
	    fi
	    if [ "$HOST_STR" != "" ] && [ "$CORE_STR" != "" ]; then
		blaunch -z $HOST_STR $LSF_BINDIR/hpa-stop-ipcluster.sh
		HOST_STR=""
		CORE_STR=""
	    fi
	done
}

if [ ! -d "${IPYTHONDIR}/profile_${IPYTHON_PROFILE}" ]; then
   ipython profile create ${IPYTHON_PROFILE}
fi

#get master host, the first execution host of LSF job
export IPYTHON_MASTER=`hostname`

if [ "X$PARALLEN_SUPPORT" = "XY" ] 
then
	trap cleanup EXIT
	. $LSF_BINDIR/hpa-start-ipcluster.sh
fi

#start ipython interactive terminal
ipython --profile=${IPYTHON_PROFILE} $@