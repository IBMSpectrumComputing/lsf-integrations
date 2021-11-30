# The Jupyter Notebook plug-in
The Jupyter Notebook plug-in allows LSF to create a schedule using the best suitable host to run the Jupyter Notebook server on the cluster. This allows the interactive Jupyter environment and dashboard to be available to users.

 
## Prerequisites
1) LSF is installed.

2) Jupyter Notebook is installed on one or more LSF server hosts.

Refer to https://www.anaconda.com/distribution/#download-section 
   
3) Ensure the Python and Jupyter Notebook command line can be executed successfully on every LSF server host intended to run Jupyter.

   For example:
   
   On the LSF server host enter the command python to test if Python is installed successfully.
   
   On the LSF server host enter the command jupyter-notebook to test if Jupyter Notebook is installed successfully.
   
## Deployment Steps

Download the Jupyter Notebook plugin file and make minor changes

1) Find a top directory for the Jupyter Notebook plugin file
   
   For example,
   
     mkdir -p /opt/ibm/hpacomponent-jupyter-notebook
   
2) Copy the Jupyter Notebook plugin file to the top directory for the Jupyter Notebook plugin
             
3) Change the place holder (i.e, @JUPYTER_HOME@) to the Jupyter Notebook installation top directory

   For example,
   
       sed -i "s|@JUPYTER_HOME@|/opt/anaconda2|" *.sh

4) Change the ownership of files to LSF Primary administrator

   For example,
   
       chown -R lsfadmin /opt/ibm/hpacomponent-jupyter-notebook

5) Make the shell scripts readable and executable by all

    chmod a+rx *.sh
    

## Configure the Jupyter Notebook plug-in

Configure a static boolean resource in LSF to indicate which hosts have Jupyter Notebook installed.

For example, in $LSF_ENVDIR/lsf.shared:

    Begin Resource
    RESOURCENAME  TYPE    INTERVAL INCREASING  DESCRIPTION
    JupyterHost Boolean  ()   ()       (Boolean resource to indicate Jupyter is installed)
    End Resource

Add the resource to the hosts that have Jupyter Notebook installed in your LSF cluster file under $LSF_ENVDIR/lsf.clsuter.<clustername>

For example:

     Begin   Host
     HOSTNAME  model    type        server  RESOURCES   
     host1  !        !        1    (mg)
     host2  !        !        1    (JupyterHost)
     End     Host

Reconfigure LSF with the changes using the lsadmin reconfig and badmin reconfig commands.

## Verify job submission with the Jupyter Notebook plugin is working
https://www.ibm.com/docs/en/scsfhpa/10.2.0?topic=in-using-jupyter-notebook-plug

