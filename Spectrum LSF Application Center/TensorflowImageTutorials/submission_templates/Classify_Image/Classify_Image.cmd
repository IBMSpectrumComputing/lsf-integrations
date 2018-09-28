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

#version: 1.3.0
#BatchConstants.JOB_SUBMISSION_CUSTOMIZE_CMD = customize_cmd
#BatchConstants.JOB_SUBMISSION_GENERIC = generic
#BatchConstants.CLUSTER_NAME = cluster_name

#Source COMMON functions
. ${GUI_CONFDIR}/application/COMMON

# Set MLDL_TOP to where package was installed. For example: /opt/share/mldl
MLDL_TOP=#MLDL_TOP#
MLDL_SCRIPTS="$MLDL_TOP/scripts"
export PATH=$MLDL_SCRIPTS:$PATH

# Set the command to run 
COMMANDTORUN=classify_image.py
# assuming an application proifle has been setup to run Tensorflow within for this job submission
APP_PROFILE=docker_tensorflow

LSF_OPT=""
ADVANCED_OPT=""
LIMITS_OPT=""
CUSTOMIZE_OPT=""

##when user implement the method of using single file in job submission,
##uncomment the following control.
#isMultiFile=`echo "$INPUT_FILE" | awk '{ if(index($0,";") == 0) {print "N";} else {print "Y";}}'`
#if [ "$isMultiFile" = "Y" ] ; then
#	echo -n "You have selected multiple files but the input file field only allows to select one file. " 1>&2
#	echo "Specify only one file or add a new field that allows multiple data files." 1>&2
#	exit 1
#fi
isMultiFile=`echo "$ERROR_FILE" | awk '{ if(index($0,";") == 0) {print "N";} else {print "Y";}}'`
if [ "$isMultiFile" = "Y" ] ; then
	echo -n "You have selected multiple files but the error file field only allows to select one file. " 1>&2
	echo "Specify only one file or add a new field that allows multiple data files." 1>&2
	exit 1
fi
isMultiFile=`echo "$OUTPUT_FILE" | awk '{ if(index($0,";") == 0) {print "N";} else {print "Y";}}'`
if [ "$isMultiFile" = "Y" ] ; then
	echo -n "You have selected multiple files but the output file field only allows to select one file. " 1>&2
	echo "Specify only one file or add a new field that allows multiple data files." 1>&2
	exit 1
fi

#------------------------basic option----------------------------------
if [ "x$COMMANDTORUN" = "x" ] ; then
	echo "Job command was not specified " 1>&2
	exit 1
fi

# Only accept a jpg image file
if [ "x$IMAGE_FILE" != "x" ]; then
	if [[ "$IMAGE_FILE" == *\;* ]] ; then
		echo "Expecting one image file " 1>&2
		exit 1
	elif [[ "$IMAGE_FILE" != *jpg? && "$IMAGE_FILE" != *JPG? ]] ; then
		echo "Image file must be of type jpg $IMAGE_FILE " 1>&2
		exit 1
	fi
fi

# Use label_image.py for Retrain Flower model 
if [ "x$MODEL" != "x" -a "$MODEL" == "Retrain_Flower" ] ; then
	COMMANDTORUN=label_image.py
	# must supply image file for $MODEL
        if [ "x$IMAGE_FILE" != "x" ] ; then
		OTHER_OPT=" --image $IMAGE_FILE"
	else
		echo "The Model $MODEL requires an image file " 1>&2
		exit 1
    fi
fi
  
# Add num predictions for InceptionV3 model
if [ "$MODEL" != "Retrain_Flower" ] ; then
	# add the optional IMAGE_FILE
	if [ "x$IMAGE_FILE" != "x" ] ; then
		OTHER_OPT="$OTHER_OPT --image_file $IMAGE_FILE"
	fi
fi

# Add the optional number of predictions
if [ "x$NUM_PREDICTIONS" != "x" ] ; then
	OTHER_OPT="$OTHER_OPT --num_top_predictions $NUM_PREDICTIONS"
fi

JOB_COMMAND=`echo "$COMMANDTORUN" | awk -F":" '{ print $1}'`
if [ "x$JOB_COMMAND" = "x" ] ; then
	echo "Job command was not specified " 1>&2
	exit 1
fi

# Remove double quote firstly
JOB_COMMAND=`echo $JOB_COMMAND | sed 's/^"\|"$//g'`
# Add double quote
JOB_COMMAND="\"$JOB_COMMAND\""

JOB_PATH=`echo "$COMMANDTORUN" | awk -F":" '{ gsub("\"",""); print $2}'`
if [ "x$JOB_PATH" != "x" ] ; then
	PATH="$JOB_PATH":$PATH
	export PATH
	chmod -R a+x "$JOB_PATH" 1>&2
fi

if [ "x$JOB_NAME" != "x" ]; then
   LSF_OPT="-J \"$JOB_NAME\""
fi
#------------------------data options-----------------------------

if [ "x$INPUT_FILE" != "x" ]; then
	INPUT_FILE=`formatFilePath "${INPUT_FILE}"`
	INPUT_FILE="\"${INPUT_FILE}\""
	LSF_OPT="$LSF_OPT -i $INPUT_FILE"
fi

if [ "x$ERROR_FILE" != "x" ]; then
	ERROR_FILE=`formatFilePath "${ERROR_FILE}"`
	LSF_OPT="$LSF_OPT -e $ERROR_FILE"
fi

if [ "x$OUTPUT_FILE" != "x" ]; then
	OUTPUT_FILE=`formatFilePath "${OUTPUT_FILE}"`
	LSF_OPT="$LSF_OPT -o $OUTPUT_FILE"
fi

#--------------------------advanced options-------------------------

###-----------------------Requirements------------------------------
if [ "x$MIN_NUM_CPU" != "x" -a "x$MAX_NUM_CPU" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -n $MIN_NUM_CPU,$MAX_NUM_CPU"
elif [ "x$MIN_NUM_CPU" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -n $MIN_NUM_CPU"
elif [ "x$MAX_NUM_CPU" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -n $MAX_NUM_CPU"
fi

if [ "x$PROC_PRE_HOST" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -R \"span[ptile=$PROC_PRE_HOST]\""
fi

if [ "x${RUNHOST}" != "x" ]; then
	RUNHOST=`formatMutilValue "${RUNHOST}"`
	ADVANCED_OPT="$ADVANCED_OPT -m \"${RUNHOST}\""
fi

if [ "x$EXTRA_RES" != "x" ]; then
	EXTRA_RES="-R \"$EXTRA_RES\""
    CUSTOMIZE_OPT="$CUSTOMIZE_OPT $EXTRA_RES"
fi

###-----------------------Additional Job Options--------------------
if [ "x$LOGIN_SHELL" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -L $LOGIN_SHELL"
fi

if [ "x$QUEUE" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -q $QUEUE"
fi

if [ "x$APP_PROFILE" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -app $APP_PROFILE"
fi

if [ "x$PRJ_NAME" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -P $PRJ_NAME"
fi

if [ "x$RES_ID" != "x" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -U $RES_ID"
fi

if [ "x$RERUNABLE" != "x" -a "$RERUNABLE" == "yes" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -r"
fi

if [ "x$EXTRA_PARAMS" != "x" ]; then
	RESULT=`isValidOption "$EXTRA_PARAMS"`
    if [ "$RESULT" == "N" ] ; then
		exit 1
	fi
    CUSTOMIZE_OPT="$CUSTOMIZE_OPT $EXTRA_PARAMS"
fi

###--------------------------limits options-------------------------

if [ "x$MAX_MEM" != "x" ]; then
    LIMITS_OPT="$LIMITS_OPT -M $MAX_MEM"
fi

if [ "x$RUNLIMITHOUR" != "x" -a "x$RUNLIMITMINUTE" != "x" ]; then
   LIMITS_OPT="$LIMITS_OPT -W $RUNLIMITHOUR:$RUNLIMITMINUTE"
elif [ "x$RUNLIMITHOUR" != "x" ]; then
   LIMITS_OPT="$LIMITS_OPT -W $RUNLIMITHOUR:0"
elif [ "x$RUNLIMITMINUTE" != "x" ]; then
   LIMITS_OPT="$LIMITS_OPT -W $RUNLIMITMINUTE"
fi

CWD_OPT="-cwd \"$OUTPUT_FILE_LOCATION\""

#echo "bsub ${LSF_OPT} ${ADVANCED_OPT} ${LIMITS_OPT} ${CUSTOMIZE_OPT} ${JOB_COMMAND}" >> /tmp/aaa
#env > /tmp/pac_$$.txt 2>&1
JOB_RESULT=`/bin/sh -c "bsub ${CWD_OPT} ${LSF_OPT} ${ADVANCED_OPT} ${LIMITS_OPT} ${CUSTOMIZE_OPT} ${JOB_COMMAND} ${OTHER_OPT} 2>&1"`

export JOB_RESULT OUTPUT_FILE_LOCATION
${GUI_CONFDIR}/application/job-result.sh
