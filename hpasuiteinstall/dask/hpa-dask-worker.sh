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
# This script will run dask-worker
#
#***********************************************************#
#                   DASK WORKER VARIABLES                   #
#***********************************************************#

DASK_OK=0
DASK_ERR=1

# Change the directory to yours. E.g.: DASK_HOME=/opt/anaconda2
DASK_HOME=$DASK_HOME
DASK_BIN_DIR=$DASK_HOME/bin
DASK_SCHEDULER=`hostname`":8786"

WORKER_PARAM=
WORKER_PID=
WORKER_PID_FILE=/tmp/hpa-dask-worker-pid
WORKER_CLI=$DASK_BIN_DIR/dask-worker

#***********************************************************#
# Name                 : worker_usage
# Environment Variables: None
# Description          : Print worker usage
# Parameters           : None
# Return Value         : None
#***********************************************************#
function worker_usage()
{
    cat << WORKER_HELP

-------------------------------------------------------------

Usage:  hpa-dask-worker.sh -s [SCHEDULER] [OPTIONS]
        hpa-dask-worker.sh -q
        hpa-dask-worker.sh -c
        hpa-dask-worker.sh -h

        -s  Start dask worker

        -q  Stop dask worker

        -c  Check status of dask worker

        -h  Show this message

-------------------------------------------------------------

Scheduler:

E.g.:  $DASK_SCHEDULER

-------------------------------------------------------------

Options:
`$WORKER_CLI --help | grep -v "Options:\|Usage:\|--help"`

-------------------------------------------------------------

WORKER_HELP

}

#***********************************************************#
# Name                 : worker_status
# Environment Variables: None
# Description          : Check worker status
# Parameters           : None
# Return Value         : None
#***********************************************************#
function worker_status()
{
    WORKER_PID=`ps -ef |grep -v grep |grep $WORKER_CLI |grep $WORKER_PID_FILE |awk '{print $2}' |xargs`
    if [ -z "$WORKER_PID" ]; then
        echo "INFO - There is no dask worker started by LSF"
        return $DASK_ERR
    fi

    echo "INFO - Dask worker PID <$WORKER_PID> is running"
    return $DASK_OK
}

#***********************************************************#
# Name                 : worker_start
# Environment Variables: None
# Description          : Start dask-worker
# Parameters           : CLI dask-worker parameters
# Return Value         : None
#***********************************************************#
function worker_start()
{
    echo "INFO - Starting dask worker..."
    if [ ! -f "$WORKER_CLI" ]; then
        echo "ERROR - Cannot execute the program '$WORKER_CLI'. Make sure 'DASK_HOME' is set and the program is executable."
        exit $DASK_ERR
    fi

    $WORKER_CLI $WORKER_PARAM --pid-file $WORKER_PID_FILE
}

#***********************************************************#
# Name                 : worker_quit
# Environment Variables: None
# Description          : Stop dask-worker
# Parameters           : None
# Return Value         : None
#***********************************************************#
function worker_quit()
{
    worker_status
    if [ $? -ne 0 ]; then
        return;
    fi

    echo -e "INFO - Stopping dask worker PID <$WORKER_PID> ...\c"
    kill -9 $WORKER_PID > /dev/null 2>&1
    echo "Stopped"
}

#***********************************************************#
# Name                 : worker_validation
# Environment Variables: DASK_HOME
# Description          : Validation for dask-worker
# Parameters           : None
# Return Value         : None
#***********************************************************#
function worker_validation()
{
    if [ "$DASK_HOME" == "" ]; then
        echo "ERROR - 'DASK_HOME' environment variable not specified. Make sure 'DASK_HOME' is set."
        exit $DASK_ERR
    fi

    if [ ! -f "$WORKER_CLI" ]; then
        echo "ERROR - Cannot execute the program '$WORKER_CLI'. Make sure 'DASK_HOME' is set and the program is executable."
        exit $DASK_ERR
    fi
}

#***********************************************************#
# Name                 : dask_worker
# Environment Variables: None
# Description          : Main process for dask-worker
# Parameters           : CLI dask-worker parameters
# Return Value         : None
#***********************************************************#
function dask_worker()
{
    WORKER_PARAM=${@:2}
    worker_validation

    if [ "$1" == "-s" -a "$WORKER_PARAM" != "" ]; then
        worker_start
    elif [ "$1" == "-q" ]; then
        worker_quit
    elif [ "$1" == "-c" ]; then
        worker_status
    elif [ "$1" == "-h" ]; then
        worker_usage
    else
        worker_usage
        exit $DASK_ERR
    fi

    exit $DASK_OK
}

dask_worker $@
