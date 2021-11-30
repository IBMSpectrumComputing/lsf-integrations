# The Dask plug-in
Dask is a library for parallel computing in Python. The Dask plugin provided in the Analytics Integration Kit provides a solution to run a Dask application across the LSF cluster.

 
## Prerequisites
1) LSF is installed.

2) Dask is installed on one or more LSF server hosts.
   Using anaconda distribution to install: https://www.anaconda.com/distribution/#download-section.
   
3) Ensure the Python and Dask command line can be executed successfully on every LSF server host intended to run Dask.

   For example:
   
   On the LSF server host enter the command python to test if Python is installed successfully.
   
   For Dask test both the scheduler and worker with the dask-scheduler and dask-worker commands
   
## Deployment Steps

Download the Dask plugin files and make minor changes

1) Find a top directory for the Dask plugin files
   
   For example,
   
     mkdir -p /opt/ibm/hpacomponent-dask
   
2) Copy the Dask plugin files to the top directory for the Dask plugin
             
3) Change the place holder (i.e, @DASK_HOME@) to the Dask installation top directory

   For example,
   
       sed -i "s|@DASK_HOME@|/opt/anaconda2|" *.sh

4) Change the ownership of files to LSF Primary administrator

   For example,
   
       chown -R lsfadmin /opt/ibm/hpacomponent-dask

5) Make the shell scripts readable and executable by all

    chmod a+rx *.sh
    

## Configure the Dask plug-in

Configure a static boolean resource in LSF to indicate which hosts have Dask installed.

For example, in $LSF_ENVDIR/lsf.shared:

    Begin Resource
    RESOURCENAME  TYPE    INTERVAL INCREASING  DESCRIPTION
     DaskHost Boolean  ()   ()       (Boolean resource to indicate Dask is installed)
    End Resource

Add the resource to the hosts that have Dask installed in your LSF cluster file under $LSF_ENVDIR/lsf.clsuter.<clustername>

For example:

     Begin   Host
     HOSTNAME  model    type        server  RESOURCES   
     host1  !        !        1    (mg)
     host2  !        !        1    (DaskHost)
     End     Host

Reconfigure LSF with the changes using the lsadmin reconfig command.

## Verify job submission with the Dask plugin is working
Refer to https://www.ibm.com/docs/en/scsfhpa/10.2.0?topic=in-using-dask-plug

