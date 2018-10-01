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
