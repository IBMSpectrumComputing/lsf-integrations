#This is a sample application template for showing remote console per job.

# Pre-condition
1). vi pmc.conf, enable remote console per job by setting:
VNCSession=Job

2). pmcadmin stop ; 
    pmcadmin start
    
3). prepare tigervnc on each LSF servers which will execute this demo application--gedit
reference doc:  https://www.ibm.com/docs/en/slac/10.2.0?topic=consoles-enabling-vnc

# Deploy this application 

1). download the whole directory including directory name(GEDIT_ON_SERVER) and files under

2). copy the directory to /opt/ibm/lsfsuite/ext/gui/conf/application/published

3). logon PAC from browser, click on "New Workload"

4). submit job with GEDIT_ON_SERVER by specifying an input file

5). after job is running. click on the console icon beside the job ID in the workload list


## Copyright

(C) Copyright IBM Corporation 2016-2023

U.S. Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

IBM(R), the IBM logo and ibm.com(R) are trademarks of International Business Machines Corp., registered in many jurisdictions worldwide. Other product and service names might be trademarks of IBM or other companies. A current list of IBM trademarks is available on the Web at "Copyright and trademark information" at www.ibm.com/legal/copytrade.shtml.
