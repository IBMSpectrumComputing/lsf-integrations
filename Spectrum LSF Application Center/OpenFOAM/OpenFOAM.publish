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
#  this script processes OpenFOAM template post-publish tasks

if [ -z "$OF_VER" ]; then
    echo "OF_VER is not specified. Exiting."
    exit 1
fi

if [ -z "$JOB_REPOSITORY_TOP" ]; then
    echo "JOB_REPOSITORY_TOP is not specified. Exiting."
    exit 1
fi

if [ ! -d "$JOB_REPOSITORY_TOP" ]; then
    echo "JOB_REPOSITORY_TOP does not exit. Exiting."
    exit 1
fi

if [ ! -w "$JOB_REPOSITORY_TOP" ]; then
    echo "JOB_REPOSITORY_TOP needs to be writeable by $USER. Exiting."
    exit 1
fi

TEMPLATE_PATH=`dirname $0`

if [ ! -d "$JOB_REPOSITORY_TOP/scripts" ]; then
    mkdir $JOB_REPOSITORY_TOP/scripts
fi
cp -f $TEMPLATE_PATH/dockerPasswd.sh $JOB_REPOSITORY_TOP/scripts/
chmod a+x $JOB_REPOSITORY_TOP/scripts/dockerPasswd.sh
sed -i "s|#JOB_REPOSITORY_TOP#|$JOB_REPOSITORY_TOP|g" $JOB_REPOSITORY_TOP/scripts/dockerPasswd.sh

if [ "$OF_VER" == "openfoam6" ]; then
    OF_CONTAINER="openfoam/openfoam6-paraview54"
    OF_ENTRYPOINT="--entrypoint="
else # assume using custom built docker container.  See https://community.ibm.com/community/user/imwuc/blogs/john-welch/2020/02/12/building-an-openfoam-ready-container-for-lsf
    OF_CONTAINER="openfoam/openfoam:v1912"
    OF_ENTRYPOINT=""
fi

#configure lsb.applications to add openfoam
export LSF_CLUSTER_NAME=`lsid |grep "My cluster name" | cut -d" " -f5`
export LSB_APPLICATION_FILE=$LSF_ENVDIR/lsbatch/$LSF_CLUSTER_NAME/configdir/lsb.applications
checkOpenFOAM=`cat $LSB_APPLICATION_FILE | awk '{if($1=="NAME" && $2=="=" && $3=="openfoam") print "FOUND" }'`
if [ x"$checkOpenFOAM" = "xFOUND" ]; then
     echo "openfoam has already been configured in lsb.applications."
else
cat << EOF >> $LSB_APPLICATION_FILE

Begin Application
NAME         = openfoam
DESCRIPTION  = Enables running jobs in docker container openFoam 
CONTAINER = docker[image($OF_CONTAINER) \\
                options(--rm --net=host --ipc=host $OF_ENTRYPOINT \\
                        --cap-add=SYS_PTRACE \\
                        -v $JOB_REPOSITORY_TOP:$JOB_REPOSITORY_TOP \\
                        @$JOB_REPOSITORY_TOP/scripts/dockerPasswd.sh \\
              ) ]
EXEC_DRIVER = context[user($USER)] \\
    starter[$LSF_SERVERDIR/docker-starter.py] \\
    controller[$LSF_SERVERDIR/docker-control.py] \\
    monitor[$LSF_SERVERDIR/docker-monitor.py]
End Application

EOF

    echo "docker openfoam configuration has been added to lsb.applications. need to restart mbatchd to enable it"
    #badmin mbdrestart -f

    #sleep 15 # wait for mbatchd restart
    # Copy the tutorials
    #bsub -I -app openfoam cp -pR /opt/$OF_VER/tutorials $JOB_REPOSITORY_TOP/
fi

REPOSITORY_XML="/opt/ibm/lsfsuite/ext/gui/conf/Repository.xml"
#REPOSITORY_XML=repo
# add tutorials share directory to Repository.xml file
if [ -w "$REPOSITORY_XML" ]; then
     checkTutorial=`grep $JOB_REPOSITORY_TOP/tutorials $REPOSITORY_XML`
     rtrn=$?
     if [ "$rtrn" == "0" ]; then # 0 = Found
          echo "tutorials has already been configured in $REPOSITORY_XML."
     else
         update_text="\n\t\t<ShareDirectory>\n\t\t\t<Alias>OpenFOAM tutorials</Alias>\n\t\t\t<Path>$JOB_REPOSITORY_TOP/tutorials</Path>\n\t\t</ShareDirectory>"
         sed -i "s|</Repository>|</Repository>$update_text|g" $REPOSITORY_XML
         echo "Tutorials Share Directory added to $REPOSITORY_XML file. You must stop and start pmcadmin."
    fi
fi

echo "Post publishing is done."
