#!/bin/bash
#
# Licensed Materials - Property of IBM
# 5725-G82
# @ Copyright IBM Corp. 2009, 2017 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# 

#this script control NCPU value based on file CASE_DIR/system/ from case directory selection

if [ x$CASE_DIR = x -o ! -d $CASE_DIR -o ! -d $CASE_DIR/system -o ! -f $CASE_DIR/system/decomposeParDict ];then
        echo "<field-control visible=\"false\" type=\"default\">"
        echo "<option value=\"1\" /> "

else
        P_FILE="$CASE_DIR/system/decomposeParDict" 
	CPU=`grep "^numberOfSubdomains" $P_FILE | awk '{if ($1=="numberOfSubdomains") print $2}' | sed 's/;//g'`
        echo "<field-control visible=\"true\" type=\"default\">"
        echo "<option value=\"$CPU\" />"
fi
echo "</field-control>"
