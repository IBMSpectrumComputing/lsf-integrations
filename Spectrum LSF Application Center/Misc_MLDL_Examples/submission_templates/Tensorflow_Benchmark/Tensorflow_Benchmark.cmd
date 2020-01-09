#!/bin/bash

#version: 1.3.0
#BatchConstants.JOB_SUBMISSION_CUSTOMIZE_CMD = customize_cmd
#BatchConstants.JOB_SUBMISSION_GENERIC = generic
#BatchConstants.CLUSTER_NAME = cluster_name

#==========BEGIN MANDATORY-PARAMETERS(INTERNAL USE ONLY, DO NOT CHANGE)===============================
#PUBLISH_NOTES This template allows users to run Tensorflow Benchmarks. It is required to follow the instructions at  <a href="https://community.ibm.com/community/user/imwuc/blogs/john-welch/2019/12/20/running-tensorflow-benchmark-with-horovod-across-i"> Running Tensorflow benchmark with Horovod... article </a> prior to using this template. This Template currently only supports IBM Power servers with NVIDIA GPUs.
#MANDATORY  MPI_INTERFACE(Network interface for MPI traffic) MPI_INTERFACE: Use ifconfig to get the highest speed network interface available on your LSF servers with GPUs.

if [ -z "$MPI_INTERFACE" ]; then
    echo "Required parameters have not been set."  1>&2
    exit 1

fi
#==========END MANDATORY-PARAMETERS=================================

#Source COMMON functions
. ${GUI_CONFDIR}/application/COMMON
  
TFB_TOP=/usr/local/benchmarks
TFB_SCRIPTS="$TFB_TOP/scripts"
export PATH=$TFB_SCRIPTS:/usr/local/scripts:$PATH

LSF_OPT=""
ADVANCED_OPT=""
LIMITS_OPT=""
CUSTOMIZE_OPT=""

APP_PROFILE=tensorflow_horovod

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
#
# mpirun command command and benchmark command
#
if [ "$NUM_HOST" != "1" ] ; then
        # only use mpirun when more than 1 host

	# testing mpirun with powerai container
	COMMANDTORUN="mpirun" 
        COMMANDTORUN="$COMMANDTORUN -mca btl_tcp_if_include $MPI_INTERFACE -x HOROVOD_GLOO_IFACE=$MPI_INTERFACE" # only use $MPI_INTERFACE network 
        COMMANDTORUN="$COMMANDTORUN -mca btl ^openib -mca pml ob1 -x NCCL_IB_DISABLE=1" 		# exclude infiniband
        COMMANDTORUN="$COMMANDTORUN -mca plm_base_verbose 10 -x NCCL_DEBUG=WARN" 			# debug options

	# benchmark with horovod only accepts 1 gpu per task 
	OTHER_OPT="gpu_bind.sh python $TFB_SCRIPTS/tf_cnn_benchmarks/tf_cnn_benchmarks.py --variable_update=horovod --num_gpus=1"
else
	COMMANDTORUN="python $TFB_SCRIPTS/tf_cnn_benchmarks/tf_cnn_benchmarks.py --num_gpus=$GPU_PER_HOST"
fi


# Example
# --model resnet101 --batch_size 15 --variable_update=horovod

# add the MODEL 
if [ -n "$MODEL" ] ; then
	OTHER_OPT="$OTHER_OPT --model $MODEL"
else
	echo "Model was not specified " 1>&2
	exit 1
fi
  
# add the optional BATCH_SIZE 
if [ -n "$BATCH_SIZE" ] ; then
	OTHER_OPT="$OTHER_OPT --batch_size $BATCH_SIZE"
fi

# add the optional NUM_BATCHES
if [ -n "$NUM_BATCHES" ] ; then
	OTHER_OPT="$OTHER_OPT --num_batches=$NUM_BATCHES"
fi

if [ -z "$COMMANDTORUN" ] ; then
	echo "Job command was not specified " 1>&2
	exit 1
fi

if [ -n "$JOB_NAME" ]; then
   LSF_OPT="-J \"$JOB_NAME\""
fi
#------------------------data options-----------------------------

if [ -n "$INPUT_FILE" ]; then
	INPUT_FILE=`formatFilePath "${INPUT_FILE}"`
	INPUT_FILE="\"${INPUT_FILE}\""
	LSF_OPT="$LSF_OPT -i $INPUT_FILE"
fi

if [ -n "$ERROR_FILE" ]; then
	ERROR_FILE=`formatFilePath "${ERROR_FILE}"`
	LSF_OPT="$LSF_OPT -e $ERROR_FILE"
fi

if [ -n "$OUTPUT_FILE" ]; then
	OUTPUT_FILE=`formatFilePath "${OUTPUT_FILE}"`
	LSF_OPT="$LSF_OPT -o $OUTPUT_FILE"
fi

#--------------------------advanced options-------------------------

###-----------------------Requirements------------------------------

# Calculate number CORES requested i.e. NUM_HOST * CORE_PER_HOST
CORE_PER_HOST=$GPU_PER_HOST    		# setting core per host equal to gpu per host to align 1 mpi task for each gpu requested
MIN_NUM_CPU=$((NUM_HOST*CORE_PER_HOST))
ADVANCED_OPT="$ADVANCED_OPT -n $MIN_NUM_CPU"

# GPUs per host
if [ -n "$GPU_PER_HOST" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -gpu \"num=$GPU_PER_HOST:mode=exclusive_process\""
fi

if [ "$NUM_HOST" == "1" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -R \"span[hosts=1]\""
else
    ADVANCED_OPT="$ADVANCED_OPT -R \"span[ptile=$CORE_PER_HOST]\" -R \"affinity[core(1)]\""
fi

if [ -n "${RUNHOST}" ]; then
	RUNHOST=`formatMutilValue "${RUNHOST}"`
	ADVANCED_OPT="$ADVANCED_OPT -m \"${RUNHOST}\""
fi

if [ -n "$EXTRA_RES" ]; then
	EXTRA_RES="-R \"$EXTRA_RES\""
    CUSTOMIZE_OPT="$CUSTOMIZE_OPT $EXTRA_RES"
fi

###-----------------------Additional Job Options--------------------
if [ -n "$LOGIN_SHELL" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -L $LOGIN_SHELL"
fi

if [ -n "$QUEUE" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -q $QUEUE"
fi

if [ -n "$APP_PROFILE" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -app $APP_PROFILE"
fi

if [ -n "$PRJ_NAME" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -P $PRJ_NAME"
fi

if [ -n "$RES_ID" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -U $RES_ID"
fi

if [ -n "$RERUNABLE" -a "$RERUNABLE" == "yes" ]; then
    ADVANCED_OPT="$ADVANCED_OPT -r"
fi

if [ -n "$EXTRA_PARAMS" ]; then
	RESULT=`isValidOption "$EXTRA_PARAMS"`
    if [ "$RESULT" == "N" ] ; then
		exit 1
	fi
    CUSTOMIZE_OPT="$CUSTOMIZE_OPT $EXTRA_PARAMS"
fi

# Add in a very rough job run time estimation
if [ "$NUM_BATCHES" == "10" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 1"
elif [ "$NUM_BATCHES" == "100" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 1"
elif [ "$NUM_BATCHES" == "200" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 2"
elif [ "$NUM_BATCHES" == "500" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 3"
elif [ "$NUM_BATCHES" == "1000" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 6"
elif [ "$NUM_BATCHES" == "2000" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 12"
elif [ "$NUM_BATCHES" == "5000" ] ; then
    ADVANCED_OPT="$ADVANCED_OPT -We 30"
fi

###--------------------------limits options-------------------------

if [ -n "$MAX_MEM" ]; then
    LIMITS_OPT="$LIMITS_OPT -M $MAX_MEM"
fi

if [ -n "$RUNLIMITHOUR" -a -n "$RUNLIMITMINUTE" ]; then
   LIMITS_OPT="$LIMITS_OPT -W $RUNLIMITHOUR:$RUNLIMITMINUTE"
elif [ -n "$RUNLIMITHOUR" ]; then
   LIMITS_OPT="$LIMITS_OPT -W $RUNLIMITHOUR:0"
elif [ -n "$RUNLIMITMINUTE" ]; then
   LIMITS_OPT="$LIMITS_OPT -W $RUNLIMITMINUTE"
fi

##########################################################
# Begin: create bsub submission script
##########################################################

BSUB_SCRIPT=$OUTPUT_FILE_LOCATION/bsub.script
exec 3>&1  # Link file descriptor #3 with stdout.
exec > $BSUB_SCRIPT  # stdout replaced with file "bsub.script".
echo "#!/bin/bash"
echo "function on_error_exit {"
echo "RT=\$?;if [ \$RT -ne 0 ]; then exit \$RT;fi"
echo "}"
echo
echo "$COMMANDTORUN $OTHER_OPT"  
echo "on_error_exit"
echo
echo "tf_cnn_benchmark_post_total.sh"
echo "on_error_exit"
  
exec 1>&3 3>&-  # Restore stdout and close file descriptor #3.

# make the script executable
chmod a+x $BSUB_SCRIPT

##########################################################
# End: create bsub submission script
##########################################################

CWD_OPT="-cwd \"$OUTPUT_FILE_LOCATION\""

JOB_RESULT=`/bin/sh -c "bsub ${CWD_OPT} ${LSF_OPT} ${ADVANCED_OPT} ${LIMITS_OPT} ${CUSTOMIZE_OPT} ${BSUB_SCRIPT} 2>&1"`

SUBMITTIME=`date +'%s'`

export JOB_RESULT OUTPUT_FILE_LOCATION
${GUI_CONFDIR}/application/job-result.sh
