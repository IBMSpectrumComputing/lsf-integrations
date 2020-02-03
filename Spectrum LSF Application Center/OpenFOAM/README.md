# OpenFOAM Template
OpenFOAM directory include all files required for integrating openfoam 6 with IBM Spectrum LSF and IBM Spectrum LSF Application Center.
This integration is based on a public docker image or buld your own OpenFOAM docker image, there is no need to install openfoam application. These are the benefits of building your own OpenFOAM docker image
 1) OpenMPI is compiled with LSF.  This makes LSF OpenMPI aware.
 2) Pstream is compiled
 3) MPI Hello World is added to the container for testing OpenMPI
 4) The above improvements allow for running some OpenFOAM commands in parallel and potentially across nodes
 5) Ability to run OpenFOAM on POWER processors
 
 Note, the steps below do not describe how to build a Docker image from the Dockerfile included.  However, this article describes the overall steps albeit for a non-OpenFOAM container image: 
 
 [Running TensorFlow benchmark with Horovod across IBM Power servers in containers in an LSF cluster](https://community.ibm.com/community/user/imwuc/blogs/john-welch/2019/12/20/running-tensorflow-benchmark-with-horovod-across-i)

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
                            -v /opt/ibm:/opt/ibm \
	                    @JOB_REPOSITORY_TOP/dockerPasswd.sh  \
                  ) starter(root) ]
        End Application


 Notes: 
 
 1).find a shared directory for all computer nodes, and replace JOB_REPOSITORY_TOP with the real path in above content       
 
 2).edit OpenFOAM/dockerPasswd.sh, replace the <JOB_REPOSITORY_TOP> with real value in the following line:
 
    JOBTMPDIR=<JOB_REPOSITORY_TOP>
 
 3).copy dockerPasswd.sh to  JOB_REPOSITORY_TOP/dockerPasswd.sh
	
 for more details, reference [LSF docker application configuration](https://www.ibm.com/support/knowledgecenter/en/SSWRJV_10.1.0/lsf_docker/lsf_docker_config.html). 
 
 4). assume LSF is installed under /opt/ibm,  if it is not, replace "/opt/ibm" in above openfoam application profile to the real
 LSF top directory.
        
Step 4: restart LSF:   
        
	lsfrestart
        
Step 5: logon LSF Application Center as administrator,  find and publish template "OpenFOAM". Then  Go to "System&Setting"-> "User Role& Permission", assign view and Control permission of OpenFOAM to "Normal User".

Step 6: Submit OpenFOAM job from LSF Application Center as a normal user.  check the job result with 3D graphic.
