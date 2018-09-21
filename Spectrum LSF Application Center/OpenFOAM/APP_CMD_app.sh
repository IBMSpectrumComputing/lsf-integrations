#!/bin/bash
#
# Licensed Materials - Property of IBM
# 5725-G82
# @ Copyright IBM Corp. 2009, 2017 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# 

#this script control APP_CMD value based on file CASE_DIR/system/controlDict from case directory selection

echo "<field-control visible=\"true\" type=\"default\">"
if [ x$CASE_DIR = x -o ! -d $CASE_DIR -o ! -d $CASE_DIR/system ];then
        echo "<option value=\"simpleFoam\" /> "

else
        CTRL_FILE=`ls $CASE_DIR/system/controlDict 2>&1`
        if [ $? = 0 ]; then
		APP_CMD=`cat $CTRL_FILE | awk '{if ($1=="application") print $2}' | sed 's/;//g'`
        else
               APP_CMD="simpleFoam"
        fi
        echo "<option value=\"$APP_CMD\" />"
fi
echo "</field-control>"
