This is a sample application template for showing remote console per job.

<Pre-condition>
1). vi pmc.conf, enable remote console per job
VNCSession=Job
2). prepare tigervnc on each LSF servers which will execute this demo application--gedit
reference doc:  https://www.ibm.com/docs/en/slac/10.2.0?topic=consoles-enabling-vnc

<Deploy this application>

1). download the whole directory including directory name(GEDIT_ON_SERVER) and files under
2). copy the directory to /opt/ibm/lsfsuite/ext/gui/conf/application/published
3). logon PAC from browser, click on "New Workload"
4). submit job with GEDIT_ON_SERVER by specifying a input file
5). after job is running. click on the console icon beside the job ID in the workload list
