#!/bin/bash
#**************************************************************************
#  Copyright International Business Machines Corp, 2019. 
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
#
# The script to stop ipython controller and engines, invoked by hpa-ipython.

# Stop ipcontoller and engines
PIDs=$(ps -ef |grep -E "python.*ipcontroller.*${IPYTHON_PROFILE}|python.*ipyparallel.engine.*${IPYTHON_PROFILE}|python.*ipcluster engines.*${IPYTHON_PROFILE}" |grep -v "grep"|awk '{print $2}' |tr "\n" " ")
kill ${PIDs} > /dev/null 2>&1
echo "Stopping ipython cluster on $HOSTNAME ..."