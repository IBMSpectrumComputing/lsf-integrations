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
# version: 10.2.0.1

#Source COMMON functions
. ${GUI_CONFDIR}/application/COMMON

export LANG=C
export LC_ALL=C

  
if [ "x$CASE_DIR" = "x" ]; then
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
  
if [ "x$NCPU" != "x" ]; then
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

    # list of apps that do not support -parallel 
    NON_PARALLEL="boundaryFoam|cfx4ToFoam|chemFoam|datToFoam|mshToFoam"
    echo $APP_CMD | egrep $NON_PARALLEL > /dev/null
    if [ $? -ne 0 ]; then   # add parallel option
       MPIRUN_CMD="mpirun -tcp -mca plm lsf" # set appropriate mpirun options
       APP_OPT="-parallel"
       RECON_CMD="reconstructPar"
    else
       MPIRUN_CMD=""
       APP_OPT=""
       RECON_CMD=""
    fi

    if [ $NCPU -gt 1 ]; then
       FOAM_CMD="$MPIRUN_CMD $APP_CMD $APP_OPT"
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
echo "if [ -f /opt/ibm/spectrum_mpi/smpi.sh ]; then "
echo "source /opt/ibm/spectrum_mpi/smpi.sh"
echo "fi"
echo "source /opt/openfoam6/etc/bashrc"
echo "$MAKE_MESH"
echo "on_error_exit"
echo "$MESH_CMD"
echo "on_error_exit"
# add "a" before case name to make it easier for user to spot the .foam file
echo "touch a${CASE_NAME}.foam"
echo "$DECOMPOSER_CMD"
echo "on_error_exit"
echo "$FOAM_CMD"
echo "on_error_exit"
echo "$RECON_CMD"
echo "on_error_exit"
#echo "convertData output.${EXECUTIONUSER}.txt"
#echo "on_error_exit"
  
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
  
JOB_RESULT=`/bin/sh -c "bsub -B -N -R "span[hosts=1]" -app openfoam ${NCPU_OPT} ${OUT_OPT} ${ERR_OPT} ${CWD_DIR} ${JOB_NAME_OPT}   $BSUB_SCRIPT 2>&1"`

export JOB_RESULT OUTPUT_FILE_LOCATION
${GUI_CONFDIR}/application/job-result.sh
