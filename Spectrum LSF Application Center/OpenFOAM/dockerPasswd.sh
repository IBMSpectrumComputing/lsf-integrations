#!/bin/sh
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

# This utility creates passwd and group file in job's CWD/OUTPUT_FILE_LOCATION before docker start 
# the container, the script must locate in the shared diretory for all LSF server hosts. 
# for example:  @/scratch/shared_job_directory/dockerPasswd.sh 


JOBTMPDIR=<JOB_REPOSITORY_TOP> # replace the value with real shared directory, AC admin must have write permission on this directory
if [ ! -d ${JOBTMPDIR}/tmp ]; then
    mkdir ${JOBTMPDIR}/tmp 2>&1
fi
if [ ! -d ${JOBTMPDIR}/tmp/${USER} ]; then
    mkdir ${JOBTMPDIR}/tmp/${USER} 2>&1
fi
JOBTMPDIR=${JOBTMPDIR}/tmp/${USER}
 
UFILE=$JOBTMPDIR/.passwd.$LSB_JOBID.$LSB_JOBINDEX
GFILE=$JOBTMPDIR/.group.$LSB_JOBID.$LSB_JOBINDEX
if [ -f /bin/id ]; then
    IDCMD="/bin/id $LSFUSER"
else
    IDCMD="/usr/bin/id $LSFUSER"
fi
 
# clear out the UFILE and GFILE
cat /dev/null > $UFILE
cat /dev/null > $GFILE
 
## copy local passwd and group files?
#cat /etc/passwd > $UFILE
#cat /etc/group > $GFILE
 
UID1=`$IDCMD -u`
GID1=`$IDCMD -g`
 
# Add current user to UFILE
echo "$USER:x:$UID1:$GID1:::" >> $UFILE
 
# mount option for the UFILE and GFILE
echo -n " -v $UFILE:/etc/passwd"
echo -n " -v $GFILE:/etc/group"
 
# Add groups
GLIST=`$IDCMD -Gn`
IDX=0
for GID2 in `$IDCMD -G`
do
    IDX=`expr $IDX + 1`
    GN2=`echo $GLIST | cut -d " " -f $IDX`
 
    echo "$GN2:x:$GID2:" >> $GFILE
    echo -n " --group-add $GID2"
done
 
# add newline to standard output
echo
chmod 644  $UFILE
chmod 644 $GFILE

