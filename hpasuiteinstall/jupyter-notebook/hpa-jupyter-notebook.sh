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
# This script will run jupyter-notebook
#
#***********************************************************#
#                JUPYTER NOTEBOOK VARIABLES                 #
#***********************************************************#

JUPYTER_OK=0
JUPYTER_ERR=1

# Change the directory to yours. E.g.: JUPYTER_HOME=/opt/anaconda2
JUPYTER_HOME=@JUPYTER_HOME@
JUPYTER_BIN_DIR=$JUPYTER_HOME/bin
JUPYTER_HOST=`hostname`

NOTEBOOK_PARAM=
NOTEBOOK_CLI=$JUPYTER_BIN_DIR/jupyter-notebook 

#***********************************************************#
# Name                 : notebook_usage
# Environment Variables: None
# Description          : Print notebook usage
# Parameters           : None
# Return Value         : None
#***********************************************************#
function notebook_usage()
{
    cat << NOTEBOOK_HELP

-------------------------------------------------------------

Usage:  hpa-jupyter-notebook.sh -s [OPTIONS]
        hpa-jupyter-notebook.sh -q [OPTIONS]
        hpa-jupyter-notebook.sh -c
        hpa-jupyter-notebook.sh -h

        -s  Start jupyter notebook

        -q  Stop jupyter notebook

        -c  Check status of jupyter notebook

        -h  Show this message

-------------------------------------------------------------

Options:
`$NOTEBOOK_CLI --help`

-------------------------------------------------------------

NOTEBOOK_HELP

}

#***********************************************************#
# Name                 : notebook_status
# Environment Variables: None
# Description          : Check notebook status
# Parameters           : None
# Return Value         : None
#***********************************************************#
function notebook_status()
{
    $NOTEBOOK_CLI list
}

#***********************************************************#
# Name                 : notebook_start
# Environment Variables: None
# Description          : Start jupyter-notebook
# Parameters           : CLI jupyter-notebook parameters
# Return Value         : None
#***********************************************************#
function notebook_start()
{
    echo "INFO - Starting jupyter notebook ..."
    if [ ! -f "$NOTEBOOK_CLI" ]; then
        echo "ERROR - Cannot execute the program '$NOTEBOOK_CLI'. Make sure 'JUPYTER_HOME' is set and the program is executable."
        exit $JUPYTER_ERR
    fi
    blaunch -no-wait -z $JUPYTER_HOST $NOTEBOOK_CLI -y --ip $JUPYTER_HOST --allow-root $NOTEBOOK_PARAM &
    sleep 2
    notebook_status
}

#***********************************************************#
# Name                 : notebook_quit
# Environment Variables: None
# Description          : Stop jupyter-notebook
# Parameters           : CLI jupyter-notebook parameters
# Return Value         : None
#***********************************************************#
function notebook_quit()
{
    notebook_status
    $NOTEBOOK_CLI stop -y $NOTEBOOK_PARAM
    sleep 2
    notebook_status
}

#***********************************************************#
# Name                 : notebook_validation
# Environment Variables: JUPYTER_HOME
# Description          : Validation for jupyter-notebook
# Parameters           : None
# Return Value         : None
#***********************************************************#
function notebook_validation()
{
    if [ "$JUPYTER_HOME" == "" ]; then
        echo "ERROR - 'JUPYTER_HOME' environment variable not specified. Make sure 'JUPYTER_HOME' is set."
        exit $JUPYTER_ERR
    fi

    if [ ! -f "$NOTEBOOK_CLI" ]; then
        echo "ERROR - Cannot execute the program '$NOTEBOOK_CLI'. Make sure 'JUPYTER_HOME' is set and the program is executable."
        exit $JUPYTER_ERR
    fi
}

#***********************************************************#
# Name                 : jupyter_notebook
# Environment Variables: None
# Description          : Main process for jupyter-notebook
# Parameters           : CLI jupyter-notebook parameters
# Return Value         : None
#***********************************************************#
function jupyter_notebook()
{
    NOTEBOOK_PARAM=${@:2}
    notebook_validation

    if [ "$1" == "-s" ]; then
        notebook_start
    elif [ "$1" == "-q" ]; then
        notebook_quit
    elif [ "$1" == "-c" ]; then
        notebook_status
    elif [ "$1" == "-h" ]; then
        notebook_usage
    else
        notebook_usage
        exit $JUPYTER_ERR
    fi

    exit $JUPYTER_OK
}

jupyter_notebook $@
