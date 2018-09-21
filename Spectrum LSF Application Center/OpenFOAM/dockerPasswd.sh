#!/bin/sh
#
# Licensed Materials - Property of IBM
# 5725-G82
# @ Copyright IBM Corp. 2009, 2018 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#

# This utility creates passwd and group file in job's CWD/OUTPUT_FILE_LOCATION for container to use.
# Administrator have to define the path in lsb.applications file for each LSF application profile, i
# for example:  @/opt/ibm/lsfsuite/ext/gui/conf/application/dockerPasswd.sh in docker option 


JOBTMPDIR=$LS_EXECCWD # Assume the job's current working directory is shared for parallel jobs
if [ "x$JOBTMPDIR" = "x" ] ; then
echo "Are you testing outside of an LSF job?"
JOBTMPDIR=/tmp/$USER
mkdir $JOBTMPDIR
fi
 
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

