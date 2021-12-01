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

# The installation script of tensorflow, to run tensorflow jobs in PAC

#-------------------------------------------------------------------
# Name: update_lsb_applications
# Synopsis: update_lsb_applications $lsb_applications_file
# Description:
#    Add docker_tensorflow application to lsb.applications;
# Return:
#    0 on success, 1 on error.
#------------------------------------------------------------------
update_lsb_applications ()
{
_lsb_applications_file="$1"

#Backup lsb_applications file
cp ${_lsb_applications_file} ${_lsb_applications_file}.original

#
# Add docker_tensorflow to the file lsb.applications
#
echo "Enabling docker_tensorflow application in ${_lsb_applications_file} ..."
egrep "^[       ]*NAME[       ]*=[       ]*docker_tensorflow" ${_lsb_applications_file} > /dev/null 2>&1
if [ "$?" = "0" ]; then
    echo "docker_tensorflow has been enabled."
else
    cat >> $_lsb_applications_file <<EOF
Begin Application
NAME         = docker_tensorflow
DESCRIPTION  = Example Docker Tensorflow application
CONTAINER = docker[image(tensorflow/tensorflow:1.10.0)  \
options(--rm --net=host --ipc=host  \
-v MLDL_TOP:MLDL_TOP \
-v /opt/ibm:/opt/ibm \
${MLDL_TOP}/scripts/dockerPasswd.sh  \
) starter(root) ]
End Application
EOF
fi
return 0

} # update_lsb_applications


#------------------------------------------------------------------
#  Name: get_clusters_name
#
#  Synopsis: get_clusters_name $LSF_SHARED
#
#  Environment Variable: LSF_CONFDIR
#
#  Description:
#       This function queries lsf.shared file and identifies all clusters.
#       It is different from the next function
#  Return Values:
#     0: get cluster and all custer names; otherwise, 1
#------------------------------------------------------------------
get_clusters_name ()
{
_lsf_shared="$1"

if [ ! -r "${_lsf_shared}" ]; then
    error_case_awsrc 4 "${_lsf_shared}"
fi

# get all the cluster names in CLUSTERNAME section of lsf.shared
# by 1) deleting line 1 to the line that contains Begin CLuster"
#    2) getting rid of cluster name
#    3) getting rid of all comment lines
#    4) getting rid of the line containing end cluster to the end of the file.
first_line=`head -n 1 $_lsf_shared`
echo $first_line | grep '^[     ]*[Bb][Ee][Gg][Ii][Nn][         ]*[Cc][Ll][Uu][Ss][Tt][Ee][Rr]' > /dev/null 2>&1
if [ "$?" = "0" ] ; then
    _lsf_clusters=`sed -e "1,1d" -e "/^[        ]*[Ee][Nn][Dd][         ]*[Cc][Ll][Uu][Ss][Tt][Ee][Rr]/,$ d" -e "/^[    ]*[Cc][Ll][Uu][Ss][Tt][Ee][Rr][Nn][Aa][Mm][Ee][         ]*.*/d" -e "/^[         ]*#.*/d" -e "s/^[       ]*//" -e "s/[   ]*$//" $_lsf_shared | awk '{ print $1 }'`
else
    _lsf_clusters=`sed -e "1,/^[        ]*[Bb][Ee][Gg][Ii][Nn][         ]*[Cc][Ll][Uu][Ss][Tt][Ee][Rr]/d" -e "/^[       ]*[Ee][Nn][Dd][         ]*[Cc][Ll][Uu][Ss][Tt][Ee][Rr]/,$ d" -e "/^[    ]*[Cc][Ll][Uu][Ss][Tt][Ee][Rr][Nn][Aa][Mm][Ee][         ]*.*/d" -e "/^[         ]*#.*/d" -e "s/^[       ]*//" -e "s/[   ]*$//" $_lsf_shared | awk '{ print $1 }'`
fi
_lsf_clusters=`echo $_lsf_clusters`
echo "$_lsf_clusters"
return 0
} # get_clusters_name


#------------------------------------------------------------------
#  Name: check_variables
#
#  Synopsis: check_variables 
#
#  Environment Variable: LSF_ENVDIR PMC_TOP MLDL_TOP
#
#  Description:
#       This function check whether LSF_ENVDIR PMC_TOP MLDL_TOP are available
#  Return Values:
#     0: check all variables pass; otherwise, 1
#------------------------------------------------------------------
check_variables ()
{

# LSF configuration, need to source LSF Profile firstly before running
if [ "x$LSF_ENVDIR" = "x" ];then
    echo "Cannot get the value of environment variable LSF_ENVDIR. \nSource the relative IBM Spectrum LSF shell script. \n * For csh or tcsh: 'source \$LSF_TOP/conf/cshrc.lsf' \n * For sh, ksh, or bash: 'source \$LSF_TOP/conf/profile.lsf'"
    exit 1
fi

# PMC configuration, need to source PMC Profile firstly before running
if [ "x$PMC_TOP" = "x" ];then
    echo "Cannot get the value of environment variable PMC_TOP. \nSource the relative IBM Spectrum Application Center profile. \n 'source \$PMC_TOP/gui/conf/profile.pmc'"
    exit 1
fi

# MLDL_TOP configuration, need to be defined before running this script
if [ "x$MLDL_TOP" = "x" ];then
    echo "Cannot get the value of environment variable MLDL_TOP \n"
    exit 1
elif [ ! -d "$MLDL_TOP" ] ; then
    mkdir -p $MLDL_TOP
fi

return 0
} # check_variables

#------------------------------------------------------------------
#  Name: get_variables
#
#  Synopsis: get_variables 
#
#
#  Description:
#       This function will get the variables this scripts needed
#  Return Values:
#     0: get all variables pass; otherwise, 1
#------------------------------------------------------------------
get_variables ()
{
LSF_CLUSTER_NAME=`get_clusters_name "$LSF_ENVDIR/lsf.shared"`
lsb_applications_file="$LSF_ENVDIR/lsbatch/$LSF_CLUSTER_NAME/configdir/lsb.applications"
if [ ! -f "$lsb_applications_file" ];then
    echo "Cannot find lsb.applications file: $lsb_applications_file\n"
    exit 1
fi
return 0
} # get_variables

#------------------------------------------------------------------
#  Name: setup_submission_templates
#
#  Synopsis: setup_submission_templates 
#
#
#  Description:
#       This function will setup for all the tensorflow templates into PAC
#  Return Values:
#     0: setup successfully; otherwise, 1
#------------------------------------------------------------------
setup_submission_templates ()
{
# Setup the Submission Templates
echo "Configure TensorFlow submission templates..."
pushd $MLDL_TOP/submission_templates >> /dev/null 2>&1
sed -i -e "s@\#MLDL_TOP\#@${MLDL_TOP}@g" */*.cmd
\cp -fr * $PMC_TOP/gui/conf/application/draft/
popd >> /dev/null 2>&1
return 0
} # setup_submission_templates

#------------------------------------------------------------------
#  Name: setup_python_files
#
#  Synopsis: setup_python_files 
#
#
#  Description:
#       This function will configure Tensorflow Tutorial python script
#  Return Values:
#     0: setup successfully; otherwise, 1
#------------------------------------------------------------------
setup_python_files ()
{
# Configure Tensorflow Tutorial python script
echo "Configure Tensorflow Tutorial python script..."
pushd $MLDL_TOP/scripts >> /dev/null 2>&1
for SCRIPT in classify_image.py label_image.py retrain.py mnist_with_summaries.py
do
  sed -i -e "s@\#MLDL_TOP\#@${MLDL_TOP}@g" $SCRIPT
done
popd >> /dev/null 2>&1
return 0
} # setup_python_files

#------------------------------------------------------------------
#  Name: reverse_config
#
#  Synopsis: reverse_config 
#  Description:
#       Reverse configuration for tensorflow 
#  Return Values:
#     0: reverse successfully; otherwise, 1
#------------------------------------------------------------------
function reverse_config()
{
    #Reverse lsb_applications file
    cp ${lsb_applications_file}.original ${lsb_applications_file}
    chown $LSF_PRIMARY_ADMIN ${lsb_applications_file}

    TEMPLATE_DIR=$PMC_TOP/gui/conf/application/draft
    rm -rf $TEMPLATE_DIR/Classify_Directory_Of_Images
    rm -rf $TEMPLATE_DIR/Classify_Image
    rm -rf $TEMPLATE_DIR/MNIST_Training
    rm -rf $TEMPLATE_DIR/Retrain_Model
    rm -rf $TEMPLATE_DIR/Tensorboard
}

#------------------------------------------------------------------
#  Name: main_config_tensorflow
#
#  Synopsis: main_config_tensorflow 
#  Description:
#       configure tensorflow 
#  Return Values:
#     0: configure tensorflow successfully; otherwise, 1
#------------------------------------------------------------------
main_config_tensorflow () {
    check_variables
    get_variables
    if [ "$1" == "-r" ]; then
        reverse_config
        return
    fi

    update_lsb_applications ${lsb_applications_file}
    setup_submission_templates
    setup_python_files
    echo "Finished the tensorflow configuration"
} # main_config_tensorflow

main_config_tensorflow $@