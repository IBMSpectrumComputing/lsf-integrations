# pacclient 
pacclient is a python3 based client example for accessing IBM Spectrum LSF Application Center and IBM Spectrum LSF.

## Prerequisites
     1). python 3(suggest 3.6 or above) and pip3
        $ yum install python3
        $ yum install python3-pip 
        
     2). httplib2 
        $ pip3 install httplib2
        
     3). configparser 
        $ pip3 install configparser
        
     4). urllib3
        $ pip3 install urllib3
     
## pacclient Examples

     $ python3 -V
     Python 3.6.8

     $ ls
     nls  pac_api.py  pacclient.py cacert.pem

     $ ./pacclient.py help
     pacclient.py usage:

     ping      --- Check whether the web service is available
     logon     --- Log on to IBM Spectrum LSF Application Center
     logout    --- Log out from IBM Spectrum LSF Application Center
     app       --- List applications or parameters of an application
     submit    --- Submit a job
     job       --- Show information for one or more jobs
     jobaction --- Perform a job action on a job
     jobdata   --- List all the files for a job
     download  --- Download job data for a job
     upload    --- Upload job data for a job
     usercmd   --- Perform a user command
     useradd   --- Add a user to IBM Spectrum LSF Application Center
     userdel   --- Remove a user from IBM Spectrum LSF Application Center
     userupd   --- Updates user email in CSV format from IBM Spectrum LSF Application Center.
     pacinfo   --- Displays IBM Spectrum LSF Application Center version, build number and build date
     notification --- Displays the notification settings for the current user.
              --- Registers notifications for a workload.
     flow          --- Show details for one or more flow instances from IBM Spectrum LSF Process Manager.
     flowaction    --- Perform an action on a flow instance from IBM Spectrum LSF Process Manager.
     flowdef       --- Show details for one or more flow definitions from IBM Spectrum LSF Process Manager.
     flowdefaction --- Perform an action on a flow definition from IBM Spectrum LSF Process Manager.
     help      --- Display command usage

     $ ./pacclient.py logon -l http://ma1lsfv02:8080 -u georgeg -p xxxxxxx
     You have logged on to PAC as: georgeg

     $ ./pacclient.py submit -a generic -p "COMMANDTORUN=sleep 200"
     The job has been submitted successfully: job ID 45439

     $ ./pacclient.py job
     JOBID     STATUS    EXTERNAL_STATUS        JOB_NAME                 COMMAND
     45439     Running   -                      *938772910               sleep 200

     $ ./pacclient.py usercmd -c "bstop 45439"
     Job <45439> is being stopped

     $ ./pacclient.py job
     JOBID     STATUS    EXTERNAL_STATUS        JOB_NAME                 COMMAND
     45439     Suspended -                      *938772910               sleep 200

     $ ./pacclient.py usercmd -c "bresume 45439"
     Job <45439> is being resumed

     $ ./pacclient.py job
     JOBID     STATUS    EXTERNAL_STATUS        JOB_NAME                 COMMAND
     45439     Running   -                      *938772910               sleep 200

## Connect to Spectrum LSF Application Center with https enabled
     
     when IBM Spectrum LSF Application Center is running with https enabled, pacclient must connect to it with https url.  
     it is required that public certificate file "cacert.pem" must stay in the same folder with pacclient.py. the default cacert.pem file
     works with default https in IBM Spectrum LSF Application Center.
     
     if you have enabled https with your own certificate,  then you need to copy the public certificate over to file: "cacert.pem".
     
     https usage examples:
     $ ls -l cacert.pem
     -rwxr-xr-x 1 root root 1193 Nov  9 17:16 cacert.pem
     
     $ ./pacclient.py ping -l https://ma1lsfv02:8443/
     Web Services are ready on URL:https://ma1lsfv02:8443/platform/
     
     $ ./pacclient.py logon -l https://ma1lsfv02:8443/
     You have logged on to PAC as: georgeg

     $  ./pacclient.py job
     JOBID     STATUS    EXTERNAL_STATUS        JOB_NAME                 COMMAND
     45441     Running   -                      *960263606               sleep 1200
     45440     Done      -                      *955691296               sleep 1234

 
