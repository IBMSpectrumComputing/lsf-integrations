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

#this script control ALLRUN value based on file CASE_DIR/Allrun exists

if  [ -z "$CASE_DIR" ] || [ ! -d $CASE_DIR -o ! -d $CASE_DIR/system ];then
        echo "<field-control visible=\"false\" >"
        echo "<option value=\"no\" /> "
elif [ -f $CASE_DIR/Allrun ]; then
        echo "<field-control visible=\"true\" >"
        echo "<option value=\"yes\" />"
else
        echo "<field-control visible=\"false\" >"
        echo "<option value=\"no\" /> "
fi
echo "</field-control>"
