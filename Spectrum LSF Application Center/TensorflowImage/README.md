# Tensorflow Image Submission Templates
TensorflowImage folder includes the submission templates and scripts to run several Tensorflow Image Tutorials with IBM Spectrum LSF and 
IBM Spectrum LSF Application Center.  This integration is based on the public docker image: tensorflow/tensorflow:1.10.0, ibmcom/tensorflow-ppc64le:1.13.1,
there is no need to install Tensorflow.

## Background
1). Tensorflow Tutorials information is available here:

[Image Recognition]( https://www.tensorflow.org/tutorials/image_recognition)

[Flower Image Retraining]( https://www.tensorflow.org/tutorials/image_retraining)

2). Here is a short demonstration of the [LSF Application Center and the Tensorflow examples]( https://www.youtube.com/watch?v=wxeiPBEItJ4&feature=youtu.be)
  
## Prerequisites
1). IBM Spectrum LSF 10.1 or above version is installed.

2). IBM Spectrum Application Center 10.2 or above version is installed.

3). LSF Compute Server support docker engine 1.12 or above version.

## Assumptions
1). You are familiar with using and administrating LSF and LSF Application Center

2). All computes nodes have access to a shared file system to act as the MLDL_TOP directory
   for scripts, images and model files.  Change MLDL_TOP to the appropriate shared directory
   in your environment.

3). Docker is installed and working on LSF compute nodes

4). You want to learn about Tensorflow Tutorials and use Tensorflow with LSF

5). The docker tensorflow container specified in this readme uses only CPU although the "-gpu" tag can be added to Tensorflow docker image.

6). Scripts were tested on Tensorflow 1.10.0 and tensorflow-ppc64le 1.13.1. Results may vary on newer or older version of Tensorflow

## Shared Directory Structure

       MLDL_TOP/imagenet
       MLDL_TOP/images
       MLDL_TOP/retrain/bottleneck
       MLDL_TOP/scripts
       MLDL_TOP/submission_templates/*/

## Setting up LSF with Docker

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

1). Change the MLDL_TOP value in the submission template *.cmd files

    cd MLDL_TOP/submission_templates
    sed -i -e 's/\#MLDL_TOP\#/\/opt\/share\/mldl/g' */*.cmd

Note, /opt/share/mldl is an example and you can change to an appropriate shared directory structure in your environment.

2). Copy the submission template directories to /opt/ibm/lsfsuite/ext/gui/conf/application/draft

3). Using the LSF Application Center to publish the submission templates

### Download Tensorflow Tutorial files

4). Download these Tensorflow Tutorial files:

    cd MLDL_TOP/scripts
    wget https://raw.githubusercontent.com/tensorflow/models/master/tutorials/image/imagenet/classify_image.py
    wget https://raw.githubusercontent.com/tensorflow/tensorflow/r1.3/tensorflow/examples/image_retraining/label_image.py
    wget https://raw.githubusercontent.com/tensorflow/tensorflow/r1.7/tensorflow/examples/image_retraining/retrain.py
    wget https://raw.githubusercontent.com/normanheckscher/mnist-tensorboard-embeddings/master/mnist_with_summaries.py

5). Download the flower_photos used in the retrain.py script

    cd MLDL_TOP/images
    wget http://download.tensorflow.org/example_images/flower_photos.tgz
    tar xzf flower_photos.tgz

Change ownership of the flower_photos directory and subdirectory to give appropriate users read access. For example,

       chmod -R a+r+x flower_photos

6). Download the Inception 2015-12-05

    cd MLDL_TOP/imagenet
    wget http://download.tensorflow.org/models/image/imagenet/inception-2015-12-05.tgz
    tar xvzf inception-2015-12-05.tgz

Change ownership of the imagenet directory and files to give appropriate users read access.


### Tensorflow Tutorial python script changes (steps 7 to 10)

For steps 7 to 10, you can use the patch command to apply the differences instead of manually applying changes.
You might need to install patch command:

        # yum install patch

Then, run these commands:

  Notes:
  
  a). Change MLDL_TOP to the appropriate shared directory structure in your environment.  /opt/share/mldl is an example.
  
  b). Pull the scripts down with wget command before running these commands:

    cd MLDL_TOP/scripts

    for SCRIPT in classify_image.py label_image.py retrain.py mnist_with_summaries.py
    do
      mv $SCRIPT $SCRIPT.orig
      patch $SCRIPT.orig -i $SCRIPT.patch -o $SCRIPT
      chmod +rx $SCRIPT
      sed -i -e 's/\#MLDL_TOP\#/\/opt\/share\/mldl/g' $SCRIPT
    done

7). classify_image.py changes are noted in classify_image.py.patch file

8). label_image.py changes are noted in label_image.py.patch file
 
   The output_graph.pb and output_labels.txt are generated by the retrain.py script. Copy output_graph.pb and output_labels.txt to the MLDL_TOP/imagenet and make these 2 files readable by appropriate users. For example
      
      cd MLDL_TOP/imagenet
      chmod +r output_graph.pb output_labels.txt

9). retrain.py changes are noted in retrain.py.patch file
   
 The first successful run of the retrain.py script will take longer because the bottleneck files are generated.  Future runs will take less time assuming bottleneck files are stored in shared location and appropriate users have full permission access.

10). mnist_with_summaries.py changes are noted in mnist_with_summaries.py.patch file

### Miscellaneous tasks and thoughts

11). Download images for the Classify_Directory_Of_Images submission template
   
   a). Download 20 or more *.jpg files for classification and place the image under MLDL_TOP/images
       InceptionV3 model knows 1000 differnt object types. So, best to download pictures of objects that InceptionV3 model knows.
   
   b). Set the image directory in the Classify_Directory_Of_Images submission template.  In LSF Application Center, 
   
    Unpublish the template
    Edit the template by changing #MLDL_IMAGE_DIR# to your specific MLDL_TOP/images
    Save the template
    Publish the template
    
12). netstat is not currently in the Docker Tensorflow Containers and is used in tensorboard.sh script to fine a free port.
    A quick workaround copy /bin/netstat to MLDL_TOP/scripts and make sure MLDL_TOP/scripts/netstat is executable (chmod +r netstat).  So, MLDL scripts calling netstat in the container
    will call the netstat under MLDL_TOP/scripts.

13). Each Retrain or MNIST training job can generate several 100s MB of data under the logs directory.  Clean up as necessary.

14). Future changes to *.py scripts in from their original github location might cause deployment problems.

### Supporting IBM Power AI 1.6 container

When using the the container image docker.io/ibmcom/powerai:1.6.0-all-ubuntu18.04, change the location of python executable in the Python script files (scripts/*.py) to point from #!/usr/bin/pyton to #!/opt/anaconda2/bin/python.   Add a new application profile called powerai at the end of lsb.applcations.  For example,

        Begin Application
        NAME         = powerai
        DESCRIPTION  = Example Power AI 1.6
        CONTAINER = docker[image(docker.io/ibmcom/powerai:1.6.0-all-ubuntu18.04)  \
                    options(--rm --net=host --ipc=host --env ACTIVATE=base --env LICENSE=yes \
                            -v MLDL_TOP:MLDL_TOP \
                            -v /opt/ibm:/opt/ibm \
	                    @MLDL_TOP/scripts/dockerPasswd.sh  \
                  ) starter(root) ]
	EXEC_DRIVER: 
	    context[user(lsfadmin)]
	    starter[$LSF_SERVERDIR/docker-starter.py]
	    controller[$LSF_SERVERDIR/docker-control.py]
	    monitor[$LSF_SERVERDIR/docker-monitor.py]
        End Application

 In the above powerai application profile change: 
 
 a). MLDL_TOP to the share directory location in your environment
 
 b). $LSF_SERVERDIR to your environmental value.  For example, /opt/ibm/lsfsuite/lsf/10.1/linux3.10-glibc2.17-ppc64le/etc
 
 Next change the APP_PROFILE value in the *.cmd files provided
 
 	#APP_PROFILE=docker_tensorflow
	APP_PROFILE=powerai
  
