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
# This script will run dask-scheduler
#
#***********************************************************#
#                 DASK SCHEDULER VARIABLES                  #
#***********************************************************#

DASK_OK=0
DASK_ERR=1

# Change the directory to yours. E.g.: DASK_HOME=/opt/anaconda2
DASK_HOME=@DASK_HOME@
DASK_BIN_DIR=$DASK_HOME/bin

SCHEDULER_PARAM=
SCHEDULER_PID=
SCHEDULER_PID_FILE=/tmp/hpa-dask-scheduler-pid
SCHEDULER_CLI=$DASK_BIN_DIR/dask-scheduler

#***********************************************************#
# Name                 : scheduler_usage
# Environment Variables: None
# Description          : Print scheduler usage
# Parameters           : None
# Return Value         : None
#***********************************************************#
function scheduler_usage()
{
    cat << SCHEDULER_HELP

-------------------------------------------------------------

Usage:  hpa-dask-scheduler.sh -s [OPTIONS]
        hpa-dask-scheduler.sh -q
        hpa-dask-scheduler.sh -c
        hpa-dask-scheduler.sh -h

        -s  Start dask scheduler

        -q  Stop dask scheduler

        -c  Check status of dask scheduler

        -h  Show this message

-------------------------------------------------------------

Options:
`$SCHEDULER_CLI --help | grep -v "Options:\|Usage:\|--help"`

-------------------------------------------------------------

SCHEDULER_HELP

}

#***********************************************************#
# Name                 : scheduler_status
# Environment Variables: None
# Description          : Check scheduler status
# Parameters           : None
# Return Value         : None
#***********************************************************#
function scheduler_status()
{
    SCHEDULER_PID=`ps -ef |grep -v grep |grep $SCHEDULER_CLI |grep $SCHEDULER_PID_FILE |awk '{print $2}' |xargs`
    if [ -z "$SCHEDULER_PID" ]; then
        echo "INFO - There is no dask scheduler started by LSF"
        return $DASK_ERR
    fi

    echo "INFO - Dask scheduler PID <$SCHEDULER_PID> is running"
    return $DASK_OK
}

#***********************************************************#
# Name                 : scheduler_start
# Environment Variables: None
# Description          : Start dask-scheduler
# Parameters           : CLI dask-scheduler parameters
# Return Value         : None
#***********************************************************#
function scheduler_start()
{
    echo "INFO - Starting dask scheduler ..."
    $SCHEDULER_CLI $SCHEDULER_PARAM --pid-file $SCHEDULER_PID_FILE
}

#***********************************************************#
# Name                 : scheduler_quit
# Environment Variables: None
# Description          : Stop dask-scheduler
# Parameters           : CLI dask-scheduler parameters
# Return Value         : None
#***********************************************************#
function scheduler_quit()
{
    scheduler_status
    if [ $? -ne 0 ]; then
        return;
    fi

    echo -e "INFO - Stopping dask scheduler PID <$SCHEDULER_PID> ...\c"
    kill -9 $SCHEDULER_PID > /dev/null 2>&1
    echo "Stopped"
}

#***********************************************************#
# Name                 : scheduler_validation
# Environment Variables: DASK_HOME
# Description          : Validation for dask-scheduler
# Parameters           : None
# Return Value         : None
#***********************************************************#
function scheduler_validation()
{
    if [ "$DASK_HOME" == "" ]; then
        echo "ERROR - 'DASK_HOME' environment variable not specified. Make sure 'DASK_HOME' is set."
        exit $DASK_ERR
    fi

    if [ ! -f "$SCHEDULER_CLI" ]; then
        echo "ERROR - Cannot execute the program '$SCHEDULER_CLI'. Make sure 'DASK_HOME' is set and the program is executable."
        exit $DASK_ERR
    fi
}

#***********************************************************#
# Name                 : dask_scheduler
# Environment Variables: None
# Description          : Main process for dask-scheduler
# Parameters           : CLI dask-scheduler parameters
# Return Value         : None
#***********************************************************#
function dask_scheduler()
{
    SCHEDULER_PARAM=${@:2}
    scheduler_validation

    if [ "$1" == "-s" ]; then
        scheduler_start
    elif [ "$1" == "-q" ]; then
        scheduler_quit
    elif [ "$1" == "-c" ]; then
        scheduler_status
    elif [ "$1" == "-h" ]; then
        scheduler_usage
    else
        scheduler_usage
        exit $DASK_ERR
    fi

    exit $DASK_OK
}

dask_scheduler $@
