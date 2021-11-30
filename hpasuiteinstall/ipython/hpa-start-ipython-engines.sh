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
# The script of to start ipython engines, invoked by hpa-start-ipcluster.sh.
# Why separete this script with hpa-start-ipcluster.sh? because bugs: if the engines was exist, the bsub jobs will be exist before other task finished.

# Get the value of NUM_ENGINES and IPYTHON_PROFILE
NUM_ENGINES=$1
IPYTHON_PROFILE=$2
#start engines on the hosts 
ipcluster engines --n=${NUM_ENGINES} --profile=${IPYTHON_PROFILE}