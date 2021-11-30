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
# This script will run dask-scheduler, dask-worker, 
# and dask application
#
#***********************************************************#
#                    LSF DASK VARIABLES                     #
#***********************************************************#

DASK_OK=0
DASK_ERR=1
DASK_APP=

SCHEDULER_HOST=`hostname`
SCHEDULER_PORT=8786
SCHEDULER_OPTIONS=

WORKER_OPTIONS=
WORKER_NUM=1

DASK_OPTION_NUM=$#
DASK_OPTIONS="$@"
DASK_ARG="$1"

#***********************************************************#
# Name                 : dask_usage
# Environment Variables: None
# Description          : Print dask usage
# Parameters           : None
# Return Value         : None
#***********************************************************#
function dask_usage()
{
    cat << DASK_HELP

--------------------------------------------------------------------------------------------

Usage:  hpa-dask.sh -A <application> -S <scheduler options> -W <worker options>
        hpa-dask.sh -h

--------------------------------------------------------------------------------------------

        -A <application>
        (Optional) Dask application in python to be run, if this argument is not specified, 
        launch dask scheduler and workers only.

        -S <scheduler options>
        (Optional) Dask scheduler options, run the command "dask-scheduler --help" 
        for more details about the options.

        -W <worker options>
        (Optional) Dask worker options, run the command "dask-worker --help" 
        for more details about the options.

        -h  Show the help

--------------------------------------------------------------------------------------------

DASK_HELP

}

#***********************************************************#
# Name                 : dask_start
# Environment Variables: LSB_MCPU_HOSTS, sample: 
#                        LSB_MCPU_HOSTS=hostA 4 hostB 8 hostC 16
# Description          : Launch dask
# Parameters           : CLI dask parameters
# Return Value         : None
#***********************************************************#
function dask_launch()
{
    # Launch dask scheduler
    blaunch -no-wait -z $SCHEDULER_HOST $LSF_BINDIR/hpa-dask-scheduler.sh -s $SCHEDULER_OPTIONS &
    echo "INFO - Launched dask scheduler on host $SCHEDULER_HOST"

    INDEX=0
    HOST_NAME=
    HOST_SLOTS=0

    # Launch dask workers
    for MCPU_HOST in $LSB_MCPU_HOSTS; do
        ((INDEX++))
        if [ $(($INDEX % 2)) -eq 0 ]; then
            HOST_SLOTS=$MCPU_HOST
            blaunch -no-wait -z $HOST_NAME $LSF_BINDIR/hpa-dask-worker.sh -s "$SCHEDULER_HOST:$SCHEDULER_PORT" $WORKER_OPTIONS &
            echo "INFO - Launched dask worker on host $HOST_NAME with $HOST_SLOTS slots"
        else
            HOST_NAME=$MCPU_HOST
        fi
    done
}

#***********************************************************#
# Name                 : dask_app_run
# Environment Variables: None
# Description          : Run dask application
# Parameters           : CLI dask parameters
# Return Value         : None
#***********************************************************#
function dask_app_run()
{
    echo "INFO - Running dask application <$DASK_APP>"
    python $DASK_APP
}

#***********************************************************#
# Name                 : dask_destroy
# Environment Variables: LSB_MCPU_HOSTS, sample: 
#                        LSB_MCPU_HOSTS=hostA 4 hostB 8 hostC 16
# Description          : Destroy dask
# Parameters           : None
# Return Value         : None
#***********************************************************#
function dask_destroy()
{
    INDEX=0
    HOST_NAME=
    HOST_SLOTS=0

    # Stop dask workers
    for MCPU_HOST in $LSB_MCPU_HOSTS; do
        ((INDEX++))
        if [ $(($INDEX % 2)) -eq 0 ]; then
            HOST_SLOTS=$MCPU_HOST
            blaunch -no-wait -z $HOST_NAME $LSF_BINDIR/hpa-dask-worker.sh -q
            echo "INFO - Stopped dask worker on host $HOST_NAME"
        else
            HOST_NAME=$MCPU_HOST
        fi
    done

    # Stop dask scheduler
    blaunch -no-wait -z $SCHEDULER_HOST $LSF_BINDIR/hpa-dask-scheduler.sh -q
    echo "INFO - Stopped dask scheduler on host $SCHEDULER_HOST"
}

#***********************************************************#
# Name                 : dask_init
# Environment Variables: None
# Description          : Initialize variables
# Parameters           : None
# Return Value         : None
#***********************************************************#
function dask_init()
{
    DASK_APP=`echo ${DASK_OPTIONS#*-A}`
    DASK_APP=`echo ${DASK_APP%-S*}`
    DASK_APP=`echo ${DASK_APP%-W*}`

    WORKER_OPTIONS=`echo ${DASK_OPTIONS#*-W}`
    WORKER_OPTIONS=`echo ${WORKER_OPTIONS%-S*}`
    WORKER_OPTIONS=`echo ${WORKER_OPTIONS%-A*}`

    SCHEDULER_OPTIONS=`echo ${DASK_OPTIONS#*-S}`
    SCHEDULER_OPTIONS=`echo ${SCHEDULER_OPTIONS%-W*}`
    SCHEDULER_OPTIONS=`echo ${SCHEDULER_OPTIONS%-A*}`
}

#***********************************************************#
# Name                 : dask_validate
# Environment Variables: DASK_HOME
# Description          : Validation for the arguments
# Parameters           : None
# Return Value         : None
#***********************************************************#
function dask_validate()
{
    if [ $DASK_ARG == "-h" ]; then
        dask_usage
        exit $DASK_OK
    elif [  $DASK_OPTION_NUM -lt 1 ]; then
        dask_usage
        exit $DASK_ERR
    elif [  $DASK_ARG != "-A" ] && [  $DASK_ARG != "-S" ] && [  $DASK_ARG != "-W" ]; then
        dask_usage
        exit $DASK_ERR
    fi

    # Initialize variables
    dask_init

    if [ "$DASK_APP" == "" ]; then
        echo "ERROR - Specify dask application with argument '-A <application>'"
        exit $DASK_ERR
    elif [ ! -e $DASK_APP ]; then
        echo "ERROR - The dask application '$DASK_APP' does not exist."
        exit $DASK_ERR
    fi
}

#***********************************************************#
# Name                 : dask_main
# Environment Variables: None
# Description          : Main process for dask
# Parameters           : CLI dask parameters
# Return Value         : None
#***********************************************************#
function dask_main()
{
    # Validate arguments
    dask_validate

    # Launch dask scheduler and workers
    dask_launch

    # Run dask application
    dask_app_run

    # Stop dask scheduler and workers
    dask_destroy

    exit $DASK_OK
}

dask_main $@
