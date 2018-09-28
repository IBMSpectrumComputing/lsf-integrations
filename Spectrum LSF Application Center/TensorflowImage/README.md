# Tensorflow Image Submission Templates
TensorflowImage folder includes the submission templates and scripts to run several Tensorflow Image Tutorials with IBM Spectrum LSF and 
IBM Spectrum LSF Application Center.  This integration is based on a public docker image: tensorflow/tensorflow:1.10.0, 
there is no need to install Tensorflow.

## Background
1). Tensorflow Tutorials information is availabe here:

[Image Recognition]( https://www.tensorflow.org/tutorials/image_recognition)

[Flower Image Retraining]( https://www.tensorflow.org/tutorials/image_retraining)

2). Here is a short demonstration of the [LSF Application Center submiting the Tensorflow examples]( https://www.youtube.com/watch?v=wxeiPBEItJ4&feature=youtu.be)
  
## Prerequisites
1). IBM Spectrum LSF 10.1 or above version is installed.

2). IBM Spectrum Application Center 10.2 or above version is installed.

3). LSF Compute Server support docker engine 1.12 or above version.

## Assumptions
a) You are familiar with using and administrating LSF and LSF Application Center
b) All computes nodes have access to a shared file system to act as the MLDL_TOP directory
   for scripts, images and model files.  Change MLDL_TOP to the appropriate shared directory
   in your environment.
c) Docker is installed and working on LSF compute nodes
d) You want learn about Tensorflow Tutorials and use Tensorflow with LSF
e) The docker tensorflow container specified in this readme uses CPU and not GPU
f) Some effort may be needed to get the Tensorflow python scripts to run on GPUs
g) Scripts were tested on Tensorflow 1.10.0.  Results may vary on newer or older version of Tensorflow

## Shared Directory Structure

MLDL_TOP/imagenet
MLDL_TOP/images
MLDL_TOP/retrain/bottleneck
MLDL_TOP/scripts
MLDL_TOP/submission_templates/*/

## Setting up LSF with Docker

Step 1: Prepare IBM Spectrum LSF to run jobs in Docker container by following [LSF docker integration instruction]( https://www.ibm.com/support/knowledgecenter/en/SSWRJV_10.1.0/lsf_docker/lsf_docker_prepare.html). Make sure the selected computer server have Docker engine installed and enabled
        
Step 2: Configure LSF Docker Application profile for Tensorflow by adding the following lines into end of lsb.applications:
 
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

 Change MLDL_TOP in the above application profile to the actuall share directory location in your environment

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

## Setup the Submission Templates

Step 1) Change the MLDL_TOP value in the submission template *.cmd files

    sed -i -e 's/\#MLDL_TOP\#/\/opt\/share\/mldl/g' submission_templates/*/*.cmd

Note, /opt/share/mldl is an example and you can change to an appropriate shared directory structure in your environment.

Step 2) Copy the submission template directories to PAC_TOP/gui/conf/application/draft.  Typically, PAC_TOP is /opt/ibm/lsfsuite/ext

Step 3) Using the LSF Application Center to publish the submission templates

## Download Tensorflow Tutorial files

5) Download these Tensorflow Tutorial files:

wget https://raw.githubusercontent.com/tensorflow/models/master/tutorials/image/imagenet/classify_image.py
wget https://raw.githubusercontent.com/tensorflow/tensorflow/r1.3/tensorflow/examples/image_retraining/label_image.py
wget https://raw.githubusercontent.com/tensorflow/tensorflow/r1.7/tensorflow/examples/image_retraining/retrain.py
wget https://raw.githubusercontent.com/normanheckscher/mnist-tensorboard-embeddings/master/mnist_with_summaries.py

   a) place the Tensorflow Tutorial script files into your MLDL_TOP/scripts directory

6) Download the flower_photos used in the retrain.py script

cd MLDL_TOP/images
wget http://download.tensorflow.org/example_images/flower_photos.tgz
tar xzf flower_photos.tgz
change ownership of the flower_photos directory and subdirectory to give appropriate users read access. For example,
 chmod -R a+r+x flower_photos

7) Download the Inception 2015-12-05

cd MLDL_TOP/imagenet
wget http://download.tensorflow.org/models/image/imagenet/inception-2015-12-05.tgz
tar xvzf inception-2015-12-05.tgz
change ownership of the imagenet directory and files to give appropriate users read access.


Tensorflow Tutorial python script changes (steps 8 to 11)

For steps 8 to 11, you can use the patch command to apply the differences instead of manually applying changes.
You might need to install patch command:

        # yum install patch

Then, run these commands:

  Notes:
  a) Change MLDL_TOP to the appropriate shared directory structure in your environment.  /opt/share/mldl is an example.
  b) pull the scripts down with wget command before running these commands:

  cd MLDL_TOP/scripts

  for SCRIPT in classify_image.py label_image.py retrain.py mnist_with_summaries.py
  do
      mv $SCRIPT $SCRIPT.orig
      patch $SCRIPT.orig -i $SCRIPT.patch -o $SCRIPT
      chmod +rx $SCRIPT
      sed -i -e 's/\#MLDL_TOP\#/\/opt\/share\/mldl/g' $SCRIPT
  done

8) classify_image.py
   a) changes are noted in classify_image.py.patch file

9) label_image.py
   a) changes are noted in label_image.py.patch file
   b) the output_graph.pb and output_labels.txt are generated by the retrain.py script. Copy
      output_graph.pb and output_labels.txt to the MLDL_TOP/imagenet and make these 2 files readable by all
      (for example, chmod +r output_graph.pb output_labels.txt).

10) retrain.py
   a) changes are noted in retrain.py.patch file
   b) The first successful run of the retrain.py script will take longer
      because the bottleneck files are generated.  Future runs will take less time
      assuming bottleneck files are stored in shared location and all users have
      full permission access.

11) mnist_with_summaries.py
   a) changes are noted in mnist_with_summaries.py.patch file

Miscellaneous thoughts or tasks

12) Download images for the Classify_Directory_Of_Images submission template
    a) download 20 or more *.jpg files for classification and place the image under MLDL_TOP/images
       InceptionV3 model knows 1000 differnt object types. So, best to download pictures of objects that InceptionV3 model knows.
    b) Set the image directory in the Classify_Directory_Of_Images submission template files.  Here is example on how to change
       value of MLDL_IMAGE_DIR to /opt/share/mldl/images:

       sed -i -e 's/\#MLDL_IMAGE_DIR\#/\/opt\/share\/mldl\/images/g' submission_templates/Classify_Directory_Of_Images/*

13) netstat is not currently in the Docker Tensorflow Containers and is used in tensorboard.sh script to fine a free port.
    A quick workaround copy /bin/netstat to MLDL_TOP/scripts.  So, MLDL scripts calling netstat in the container
    will call the netstat under MLDL_TOP/scripts.

14) Each Retrain or MNIST training job can generate several 100s MB of data under the logs directory.  Clean up as necessary.

15) Future changes to *.py scripts in github might cause problems.
