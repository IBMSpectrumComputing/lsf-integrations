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
