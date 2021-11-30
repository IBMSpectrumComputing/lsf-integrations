# The IPython plug-in
The IPython plug-in for LSF allows the IPython interactive computing environment to be launched across hosts spanning the LSF cluster. LSF will pick the best suited hosts to launch the IPython worker nodes in the cluster.

 
## Prerequisites
1) LSF is installed.

2) Python, IPython and IPython Parallel are installed on one or more LSF server host.

IPython can be installed with pip using the pip install ipython command. For details refer to the installation guide: https://ipython.readthedocs.io/en/stable/install/install.html

IPython Parallel can be installed with pip using the pip install ipyparallel command. For details refer to the installation guide: https://ipyparallel.readthedocs.io/en/latest/
   
3) Ensure the Python, IPython and IPython Parallel command line can be executed successfully on every LSF server host intended to run IPython.
For example:

     Python: Enter the python command on the LSF server host.
     IPython: Enter the ipython command on the LSF server host.
     IPython Parallel: Enter the ipcluster and ipcontroller commands on the LSF server host.

  
## Deployment Steps

Download the IPython plugin files and make minor changes

1) Find a top directory for the IPython plugin files
   
   For example,
   
     mkdir -p /opt/ibm/hpacomponent-ipython
   
2) Copy the IPython plugin files to the top directory for the IPython plugin
             
3) Change the place holder (i.e, @IPYTHONDIR@) to a shared directory in which to store IPython configuration files, history, commands, and extensions.

   For example,
   
       sed -i "s|@IPYTHONDIR@|/path/to/.ipython|" *.sh

4) Change the ownership of files to LSF Primary administrator

   For example,
   
       chown -R lsfadmin /opt/ibm/hpacomponent-ipython

5) Make the shell scripts readable and executable by all

    chmod a+rx *.sh
    

## Configure the IPython plug-in

Configure a static boolean resource in LSF to indicate which hosts have IPython installed.

For example, in $LSF_ENVDIR/lsf.shared:

    Begin Resource
    RESOURCENAME  TYPE    INTERVAL INCREASING  DESCRIPTION
    IpythonHost Boolean  ()   ()       (Boolean resource to indicate IPython is installed)
    End Resource

Add the resource to the hosts that have IPython installed in your LSF cluster file under $LSF_ENVDIR/lsf.clsuter.<clustername>

For example:

     Begin   Host
     HOSTNAME  model    type        server  RESOURCES   
     host1  !        !        1    (mg IpythonHost)
     host2  !        !        1    (IpythonHost)
     End     Host

Reconfigure LSF with the changes using the lsadmin reconfig and badmin reconfig commands.

## Verify job submission with the IPython plugin is working
Using the IPython plug-in in parallel mode LSF

Refer to https://www.ibm.com/docs/en/scsfhpa/10.2.0?topic=in-using-ipython-plug-parallel-mode

Using the IPython plug-in in non-parallel mode LSF

Refer to https://www.ibm.com/docs/en/scsfhpa/10.2.0?topic=in-using-ipython-plug-non-parallel-mode

