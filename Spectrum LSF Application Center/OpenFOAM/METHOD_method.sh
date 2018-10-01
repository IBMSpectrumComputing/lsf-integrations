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

#this script control METHOD value based on file CASE_DIR/system/decomposeParDict from case directory selection

if [ x$CASE_DIR = x -o ! -d $CASE_DIR -o ! -d $CASE_DIR/system -o ! -f $CASE_DIR/system/decomposeParDict ];then
        echo "<field-control visible=\"false\" type=\"default\">"
        echo "<option value=\"simple\" /> "

else
        P_FILE="$CASE_DIR/system/decomposeParDict" 
	METHOD_CMD=`cat $P_FILE | grep "^method" | awk '{if ($1=="method") print $2}' | sed 's/;//g'`
        echo "<field-control visible=\"true\" type=\"default\">"
        echo "<option value=\"$METHOD_CMD\" />"
fi
echo "</field-control>"
