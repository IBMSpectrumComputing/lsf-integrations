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
#
# version: 10.2.0.9

#==========BEGIN MANDATORY-PARAMETERS(INTERNAL USE ONLY, DO NOT CHANGE)===============================
#PUBLISH_NOTES This template allows users to run OpenFOAM. It is required to follow the instructions at  <a href="https://github.com/IBMSpectrumComputing/lsf-integrations/tree/master/Spectrum%20LSF%20Application%20Center/OpenFOAM"> OpenFOAM README.md </a> prior to using this template. 
#MANDATORY  OF_VER(OpenFOAM Version) OF_VER: Support for openfoam6 or OpenFOAM-v1912.
#MANDATORY  MPI_INTERFACE(Network interface for MPI traffic) MPI_INTERFACE: Use ifconfig to get the highest speed network interface available on your LSF servers.

if [ -z "$OF_VER" ] || [ -z "$MPI_INTERFACE" ]; then
    echo "Required parameters have not been set."  1>&2
    exit 1
fi
#==========END MANDATORY-PARAMETERS=================================

# Only supporting openfoam6 or OpenFOAM-v1912
if [ "$OF_VER" != "openfoam6" ] && [ "$OF_VER" != "OpenFOAM-v1912" ]; then
    echo "Set OF_VER to either openfoam6 or OpenFOAM-v1912 in $0."  1>&2
    exit 1
fi

#Source COMMON functions
. ${GUI_CONFDIR}/application/COMMON

function script_echo {
    string1=$1
    if [ -n "$string1" ]; then # not blank
        echo "$string1"
        echo "on_error_exit" 
        echo
    fi
}

export LANG=C
export LC_ALL=C

OF_DIR="/opt/$OF_VER"
DEBUG_MPI=0
  
if [ -z "$CASE_DIR" ]; then
        echo "You must specify an OpenFOAM case directory to submit an OpenFOAM job." 1>&2
        exit 1
else
        CASE_DIR=`echo $CASE_DIR | sed 's/[a-z]*://g' | tr -d \"`
        CASE_NAME=`basename $CASE_DIR`
fi

cd $OUTPUT_FILE_LOCATION/
#if submit from Data page, the directory is copied over before submission script
if [ ! -d $CASE_NAME ]; then
    cp -R $CASE_DIR  .
fi
cd $CASE_NAME
  
if [ -n "x$NCPU" ]; then
        NCPU_OPT="-n $NCPU"
else
        NCPU_OPT=""
        NCPU="1"
fi

MAKE_MESH=""
if [ -f makeMesh ]; then
    MAKE_MESH="$OUTPUT_FILE_LOCATION/$CASE_NAME/makeMesh"
fi
  
if [ -f system/decomposeParDict ]; then
    MESH_CMD="$MESH"
    DECOMPOSER_CMD="decomposePar"

    MPIRUN_CMD=""
    APP_OPT=""
    RECON_CMD=""

    # list of apps that do not support -parallel 
    NON_PARALLEL="boundaryFoam|cfx4ToFoam|chemFoam|datToFoam|mshToFoam"
    echo $APP_CMD | egrep $NON_PARALLEL > /dev/null
    if [ $? -ne 0 ]; then   # add parallel option
       if [ "$OF_VER" = "OpenFOAM-v1912" ]; then   # add LSF & openMPI support
          MPIRUN_CMD="mpirun"                                                # use container mpirun
          MPIRUN_CMD="$MPIRUN_CMD -mca btl_tcp_if_include $MPI_INTERFACE"    # only use MPI_INTERFACE 
          MPIRUN_CMD="$MPIRUN_CMD -mca btl ^openib -mca pml ob1"             # exclude infiniband
          MPIRUN_CMD="$MPIRUN_CMD -mca plm ^rsh"                             # exclude rsh 
          if [ $DEBUG_MPI -eq 1 ]; then
             MPIRUN_CMD="$MPIRUN_CMD -mca plm_base_verbose 10"               # debug 
          fi
          APP_OPT="-parallel"
          RECON_CMD="reconstructPar"
       else
          #MPIRUN_CMD="mpirun -np $NCPU -mca plm ^rsh" # use container mpirun
          NHOST=1
       fi
    else
       NHOST=1
    fi

    ADVANCED_OPT="-R \"span[hosts=1]\""  # default to using 1 host
    if [ $NCPU -gt 1 ]; then
       if [ $NHOST -gt 1 2>/dev/null ]; then
          # must source the OpenFOAM bashrc on each node when running across multiple nodes
          FOAM_CMD="$MPIRUN_CMD /bin/bash -c 'source $OF_DIR/etc/bashrc && $APP_CMD $APP_OPT'"
          PTILE=$(($NCPU/$NHOST))
          ADVANCED_OPT="-R \"span[ptile=$PTILE]\""
       else
          FOAM_CMD="$MPIRUN_CMD $APP_CMD $APP_OPT"
       fi
    else
       DECOMPOSER_CMD=""
       FOAM_CMD="$APP_CMD"  # no need for MPI
       RECON_CMD=""
    fi

    #replace numberOfSubdomains value in system/decomposeParDict with $NCPU
    sed -i '/^numberOfSubdomains/c\'"numberOfSubdomains $NCPU;"  system/decomposeParDict
  
    #replace method value in  system/decomposeParDict with $METHOD
    sed -i '/^method/c\'"method $METHOD;"  system/decomposeParDict
else
    MESH_CMD=$MESH
    DECOMPOSER_CMD=""
    FOAM_CMD=$APP_CMD
fi
  
#Replace application value in system/controlDict with $APP_CMD
sed -i '/^application/c\'"application $APP_CMD;"   system/controlDict

##########################################################
# Begin: create bsub submission script
##########################################################

BSUB_SCRIPT=$OUTPUT_FILE_LOCATION/$CASE_NAME/bsub.${JOB_NAME//\ /_}
exec 3>&1  # Link file descriptor #3 with stdout.
exec > $BSUB_SCRIPT  # stdout replaced with file "bsub.$JOBNAME".
echo "#!/bin/bash"
echo "function on_error_exit {"
echo "RT=\$?;if [ \$RT -ne 0 ]; then exit \$RT;fi"
echo "}"
echo

script_echo "source $OF_DIR/etc/bashrc"
script_echo "$MAKE_MESH"
script_echo "$MESH_CMD"
# add "a" before case name to make it easier for user to spot the .foam file
script_echo "touch a${CASE_NAME}.foam"
script_echo "$DECOMPOSER_CMD"
script_echo "$FOAM_CMD"
#script_echo "$RECON_CMD"
#script_echo "convertData output.${EXECUTIONUSER}.txt"

exec 1>&3 3>&-  # Restore stdout and close file descriptor #3.

if [ "x$JOB_NAME" != "x" ]; then
        JOB_NAME_OPT="-J \"$JOB_NAME\"_$CASE_NAME"
else
        JOB_NAME_OPT="-J `basename $OUTPUT_FILE_LOCATION`"
fi


OUT_OPT="-o \"$OUTPUT_FILE_LOCATION/$CASE_NAME/output.${EXECUTIONUSER}.txt\""
ERR_OPT="-e \"$OUTPUT_FILE_LOCATION/$CASE_NAME/error.${EXECUTIONUSER}.txt\""
CWD_DIR="-cwd \"$OUTPUT_FILE_LOCATION/$CASE_NAME\""

chmod a+x $BSUB_SCRIPT
  
JOB_RESULT=`/bin/sh -c "bsub -B -N ${ADVANCED_OPT} -app openfoam ${NCPU_OPT} ${OUT_OPT} ${ERR_OPT} ${CWD_DIR} ${JOB_NAME_OPT}   $BSUB_SCRIPT 2>&1"`

export JOB_RESULT OUTPUT_FILE_LOCATION
${GUI_CONFDIR}/application/job-result.sh
