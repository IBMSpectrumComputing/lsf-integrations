# The TensorFlow plug-in
TensorFlow is an open source library to help develop and train machine learning models. The TensorFlow interactions with IBM Spectrum Computing Suite for High Performance Analytics uses Application Center which will leverage the underlying LSF cluster capabilities.

TensorflowImage folder includes the submission templates and scripts to run several Tensorflow Image Tutorials with IBM Spectrum LSF and 
IBM Spectrum LSF Application Center.  This integration is based on the public docker image: tensorflow/tensorflow:1.10.0, ibmcom/tensorflow-ppc64le:1.13.1,

1) Tensorflow Tutorials information is available here:

[Image Recognition]( https://www.tensorflow.org/tutorials/image_recognition)

[Flower Image Retraining]( https://www.tensorflow.org/tutorials/image_retraining)

2) Here is a short demonstration of the [LSF Application Center and the Tensorflow examples]( https://www.youtube.com/watch?v=wxeiPBEItJ4&feature=youtu.be)

## Prerequisites
1) LSF is installed.

2) IBM Spectrum Application Center 10.2 or above version is installed.

3) Docker is installed and working on LSF compute nodes.

4) Prepare IBM Spectrum LSF to run jobs in Docker container by following [LSF docker integration instruction]( https://www.ibm.com/support/knowledgecenter/en/SSWRJV_10.1.0/lsf_docker/lsf_docker_prepare.html). Make sure the selected compute servers have Docker engine installed and enabled
        
5) All computes nodes have access to a shared directory (MLDL_TOP) in which to store TensorFlow scripts, images and model files, accessible by compute nodes.

    MLDL_TOP Shared Directory Structure

       MLDL_TOP/imagenet
       MLDL_TOP/images
       MLDL_TOP/retrain/bottleneck
       MLDL_TOP/scripts
       MLDL_TOP/submission_templates

## Deployment Steps

Download the TensorFlow plugin files and make minor changes

1) Find a shared directory (MLDL_TOP) for the TensorFlow plugin files
   
   For example,
   
     mkdir -p  /path/to/MLDL_TOP/imagenet
     mkdir -p  /path/to/MLDL_TOP/images
     mkdir -p  /path/to/MLDL_TOP/retrain/bottleneck
     mkdir -p  /path/to/MLDL_TOP/scripts
     mkdir -p  /path/to/MLDL_TOP/submission_templates
   
2) Copy the TensorFlow plugin files to the corresponding MLDL_TOP sub-directories.

3) Change the ownership of files to LSF Primary administrator

   For example,
   
       chown -R lsfadmin /path/to/MLDL_TOP

5) Make the all files readable and executable by all

   For example,

       chmod -R a+rx /path/to/MLDL_TOP/*
   
            
6) Source the LSF and Application Center environment:
For LSF:

    For csh or tcsh: %source <LSF_TOP>/conf/cshrc.lsf
    For sh, ksh, or bash: $ . <LSF_TOP>/conf/profile.lsf

For Application Center:

    For csh or tcsh: % source <PMC_TOP>/gui/conf/cshrc.pmc
    For sh, ksh, or bash: $ . <PMC_TOP>/gui/conf/profile.pmc


7) Execute the config_tensorflow.sh script as LSF primary administrator

   For example,

     export MLDL_TOP=/path/to/MLDL_TOP
     cd /path/to/MLDL_TOP 
     ./config_tensorflow.sh

8) Restart LSF daemons on the LSF Master and Master Candidate hosts

9) Verify job submission with a docker container is working.  For example,

        $  bsub -Is -app docker_tensorflow /bin/bash
        Job <2742> is submitted to default queue <interactive>.
        <<Waiting for dispatch ...>>
        <<Starting on compute1>>
        $ hostname
        compute1
        $ exit
        $

  Before exiting from the above interactive job, run "docker ps -a" on compute1 to verify a docker container is running tensorflow.


## Verify job submission with the TensorFlow plugin is working

Refer to [Using the TensorFlow plug-in in LSF](https://www.ibm.com/docs/en/scsfhpa/10.2.0?topic=in-using-tensorflow-plug)
