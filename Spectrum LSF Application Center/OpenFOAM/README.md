# OpenFOAM Template
OpenFOAM directory include all files required for integrating openfoam 6 with IBM Spectrum LSF and IBM Spectrum LSF Application Center.
This integration is based on a public docker image or buld your own OpenFOAM docker image, there is no need to install openfoam application. These are the benefits of building your own OpenFOAM docker image
 1) [Open MPI](https://www.open-mpi.org/)is compiled with LSF, which makes LSF Open MPI aware.
 2) Pstream is compiled
 3) MPI Hello World is added to the container for testing Open MPI
 4) The above improvements allow for running some OpenFOAM commands in parallel and potentially across nodes
 5) Ability to run OpenFOAM on IBM POWER processors
 
 The steps below describe how to build a custom OpenFOAM Docker image from the Dockerfile:
 
 [Building an OpenFOAM ready container for an LSF cluster](https://community.ibm.com/imwuc/blogs/john-welch/2020/02/12/building-an-openfoam-ready-container-for-lsf)

## Prerequisites
1). IBM Spectrum LSF 10.1 or above version is installed.

2). IBM Spectrum Application Center 10.2 or above version is installed.

3). LSF Compute Server support docker engine 1.12 or above version.

## Deployment Steps
Step 1: download all the files under this directory OpenFOAM/,   and copy over to IBM Spectrum LSF Application Center configuration 
        directory, for example:  /opt/ibm/lsfsuite/ext/gui/conf/application/draft/OpenFOAM, make sure files owner are administrator, 
        all files have excutable permission.
        
Step 2: Prepare IBM Spectrum LSF to run jobs in Docker container by following [LSF docker integration instruction]( https://www.ibm.com/support/knowledgecenter/en/SSWRJV_10.1.0/lsf_docker/lsf_docker_prepare.html). make sure the selected computer server have Docker engine installed  and enabled
        
Step 3: Configure LSF Docker Application profile for openfoam 6 by adding the following lines into end of lsb.applications:
        	
        Begin Application
        NAME         = openfoam
        DESCRIPTION  = Enables running jobs in docker container --openFoam
        CONTAINER = docker[image(openfoam/openfoam6-paraview54)  \
                    options(--rm --net=host --ipc=host --entrypoint=  \
		            --cap-add=SYS_PTRACE \
                            -v JOB_REPOSITORY_TOP:JOB_REPOSITORY_TOP \
	                    @JOB_REPOSITORY_TOP/dockerPasswd.sh  \
		     ) starter(root) ]
        EXEC_DRIVER = context[user(lsfadmin)] \
           starter[LSF_SERVERDIR/docker-starter.py] \
           controller[LSF_SERVERDIR/docker-control.py] \
           monitor[LSF_SERVERDIR/docker-monitor.py]
        End Application

 Notes: 
 
 1). If you built a custom OpenFOAM container, change above "openfoam/openfoam6-paraview54" to "openfoam/openfoam:v1912".
 
 2). Find a shared directory for all computer nodes, and replace JOB_REPOSITORY_TOP with the real path in above content 
 
 3). Change LSF_SERVERDIR to your LSF SERVERDIR direction location.
 
 4). Edit OpenFOAM/dockerPasswd.sh, replace the <JOB_REPOSITORY_TOP> with real value in the following line:
 
    JOBTMPDIR=<JOB_REPOSITORY_TOP>
 
 5). Copy dockerPasswd.sh to  JOB_REPOSITORY_TOP/dockerPasswd.sh
	
 for more details, reference [LSF docker application configuration](https://www.ibm.com/support/knowledgecenter/en/SSWRJV_10.1.0/lsf_docker/lsf_docker_config.html). 

 6). Restart the LSF mbatchd on the LSF Master by running either badmin mbdrestart or badmin reconfig. Then, verify a job submission with the OpenFOAM container is working. For example,

    $  bsub -Is -app openfoam ls /opt/
    Job <2742> is submitted to default queue <interactive>.
    <<Waiting for dispatch ...>>
    <<Starting on compute1>>
    OpenFOAM-v1912 ThirdParty-v1912 ibm
    $
    
Step 4: Copy the OpenFOAM tutorials out of a OpenFOAM container in to JOB_REPOSITORY_TOP directory.  Set OF_VER to either openfoam6 or OpenFOAM-v1912 depending on container image being used.   For example,

    $ OF_VER=openfoam6
    $ bsub -Is -app openfoam cp -pR /opt/$OF_VER/tutorials JOB_REPOSITORY_TOP

Step 5: User will need to be able to access the tutorials files from the previous step and one method would be to assign an appropriate group to the tutorials directory.   For example

    $ chgrp -R YourGroup JOB_REPOSITORY_TOP/tutorials

Step 6: Add the tutorials directory to /opt/ibm/lsfsuite/ext/gui/conf/Repository.xml file below the “</Repository>” line:

                <ShareDirectory>
                        <Alias>OpenFOAM tutorials</Alias>
                        <Path> JOB_REPOSITORY_TOP/tutorials</Path>
                </ShareDirectory>

Step 7:	Restart LSF Application Center

    # . /opt/ibm/lsfsuite/ext/profile.platform
    # pmcadmin stop
    # pmcadmin start
    # pmcadmin list

        
Step 8: Logon LSF Application Center as administrator,  find and publish template "OpenFOAM". Then  Go to "System&Setting"-> "User Role& Permission", assign view and Control permission of OpenFOAM to "Normal User".

Step 8: Submit OpenFOAM job from LSF Application Center as a normal user.  Check the job result with 3D graphic.
