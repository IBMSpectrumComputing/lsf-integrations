# Miscellaneous Machine/Deep Learning Submission Templates
Misc_MLDL_Examples folder includes the submission templates and scripts to run several Machine or Deep Learning examples with IBM Spectrum LSF and 
IBM Spectrum LSF Application Center.  This integration assumes PowerAI 1.6 is installed on your LSF compute nodes.  However, with some
extra effort these examples can be setup to run inside of publicly available docker images.

## Background
Here is a short demonstration of the [LSF Application Center with Tensorflow examples]( https://www.youtube.com/watch?v=wxeiPBEItJ4&feature=youtu.be)
  
## Prerequisites
1). IBM Spectrum LSF 10.1 or above version is installed.  It is recommened to apply the latest LSF Service Pack.

2). IBM Spectrum Application Center 10.2 or above version is installed.

3). PowerAI 1.6 is installed on your LSF compute nodes.  If not using Power, LSF compute nodes support docker engine 1.12 or above version.

4) NVIDIA CUDA is installed on your LSF Compute nodes.

5) To use Docker and CUDA togethre install Nvidia-docker 2.0 on your LSF compute nodes.  See this article [Using nvidia-docker 2.0 with RHEL 7] ( https://developer.ibm.com/linuxonpower/2018/09/19/using-nvidia-docker-2-0-rhel-7/)

## Assumptions
1). You are familiar with using and administrating LSF and LSF Application Center

2). All computes nodes have access to a shared file system to act as the MLDL_TOP directory
   for scripts, images and model files.  Change MLDL_TOP to the appropriate shared directory
   in your environment.

3). If not using Power, Docker is installed and working on LSF compute nodes

4). You want to learn about MLDL and use MLDL with LSF

5). Scripts were tested on PowerAI 1.6. Results may vary on newer or older version of the related MLDL framework

## Shared Directory Structure

       MLDL_TOP/data
       MLDL_TOP/scripts
       MLDL_TOP/submission_templates/*/

## Setting up LSF with Docker (only required if not using PowerAI)

1). Prepare IBM Spectrum LSF to run jobs in Docker container by following [LSF docker integration instruction]( https://www.ibm.com/support/knowledgecenter/en/SSWRJV_10.1.0/lsf_docker/lsf_docker_prepare.html). Make sure the selected compute servers have Docker engine installed and enabled
        
2). Configure LSF Docker Application profile for Tensorflow by adding the following lines into end of lsb.applications:
 
        Begin Application
        NAME         = docker_tensorflow
        DESCRIPTION  = Example Docker Tensorflow application
        CONTAINER = docker[image(tensorflow/tensorflow:1.10.0)  \
                    options(--rm --net=host --ipc=host  \
                            -v MLDL_TOP:MLDL_TOP \
                            -v /opt/ibm:/opt/ibm \
	                    @MLDL_TOP/scripts/dockerPasswd.sh  \
                  ) starter(root) ]
        End Application

 Change MLDL_TOP in the above application profile to the share directory location in your environment
 Notes: Change "image(tensorflow/tensorflow:1.10.0)" to "image(ibmcom/tensorflow-ppc64le:1.13.1)" if your environment is IBM Power Linux.

 Restart LSF daemons on the LSF Master and Master Candidate hosts
 Verify job submission with a docker container is working.  For example,

        $  bsub -Is -app docker_tensorflow /bin/bash
        Job <2742> is submitted to default queue <interactive>.
        <<Waiting for dispatch ...>>
        <<Starting on compute1>>
        $ hostname
        compute1
        $ exit
        $

  Before exiting from the above interactive job, run "docker ps -a" on compute1 to verify a docker container is running tensorflow.

## Deployment Steps

### Setup the Submission Templates

1). Change the MLDL_TOP value in the submission template files

    cd MLDL_TOP/submission_templates
    sed -i -e 's/\#MLDL_TOP\#/\/opt\/share\/mldl/g' */*

Note, /opt/share/mldl is an example and you can change to an appropriate shared directory structure in your environment.

2). Copy the submission template directories to /opt/ibm/lsfsuite/ext/gui/conf/application/draft

3). Using the LSF Application Center to publish the submission templates

### Download Example files and make minor changes

4). Download these examples python scripts:

    cd MLDL_TOP/scripts
    wget https://raw.githubusercontent.com/pytorch/pytorch/master/caffe2/python/examples/char_rnn.py
    wget https://raw.githubusercontent.com/pytorch/examples/master/mnist/main.py
    
    Optionally, these scripts are also available with PowerAI under
    
        /opt/anaconda2/caffe2/examples/char_rnn.py
        /opt/anaconda2/pytorch/examples/mnist/main.py
             
5). Make the python scripts readable and executable by all

    chmod +rx *.py

6). Add this line below as the first line to each of the above python scripts (char_rnn.py and main.py)

For PowerAI

    #!/opt/anaconda2/bin/python

Alternatively

    #!/usr/bin/python

7). Additional changes to main.py script

From

    datasets.MNIST('../data', train=True, download=True,
    datasets.MNIST('../data', train=False, transform=transforms.Compose([

To

    datasets.MNIST('./data', train=True, download=True,
    datasets.MNIST('./data', train=False, transform=transforms.Compose([


8). Download the data file

    cd MLDL_TOP/data
    https://raw.githubusercontent.com/hzy46/Char-RNN-TensorFlow/master/data/shakespeare.txt
   
    Optionally, a smaller version of the data file is available with PowerAI under
    
        /opt/anaconda2/caffe2/examples/shakespeare.txt

9). Make the file readable by all

    chmod +r shakespeare.txt
        
### Miscellaneous tasks and thoughts

10). Future changes to *.py scripts from their original github location might cause deployment problems.
