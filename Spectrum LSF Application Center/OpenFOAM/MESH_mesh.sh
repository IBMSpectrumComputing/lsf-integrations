#!/bin/bash
#
# Licensed Materials - Property of IBM
# 5725-G82
# @ Copyright IBM Corp. 2009, 2017 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# 

#this script control MESH value based on file CASE_DIR/system/*MeshDict from case directory selection

echo "<field-control visible=\"true\" type=\"default\">"
if [ x$CASE_DIR = x -o ! -d $CASE_DIR -o ! -d $CASE_DIR/system ];then
        #echo "<option value=\"blockMesh\" /> "
        echo "<option value=\"\" /> "

else
        for MESH_FILE in $CASE_DIR/system/*MeshDict $CASE_DIR/system/*MeshDict.m4
        do
            if [ -f $MESH_FILE ]; then
                MESH_CMD=`basename $MESH_FILE | sed 's/Dict//g' | sed 's/.m4//g'`
                echo "<option value=\"$MESH_CMD\" />"
            fi
        done

        for MESH_FILE in $CASE_DIR/constant/*MeshDict
        do
            if [ -f $MESH_FILE ]; then
                MESH_CMD=`basename $MESH_FILE | sed 's/Dict//g'`
                echo "<option value=\"$MESH_CMD\" />"
            fi
        done
fi
echo "</field-control>"
