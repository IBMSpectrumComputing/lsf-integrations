#!/bin/bash
#
# Licensed Materials - Property of IBM
# 5725-G82
# @ Copyright IBM Corp. 2009, 2017 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# 

#
# version: 1.3.0
GEDIT_CMD="/usr/bin/gedit"
LM_LICENSE_FILE="aa"


#number of  tasks per host
SPAN="span[ptile=1]"

#Source COMMON functions
. ${GUI_CONFDIR}/application/COMMON
. ${GUI_CONFDIR}/application/LOG_FUNC

LOG_LEVEL=3

export FLUENT_ARCH=lnamd64
export PATH=$PATH
export LM_LICENSE_FILE

#if [ "x$FLUENT_JOURNAL" = "x" ]; then
#    echo "You must specify a .jou file to submit a FLUENT job." 1>&2
#    LOG_ERROR "You must specify a .jou file to submit a FLUENT job."
#    exit 1
#fi

if [ "x$EXTRA_PARAMS" != "x" ]; then
    RESULT=`isValidOption "$EXTRA_PARAMS"`
    if [ "$RESULT" == "N" ] ; then
        LOG_ERROR "EXTRA_PARAMS[$EXTRA_PARAMS] is invalid, exit"
        exit 1
    fi
fi

#check BSUB parameters and create final bsub options

if [ "x$NCPU" != "x" ]; then
        NCPU_OPT="-n $NCPU"
else
        NCPU_OPT=""
fi

if [ "x$JOB_NAME" != "x" ]; then
        JOB_NAME_OPT="-J \"$JOB_NAME\""
else
        JOB_NAME_OPT="-J `basename $OUTPUT_FILE_LOCATION`"
fi

if [ "x$QUEUE" != "x" ]; then
        SUB_QUEUE_OPT="-q $QUEUE"
else
        SUB_QUEUE_OPT=""
fi

if [ "x${RUNHOST}" != "x" -a "x${RUNHOST}" != "xany" ]; then
	RUNHOST=`formatMutilValue "${RUNHOST}"`
	RUNHOST_OPT="-m \"${RUNHOST}\""
else
        RUNHOST_OPT=""
fi 

if [ "x$RELEASE" != "x" ]; then
        RELEASE_OPT="-r$RELEASE"
else
        RELEASE_OPT=""
fi

if [ "x$PAC_HOSTTYPE" != "x" ]; then
        HOSTTYPE_OPT="-mpi=$PAC_HOSTTYPE"
else
        HOSTTYPE_OPT=""
fi

if [ "x$FLUENT_JOURNAL" != "x" ]; then
	FLUENT_JOURNAL_FILE=`formatFilePath "${FLUENT_JOURNAL}"`
	#FLUENT_JOURNAL_FILE=`echo $FLUENT_JOURNAL_FILE | sed 's/^.*\///' `
	FLUENT_JOURNAL_FILE=${FLUENT_JOURNAL_FILE/\(/\\(}
	FLUENT_JOURNAL_FILE=${FLUENT_JOURNAL_FILE/\)/\\)}
	FLUENT_JOURNAL_OPT="-i $FLUENT_JOURNAL_FILE"
else
	FLUENT_JOURNAL_OPT=""
	DISTRIBUTE_FLUENT_JOURNAL_OPT=""
fi

LSF_OPT=-lsf


OUTPUT_FILE_LOCATION_OPT="-o \"$OUTPUT_FILE_LOCATION/output.${EXECUTIONUSER}.txt\""
CWD_OPT="-cwd \"$OUTPUT_FILE_LOCATION\""

case "$MEMARC" in
        Sequential)
                LSF_OPT=""
                SSH_OPT=""
                HOSTTYPE_OPT=""
                FLUENT_NCPU_OPT=""
                NCPU_OPT=""
                SPAN=""
                ;;
        SMP)
                if [ "x$NCPU" = "x1" ]; then
                        echo "You selected an SMP (parallel job). Select at least 2 CPUs." 1>&2
                        LOG_ERROR "EXTRA_PARAMS[$EXTRA_PARAMS]You selected an SMP (parallel job). Select at least 2 CPUs."
                        exit 1
                fi
                LSF_OPT=""
                SSH_OPT=""
                HOSTTYPE_OPT=""
                SPAN="span[hosts=1]"
                FLUENT_NCPU_OPT="-t$NCPU"
                ;;
        DMP)
                if [ "x$NCPU" = "x1" ]; then
                        echo "You selected a DMP (distributed parallel job). Select at least 2 CPUs." 1>&2
                        LOG_ERROR "You selected a DMP (distributed parallel job). Select at least 2 CPUs."
                        exit 1
                fi
                if [ "x$SPAN" = "x" ]; then
                        echo "You selected a DMP (distributed parallel job). Select a span option." 1>&2
                        LOG_ERROR "You selected a DMP (distributed parallel job). Select a span option."
                        exit 1
                fi
                FLUENT_NCPU_OPT="-t$NCPU"
                ;;
        *)
                echo "${MEMARC}: The memory architecture you specified is not recognized." 1>&2
                LOG_ERROR "${MEMARC}: The memory architecture you specified is not recognized."
                exit 1
                ;;
esac

if [ "x$SPAN" != "x" ]; then
        LSF_RESREQ="$LSF_RESREQ $SPAN"
fi

if [ "x$LSF_RESREQ" != "x" ]; then
        LSF_RESREQ="-R \"$LSF_RESREQ\""
fi

GRAPHIC_OPT="-g"
CONSOLE_SUPPORT=`echo $CONSOLE_SUPPORT | tr a-z A-Z`
if [ "$CONSOLE_SUPPORT" = "YES" -a "$VNCSession" = "User" ]; then
        LOG_DEBUG "Start VNC session<USER> by calling ${GUI_CONFDIR}/application/vnc/startvnc.sh $(dirname $OUTPUT_FILE_LOCATION) ${EXECUTIONUSER} ${VNC_WIDTH} ${VNC_HEIGHT}"
        VNC_SID=`${GUI_CONFDIR}/application/vnc/startvnc.sh $(dirname $OUTPUT_FILE_LOCATION) ${EXECUTIONUSER} ${VNC_WIDTH} ${VNC_HEIGHT}`  
        if [ "${VNCServer}" = "" ]; then
            VNCServer=${HOSTNAME}
        fi
        DISPLAY="${VNCServer}:${VNC_SID}.0"   
        GRAPHIC_OPT=""  
        export DISPLAY  VNC_SID
        LOG_DEBUG "Started VNC session"
fi  

if [ "$CONSOLE_SUPPORT" = "YES" -a "$VNCSession" = "Job" ]; then
        LOG_DEBUG "Started VNC session<JOB> "
        # copy VNC starter to job data directory
        mkdir -p "${OUTPUT_FILE_LOCATION}/.spooler_action"

        LOG_DEBUG "Copy ${GUI_CONFDIR}/application/vnc/startvnc_prejob.sh to ${OUTPUT_FILE_LOCATION}/.spooler_action"
        cp -fp ${GUI_CONFDIR}/application/vnc/startvnc_prejob.sh "${OUTPUT_FILE_LOCATION}/.spooler_action"

        LOG_DEBUG "Copy ${GUI_CONFDIR}/application/vnc/stopvnc_prejob.sh to ${OUTPUT_FILE_LOCATION}/.spooler_action"
        cp -fp ${GUI_CONFDIR}/application/vnc/stopvnc_prejob.sh "${OUTPUT_FILE_LOCATION}/.spooler_action"

        cp -fp ${GUI_CONFDIR}/application/vnc/startVncSession_prejob.sh "${OUTPUT_FILE_LOCATION}/.spooler_action"
        LOG_DEBUG "Copy ${GUI_CONFDIR}/application/vnc/startVncSession_prejob.sh ${OUTPUT_FILE_LOCATION}/.spooler_action"

        cp -fp ${GUI_CONFDIR}/application/vnc/vnc_common.sh "${OUTPUT_FILE_LOCATION}/.spooler_action"
        LOG_DEBUG "Copy ${GUI_CONFDIR}/application/vnc/vnc_common.sh ${OUTPUT_FILE_LOCATION}/.spooler_action"

        LOG_DEBUG "${GUI_CONFDIR}/application/vnc/xstartup.template ${OUTPUT_FILE_LOCATION}/.spooler_action/xstartup.template"
        cp -fp ${GUI_CONFDIR}/application/vnc/xstartup.template "${OUTPUT_FILE_LOCATION}/.spooler_action/xstartup.template"

        LOG_DEBUG "Copy done"

        export VNC_SID="-1" 
        GRAPHIC_OPT=""
        
        LOG_DEBUG "/bin/sh -c bsub  -B -N ${JOB_NAME_OPT} ${CWD_OPT} ${SUB_QUEUE_OPT} ${RUNHOST_OPT} ${NCPU_OPT} ${LSF_RESREQ} ${OUTPUT_FILE_LOCATION_OPT} ${EXTRA_PARAMS} .spooler_action/startvnc_prejob.sh ${GEDIT_CMD}  2>&1 "
        JOB_RESULT=`/bin/sh -c "bsub  -B -N ${JOB_NAME_OPT} ${CWD_OPT} ${SUB_QUEUE_OPT} ${RUNHOST_OPT} ${NCPU_OPT} ${LSF_RESREQ} ${OUTPUT_FILE_LOCATION_OPT} ${EXTRA_PARAMS} \".spooler_action/startvnc_prejob.sh ${GEDIT_CMD} \" 2>&1 "`
else

        OS_VERSION=$(cat /etc/redhat-release | sed -ne 's/[[:alpha:]]+*\s*//gp'|awk '{print $1}' | awk -F. '{print $1}')
        LOG_DEBUG "/bin/sh -c bsub -B -N ${JOB_NAME_OPT} ${CWD_OPT} ${SUB_QUEUE_OPT} ${RUNHOST_OPT} ${NCPU_OPT} ${LSF_RESREQ} ${OUTPUT_FILE_LOCATION_OPT} ${EXTRA_PARAMS} \" ${GEDIT_CMD} \" 2>&1"
        JOB_RESULT=`/bin/sh -c "bsub -B -N ${JOB_NAME_OPT} ${CWD_OPT} ${SUB_QUEUE_OPT} ${RUNHOST_OPT} ${NCPU_OPT} ${LSF_RESREQ} ${OUTPUT_FILE_LOCATION_OPT} ${EXTRA_PARAMS} \" ${GEDIT_CMD} \" 2>&1" `
fi

export JOB_RESULT OUTPUT_FILE_LOCATION
LOG_DEBUG "export $JOB_RESULT=JOB_RESULT; OUTPUT_FILE_LOCATION=$OUTPUT_FILE_LOCATION"
${GUI_CONFDIR}/application/job-result.sh
