#!/usr/bin/env python3

import sys
import os
import getopt
import httplib2
from xml.etree import ElementTree as ET
from xml.dom import minidom
from configparser import ConfigParser
from configparser import NoSectionError
import getpass
import socket
import re
import urllib3
import calendar
from datetime import timedelta, datetime
import csv
from pac_api import *

import logging

def logon_usage():
	print ( (_getmsg("logon_usage") + "\n") )
	
def main_logon(argv):
	url=''
	user=''
	password=''
	try:                                
		opts, args = getopt.getopt(argv, "hl:u:p:", ['help','url=','user=','pass=']) 
	except getopt.GetoptError:           
		logon_usage()                        
		return
	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			logon_usage()                     
			return                  
		elif ((opt == '-l') | (opt == "--url")) :
			url = arg  
		elif ((opt == '-u') | (opt == "--user")) :                
			user = arg  
		elif ((opt == '-p') | (opt == "--pass")) :                
			password = arg  

	if len(url) == 0:	
		url=input( _getmsg("logon_url_prompt") )
	url,context = parseUrl(url);
	p = re.compile('^(http|https)://[\w\W]+:\d+[/]{0,1}$')
	if (len(url) == 0) | (p.match(url.lower()) == None):
		print ( _getmsg("logon_null_url") )
		return
	url = url + context
	url = removeQuote(url)
	x509Flag, key, cert = checkX509PEMCert(url)

	if (x509Flag == False) | ( len(user) > 0) | (len(password) > 0):
		if len(user) == 0:
			user=input( _getmsg("logon_username") )
		if len(user) == 0:
			print ( _getmsg("logon_specify_username") )
			return
		if len(password) == 0:
			password=getpass.getpass()
		if len(password) == 0:
			print ( _getmsg("logon_specify_password") )
			return
		if ( (len(url) != 0) & ('https' in url.lower()) ):
			if ( ( os.path.isfile('cacert.pem') == False ) & (httplib2.__version__ >= '0.7.0') ):
				print ( _getmsg("https_certificate_missing") )
				return
		# In xml, & should be written as &amp; Or it will generate exception when CFX parses
		password = password.replace("&", "&amp;")
		# < === &lt;
		password = password.replace("<", "&lt;")
		# > === &gt;
		password = password.replace(">", "&gt;")
		
		# remove the quote
		password = removeQuote(password)
		user = removeQuote(user)
		
	# Log on action
	logon(url, user, password)

def submit_usage():
	print ( (_getmsg("submit_usage") + "\n") )

def main_submit(argv):
	if len(argv) == 0:
		submit_usage()                        
		return
	appName=''
	profile=''
	params=''
	slash = getFileSeparator()
	try:                                
		opts, args = getopt.getopt(argv, "ha:c:p:", ['help','app=','conf=', 'param=']) 
	except getopt.GetoptError:           
		submit_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			submit_usage()                     
			return                  
		elif ((opt == '-a') | (opt == "--app")) :                
			appName = arg  
		elif ((opt == '-c') | (opt == "--conf")) :                
			profile = arg  
		elif ((opt == '-p') | (opt == "--param")) :                
			params = arg  
	if len(appName) <= 0:
		print ( _getmsg("submit_arg_missing") )
		return
	inputParams={}
	inputFiles={}
	
	if len(profile) > 0:
		profile = removeQuote(profile)
		if (":" not in profile) & ( slash != profile[0]):
			dir = os.getcwd() + slash
			profile = dir + profile
			if os.path.isfile(profile) is False:
				print ( _getmsg("submit_file_notexist") % profile )
				return
		config = ConfigParser()
		config.optionxform = str #make option name case-sensitive
		try:
			config.read(profile)
		except IOError:
			print ( _getmsg("submit_cannot_openfile") % profile )
			return
		try:
			for option in config.options('Parameter'):
				inputParams[option]=config.get('Parameter', option)
		except NoSectionError:
			print ( _getmsg("submit_param_missing") % profile )
			return
		try:
			for option in config.options('Inputfile'):
				inputFiles[option]=config.get('Inputfile', option)
		except NoSectionError:
			print ( _getmsg("submit_inputfile_missing") % profile )
			return
			

	if len(params) > 0:
		for pp in params.split(';'):
			if len(pp) > 0:
				nv = pp.split('=',1)
				if len(nv) > 1:
					if ',' in nv[1]:
						inputFiles[nv[0]] = nv[1]
					else:
						inputParams[nv[0]] = nv[1]
				else:
					print ( _getmsg("submit_input_invalid") )                     
					return

	JobDict={}
	JobDict[APP_NAME]=appName
	try:
		span = inputParams['SPAN']
		inputParams['SPAN'] = "span[%s]" % span
	except KeyError:
		pass
	JobDict['PARAMS']=inputParams
	JobDict['INPUT_FILES']=inputFiles
	

	status, message = submitJob(JobDict)
	if status == 'ok':
		print ( _getmsg("submit_success").format(message) )
	else:
		print ( message)
		
def job_usage():
	print ( (_getmsg("job_usage") + "\n\n") )

def main_job(argv):
	jobStatus=''
	jobName=''
	jobId=''
	long=''
	group=''
	user=''
	past=''
	try:                                
		opts, args = getopt.getopt(argv, "hu:ls:n:g:p:", ['help','user=','long','status=','name=','group=','past=']) 
	except getopt.GetoptError:          
		job_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			job_usage()                     
			return 
		elif ((opt=='-u') | (opt == '--user')) :
			user=arg
		elif ((opt=='-l') | (opt == '--long')) :
			long='yes'                 
		elif ((opt == '-s') | (opt == "--status")) :                
			jobStatus = arg  
		elif ((opt == '-n') | (opt == "--name")) :                
			jobName = urllib3.quote(arg)
		elif ((opt == '-g') | (opt == "--group")) :
			group=urllib3.quote(arg)
		elif ((opt == '-p') | (opt == '--past')) :
			past=arg
	if len(args) > 0:
		jobId = args[0]
		p = re.compile('^[1-9]{1}[0-9]{0,}$')
		pl = re.compile('^[1-9]{1}[0-9]{0,}\[{1}[0-9]{0,}\]{1}$')
		if (len(jobId) == 0) | ((p.match(jobId.lower()) == None) and (pl.match(jobId.lower()) == None)) | (len(args)>1):
			job_usage()
			return	
	if (len(jobStatus) > 0 and len(jobName) > 0) | (len(jobStatus) > 0 and len(jobId) > 0) | (len(jobId) > 0 and len(jobName) > 0) | (len(jobId)>0 and len(group)>0) | (len(jobName)>0 and len(group)>0) | (len(jobStatus)>0 and len(group)>0):
		print ( _getmsg("job_usage_error") )
		return
	status = ''
	message = ''
	statusFlag = False
	nameFlag = False
	groupFlag=False
	if len(jobStatus) > 0:
		status, message = getJobListInfo('status='+jobStatus+'&user='+user+'&details='+long+'&past='+past)
		statusFlag = True
	elif len(jobName) > 0:
		status, message = getJobListInfo('name='+jobName+'&user='+user+'&details='+long+'&past='+past)
		nameFlag = True
	elif len(group) > 0:
		status, message = getJobListInfo('group='+group+'&user='+user+'&details='+long+'&past='+past)
		groupFlag=True
	if status != '':
		if status == 'ok':
			tree = ET.fromstring(message)
			jobs =tree.iter("Job")
			count = len(tree.findall('Job'))
			if count == 0:
				if statusFlag == True:
					print (  _getmsg("job_nomatch_status").format(jobStatus) )
				elif nameFlag == True:
					print (  _getmsg("job_nomatch_name").format(jobName) )
				elif groupFlag== True:
					print (  _getmsg("job_nomatch_group").format(group) )
				return
			showJobinfo(jobs,long, count)
		else:
			print(message)
		return

	if len(jobId) > 0:
		status, message= getJobListInfo('id='+jobId+'&user='+user+'&details='+long+'&past='+past)
		if status == 'ok':
			tree = ET.fromstring(message)
			jobs =tree.iter("Job")
			count = len(tree.findall('Job'))
			showJobinfo(jobs,long, count)
		else:
			print(message)
		return
	else:
		status, message= getJobListInfo('user='+user+'&details='+long+'&past='+past)
		if status == 'ok':
			tree = ET.fromstring(message)
			jobs =tree.iter("Job")
			count = len(tree.findall('Job'))
			showJobinfo(jobs,long, count)
		else:
			print(message)
		return
	job_usage()

def showJobinfo(jobs,long,count):
	if long == '':
		print ( _getmsg("job_info_title") )
		for xdoc in jobs:
			jobId=xdoc.find('id').text
			status=xdoc.find('status')
			extStatus=xdoc.find('extStatus')
			name=xdoc.find('name').text
			cmd=xdoc.find('cmd')
			print('%-10s%-10s%-23s%-25s%s' % (jobId, checkFieldValidity(status), SubStr(checkFieldValidity(extStatus)), SubStr(name),checkFieldValidity(cmd)))
	else:
		for xdoc in jobs:
			jobId=xdoc.find('id').text
			name=xdoc.find('name').text
			user=xdoc.find('user')
			jobType=xdoc.find('jobType')
			status=xdoc.find('status')
			appType=xdoc.find('appType')
			submitTime=xdoc.find('submitTime')
			endTime=xdoc.find('endTime')
			startTime=xdoc.find('startTime')
			estimatedStartTime=xdoc.find('estimatedStartTime')
			if estimatedStartTime != None:
				if estimatedStartTime.text != '-' :
					startTime.text = startTime.text + " (Estimated)"
			queue=xdoc.find('queue')
			cmd=xdoc.find('cmd')
			projectName=xdoc.find('projectName')
			pendReason=xdoc.find('pendReason')
			description=xdoc.find('description')
			extStatus=xdoc.find('extStatus')
			priority=xdoc.find('priority')
			exitCode=xdoc.find('exitCode')
			swap=xdoc.find('swap')
			pgid=xdoc.find('pgid')
			pid=xdoc.find('pid')
			nthreads=xdoc.find('nthreads')
			numProcessors=xdoc.find('numProcessors')
			fromHost=xdoc.find('fromHost')
			exHosts=xdoc.find('exHosts')
			askedHosts=xdoc.find('askedHosts')
			runTime=xdoc.find('runTime')
			mem=xdoc.find('mem')
			timeRemaining=xdoc.find('timeRemaining')
			estimateRunTime=xdoc.find('estimateRunTime')
			infile=xdoc.find('infile')
			outfile=xdoc.find('outfile')
			execCwd=xdoc.find('execCwd')
			graphicJob=xdoc.find('graphicJob')
			cwd=xdoc.find('cwd')
			timeRemaining=xdoc.find('timeRemaining')
			app=xdoc.find('app')
			jobForwarding=xdoc.find('jobForwarding')
			localClusterName=xdoc.find('localClusterName')
			localJobId=xdoc.find('localJobId')
			remoteJobId=xdoc.find('remoteJobId')
			remoteClusterName=xdoc.find('remoteClusterName')		
			# Add slots number: 123295
			slotsNum = xdoc.find('slotsNum')
			cpuEfficiency = xdoc.find('cpuEfficiency')
			# Add group name
			groupName = xdoc.find('groupName')
			# Add container
			container = xdoc.find('container')
			
			print ( _getmsg("job_info_id") % jobId )
			print ( _getmsg("job_info_name") % name )
			print ( _getmsg("job_info_type") % checkFieldValidity(jobType) )
			print ( _getmsg("job_info_status") % checkFieldValidity(status) )
			print ( _getmsg("job_info_apptype") % checkFieldValidity(appType) )
			print ( _getmsg("job_info_submittime") % checkFieldValidity(submitTime) )
			print ( _getmsg("job_info_user") % checkFieldValidity(user) )
			print ( _getmsg("job_info_endtime") % checkFieldValidity(endTime) )
			print ( _getmsg("job_info_starttime") % checkFieldValidity(startTime) )
			print ( _getmsg("job_info_queue") % checkFieldValidity(queue) )
			print ( _getmsg("job_info_cmd") % checkFieldValidity(cmd) )
			print ( _getmsg("job_info_projname") % checkFieldValidity(projectName) )
			print ( _getmsg("job_info_pending_reason") % checkFieldValidity(pendReason) )
			print ( _getmsg("job_info_desc") % checkFieldValidity(description) )
			print ( _getmsg("job_info_exstatus") % checkFieldValidity(extStatus) )
			print ( _getmsg("job_info_priority") % checkFieldValidity(priority) )
			print ( _getmsg("job_info_exitcode") % checkFieldValidity(exitCode) )
			print ( _getmsg("job_info_mem") % checkFieldValidity(mem) )
			print ( _getmsg("job_info_swap") % checkFieldValidity(swap) )
			print ( _getmsg("job_info_container") % checkFieldValidity(container) )
			print ( _getmsg("job_info_gid") % checkFieldValidity(pgid) )
			print ( _getmsg("job_info_pid") % checkFieldValidity(pid) )
			print ( _getmsg("job_info_numthread") % checkFieldValidity(nthreads) )
			print ( _getmsg("job_info_reqprocessors") % checkFieldValidity(numProcessors) )
			print ( _getmsg("job_info_submithost") % checkFieldValidity(fromHost) )
			print ( _getmsg("job_info_exeutionhost") % checkFieldValidity(exHosts) )
			print ( _getmsg("job_info_reqhost") % checkFieldValidity(askedHosts) )
			print ( _getmsg("job_info_runtime") % checkFieldValidity(runTime) )
			print ( _getmsg("job_info_cpuefficiency") % checkFieldValidity(cpuEfficiency) )
			print ( _getmsg("job_info_timeremain") % checkFieldValidity(timeRemaining) )
			print ( _getmsg("job_info_est_runtime") % checkFieldValidity(estimateRunTime) )
			print ( _getmsg("job_info_inputfile") % checkFieldValidity(infile) )
			print ( _getmsg("job_info_outfile") % checkFieldValidity(outfile) )
			print ( _getmsg("job_info_exe_cwd") % checkFieldValidity(execCwd) )
			print ( _getmsg("job_info_gjob") % checkFieldValidity(graphicJob) )
			print ( _getmsg("job_info_curdir") % checkFieldValidity(cwd) )
			print ( _getmsg("job_info_app_profile") % checkFieldValidity(app) )
			print ( _getmsg("job_info_localid") % checkFieldValidity(localJobId) )
			print ( _getmsg("job_info_localcluster") % checkFieldValidity(localClusterName) )
			print ( _getmsg("job_info_fwd") % checkFieldValidity(jobForwarding) )
			
			# Add slots number: 123295
			print ( _getmsg("job_info_slotsnum") % checkFieldValidity(slotsNum) )
			
			# Add group name
			print ( _getmsg("job_info_groupname") % checkFieldValidity(groupName) )
			
			if checkFieldValidity(jobForwarding) != 'None':
				print ( _getmsg("job_info_remoteid") % checkFieldValidity(remoteJobId) )
				print ( _getmsg("job_info_remotecluster") % checkFieldValidity(remoteClusterName) )		
			if count > 1:
				print(' ')
				print(' ')
					
def SubStr(field, size=None):
	if size is None:
		size = 10
	if len(field) > size :
		field = '*' + field[-(size-1):]
	return field

def checkFieldValidity(field):
	if field != None:
		if field.text == None :
			field = ''
		else:
			field = field.text
	else:
		field='-'
	return field

def download_usage():
	print ( (_getmsg("download_usage") + "\n\n") )

def main_download(argv):
	if len(argv) == 0:
		download_usage()                       
		return
	dir=''
	file = ''
	jobId=''
	cmd=''
	
	# Total size of uploaded files
	totalSize = 0
		
	try:                                
		opts, args = getopt.getopt(argv, "hd:f:c:", ['help','dir=','file=','cmd=']) 
	except getopt.GetoptError:           
		download_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			download_usage()                     
			return                  
		elif ((opt == '-d') | (opt == "--dir")) :                
			dir = arg  
		elif ((opt == '-f') | (opt == '--file')) :
			file = arg
		elif ((opt == '-c') | (opt == '--cmd')) :
			cmd = arg
	if dir == '' and cmd == '' and file == '' and len(args) <=0:
	   download_usage()
	   return
	if len(args) <= 0:
		print ( _getmsg("download_specify_id") )
		return
	if len(dir) <=0:
		dir = os.getcwd()
	jobId = args[0]
	if os.path.exists(dir) == False :
		print ( _getmsg("download_dirnotexist") % dir )
		return

	dir = removeQuote(dir)
	file = removeQuote(file)
	downloadJobFiles(jobId, dir, file, cmd)

def upload_usage():
	print ( (_getmsg("upload_usage") + "\n") )
	
def main_upload(argv):
	if len(argv) == 0:
		upload_usage()                       
		return
	dir=''
	file = ''
	jobId=''
	
	# Total size of uploaded files
	totalSize = 0
	
	try:                                
		opts, args = getopt.getopt(argv, "hd:f:") 
	except getopt.GetoptError:           
		upload_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h")) :      
			upload_usage()                     
			return                  
		elif ((opt == '-d')) :                
			dir = arg  
		elif ((opt == '-f')) :
			file = arg

	dir = removeQuote(dir)
	file = removeQuote(file)
	if file == '':
		print ( _getmsg("submit_file_notexist") )
		return
	p = re.compile('^[\w\W]+:/[\w\W]+')
	# Windows regular express compiler
	winp = re.compile('^[\w\W]+:[a-zA-Z]:[/\\\\]+')
	if (((dir == '') | ((len(dir) > 0) and (('/' != dir[0]) and (p.match(dir.lower()) == None) and ( winp.match(dir.lower()) == None) ))) and (len(args) <= 0)):
		print ( _getmsg("upload_specify_jobid") )
		return
	if ((':' in dir) and (p.match(dir.lower()) == None) and ( winp.match(dir.lower()) == None)):
		print ( _getmsg("upload_specify_absolutepath") )
		return
	cwd = os.getcwd()
	files = file.split(',')
	paths = ''
	p = re.compile('^[a-zA-Z]:[/\\][\w\W]+')
	slash = getFileSeparator()
	valid = True
	for f in files:
		f.strip()
		if len(f) > 0:
			if ((slash != f[0]) and (p.match(f.lower()) == None)):
				f = cwd + slash + f
			if not os.path.isfile(f):
				valid = False
				print ( _getmsg("upload_file_notfound") % f )
			elif os.access(f, os.R_OK) == 0:
				valid = False
				print ( _getmsg("upload_fileread_denied") % f )
			else:
				# Get all files total size
				totalSize += os.path.getsize(f)
				paths = paths + f + ','
	if not valid:
		return
	elif len(paths)<=0:
		print ( _getmsg("upload_file_notfound") % file )
		return
	else:
		paths = paths[:-1]
	p = re.compile('^[\w\W]+:/[\w\W]+')
	if ((len(dir) > 0) and (('/' == dir[0]) | (p.match(dir.lower()) != None) | (winp.match(dir.lower()) != None))):
		jobId = '0'
	else:
		jobId = args[0]
		p = re.compile('^[1-9]{1}[0-9]{0,}$')
		if p.match(jobId.lower()) == None:
			print ( _getmsg("upload_jobid_invalid") )
			return
		
	# If total file size is greater than 500Mb, upload them separately by WS API.
	if (totalSize > 536870912):
		# If one file size is greater than 500Mb, split it into chunks and every chunk max size is 500Mb
		files = paths.split(',')
		for f in files:
			if os.path.getsize(f) > 536870912:
				# Upload larger file
				uploadLargeFile(jobId, dir, f)
			else:
				# Upload normal file
				uploadJobFiles(jobId, dir, f)
	else:	
		uploadJobFiles(jobId, dir, paths)

def jobaction_usage():
	print ( (_getmsg("jobaction_usage") + "\n") )

def main_jobaction(argv):
	jobAction=''
	jobId=''
	try:                                
		opts, args = getopt.getopt(argv, "ha:", ['help','action=']) 
	except getopt.GetoptError:           
		jobaction_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			jobaction_usage()                     
			return                  
		elif ((opt == '-a') | (opt == "--action")) :                
			jobAction = arg  
	if len(args) <= 0 and len(jobAction) <= 0:
		jobaction_usage()
		return
	if len(args) <= 0:
		print ( _getmsg("jobaction_specify_jobid") )
		return
	if len(args) >0 :
		jobId = args[0]
		p = re.compile('^[1-9]{1}[0-9]{0,}$')
		pl = re.compile('^[1-9]{1}[0-9]{0,}\[{1}[0-9]{0,}\]{1}$')
		if (p.match(jobId.lower()) == None) and (pl.match(jobId.lower()) == None):
			jobaction_usage()
			return
	jobId=args[0]
	status, message = doJobAction(jobAction, jobId)
	print(message)

def flowdef_usage():
	print ( (_getmsg("flowdef_usage") + "\n") )
	
def main_flowDef(argv):
	flowName=''
	userName=''
	published=False
	status=''
	try:                                
		opts, args = getopt.getopt(argv, "hn:u:ps:", ['help','name=','username=','published','status=']) 
	except getopt.GetoptError:           
		flowdef_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			flowdef_usage()                     
			return                  
		elif ((opt == '-n') | (opt == "--name")) :                
			flowName = arg  
		elif ((opt == '-u') | (opt == "--username") | (opt == "--user_name")) :                
			userName = arg  
		elif ((opt == '-p') | (opt == "--published")) :                
			published = True  		
		elif ((opt == '-s') | (opt == "--status")) :                
			status = arg  
	if  len(args) > 0 :
		flowdef_usage()
		return		
	status, message = getflowDef(flowName, userName, published, status)
	if status == 'ok':
		tree = ET.fromstring(message)
		flowdefs =tree.iter("pseudoFlowDefinition")
		showFlowdefInfo(flowdefs)
	else:
		print(message)

def showFlowdefInfo(flowdefs):
	print ( _getmsg("flowdef_info_title") )
	for xdoc in flowdefs:
		name      = xdoc.find('name').text
		user      = xdoc.find('user').text
		status    = xdoc.find('status').text
		published = xdoc.find('published').text
		version   = xdoc.find('version').text
		print('%-31s%-16s%-10s%-11s%s' % (SubStr(name, 31-1), SubStr(user, 16-1), status, published, version))

def flowdefaction_usage():
	print ( (_getmsg("flowdefaction_usage") + "\n") )
	
def main_flowDefaction(argv):

	flowAction=''
	flowName=''
	flowPath=''
	variables=''
	comment=''
	version=''
	forceFlag=False
	useF=False
	useV=False
	useC=False
	try:                                
		opts, args = getopt.getopt(argv, "hfa:v:c:", ['help','force','action=','variables=','comment=']) 
	except getopt.GetoptError:          
		flowdefaction_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			flowdefaction_usage()                     
			return 
		elif ((opt=='-f') | (opt == '--force')) :
			forceFlag=True
			useF=True
		elif ((opt=='-a') | (opt == '--action')) :
			flowAction=arg
		elif ((opt == '-v') | (opt == "--variables") | (opt == "--version")) :
			variables=arg
			version=arg	
			useV=True
		elif ((opt == '-c') | (opt == '--comment')) :
			comment=arg
			useC=True

	if  len(args) <= 0 and len(flowAction) <= 0:
		flowdefaction_usage()
		return
	if ( (flowAction != "commit") and (flowAction != 'submit') and (flowAction != 'release') and
	     (flowAction != 'publish') and (flowAction != 'unpublish') and (flowAction != 'hold') and 
	     (flowAction != 'delete')):
			print ( _getmsg("flowdefaction_unsupported") )
			return
	if flowAction != 'delete' and useF==True:
		flowdefaction_usage()
		return
	if flowAction != 'commit' and useC==True:
		flowdefaction_usage()
		return
	if flowAction != 'commit' and flowAction != 'submit' and useV==True:
		flowdefaction_usage()
		return
	if len(args) <= 0:
		if flowAction == 'commit':
			print ( _getmsg("flowdefaction_specify_filepath") )
			return
		else:
			print ( _getmsg("flowdefaction_specify_flowname") )
			return	
		
	if flowAction == 'commit':
		flowPath = args[0]
	else:
		flowName = args[0]
		
	status, message = doflowDefAction(flowAction, flowName, flowPath, variables, comment, forceFlag,version)
	print(message)

def usercmd_usage():
	print ( (_getmsg("usercmd_usage") + "\n") )

def main_usercmd(argv):
	userCmd=''

	for i in range(0, len(argv)):
		if ((argv[i] == '-h')):
			usercmd_usage()
			return
		elif (((argv[i] == '-c')) & (i+1 < len(argv))):
			userCmd = removeQuote(argv[i+1]).strip()
			if len(userCmd) <= 0:
				usercmd_usage()
				return
			for arg in argv[i+2:]:
				temp = removeQuote(arg).strip()
				if len(temp) > 0:
					userCmd = userCmd + ' "' + temp + '"'
			break
		else:
			usercmd_usage()
			return

	if len(userCmd) <= 0:
		usercmd_usage()
		return

	status, message = doUserCmd(userCmd)
	print(message)

def ping_usage():
	print ( (_getmsg("ping_usage") + "\n") )

def main_ping(argv):
	url = ''
	try:                                
		opts, args = getopt.getopt(argv, "hl:", ['help','url='])
	except getopt.GetoptError:           
		ping_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			ping_usage()                     
			return   
		elif ((opt == '-l') | (opt == "--url")) :
			url = arg         
	if len(url) == 0:	
		url=input( _getmsg("ping_url"))
	url,context = parseUrl(url);
	p = re.compile('^(http|https)://[\w\W]+:\d+[/]{0,1}$')
	if (len(url) == 0) | (p.match(url.lower()) == None):
		print ( _getmsg("ping_urlformat_example") )
		return
	url = url + context
	ping(url)

def logout_usage():
	print ( (_getmsg("logout_usage") + "\n") )

def main_logout(argv):
	try:                                
		opts, args = getopt.getopt(argv, "h", ['help'])
	except getopt.GetoptError:           
		logout_usage()                        
		return

	for opt, arg in opts:                
		if ((opt == "-h") | (opt == "--help")) :      
			logout_usage()                     
			return                  
	logout()

def main_usage():
	print ( (_getmsg("main_usage") + "\n") )
	
def app_usage():
	print ( (_getmsg("app_usage") + "\n") )

def main_app(argv):
	if len(argv) == 0:
		app_usage()
		return
	appName = ''
	list = False
	try:
		opts, args = getopt.getopt(argv, "hlp:", ['help','list','param='])
	except getopt.GetoptError:
		app_usage()
		return
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			app_usage()
			return
		elif ((opt == "-l") | (opt == "--list")):
			list = True
		elif ((opt == "-p") | (opt == "--param")):
			appName = arg
	
	if list == True:
		status, message = getAllAppStatus()
		if status == 'ok':
			xdoc = minidom.parseString(message)
			apps = xdoc.getElementsByTagName('AppInfo')
			if len(apps) == 0:
				print ( _getmsg("app_no_published_app") )
				return
			print ( _getmsg("app_allappstatus_title") )
			for app in apps:
				appStatus=''
				appName=''
				for apparg in app.childNodes:
					if apparg.nodeName == 'appName':
						appName = apparg.childNodes[0].nodeValue
					elif apparg.nodeName == 'status':
						appStatus = apparg.childNodes[0].nodeValue
				
				print('%-24s%-15s' % (appName, appStatus))
		else:
			print(message)
		return
	
	if len(appName) > 0:
		status, message = getAppParameter(appName)
		if status == "ok":
			xdoc = minidom.parseString(message)
			params = xdoc.getElementsByTagName('AppParam')
			print ( _getmsg("app_app_param_title") )
			for param in params:
				id = ''
				label = ''
				mandatory = ''
				dValue = ''
				for paramValue in param.childNodes:
					if paramValue.nodeName == 'id':
						id = paramValue.childNodes[0].nodeValue
					elif paramValue.nodeName == 'label':
						label = paramValue.childNodes[0].nodeValue
					elif paramValue.nodeName == 'mandatory':
						mandatory = paramValue.childNodes[0].nodeValue
					elif paramValue.nodeName == 'defaultValue':
						dValue = paramValue.childNodes[0].nodeValue
				print('%-18s%-35s%-11s%-10s' % (id, label, mandatory, dValue))
		else:
			print(message)
		return
	app_usage()
	return

def userAdd_usage():
	print ( (_getmsg("useradd_usage") + "\n") )
	
def main_userAdd(argv):
	username = ''
	email = ''
	roles = ''
	try:
		opts, args = getopt.getopt(argv, "hu:e:r:", ['help','username=','email=','role='])
	except getopt.GetoptError:
		userAdd_usage()
		return
	
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			userAdd_usage()
			return
		elif ((opt == "-u") | (opt == "--username")):
			username = arg
		elif ((opt == "-e") | (opt == "--email")):
			email = arg
		elif ((opt == "-r") | (opt == "--role")):
			roles = arg
	
	unameValid = 'false'
	
	if len(username) == 0:
		username=input('username:')
		if (len(username) == 0):
			userAdd_usage()
			return
	else:
		unameValid = 'true'
		
	if (len(email) == 0) & (unameValid == "false"):
		email=input('email:')
		
	if (len(roles) == 0) & (unameValid == "false"):
		roles=input('role[Normal User]:')
		if (len(roles) == 0):
			roles = 'Normal User'
	
	status, message = addUser(username, email, roles)
	if status == "ok":
		if len(message) > 0:
			xdoc = minidom.parseString(message)
			error = xdoc.getElementsByTagName('message')
			print(error[0].childNodes[0].nodeValue)
		else:
			print('User '+username+' added to IBM Spectrum LSF Application Center.')
	else:
		print(message)
	return


def userDel_usage():
	print ( (_getmsg("userdel_usage") + "\n") )

def main_userDel(argv):
	username = ''
	try:
		opts, args = getopt.getopt(argv, "hu:", ['help','username='])
	except getopt.GetoptError:
		userDel_usage()
		return
	
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			userDel_usage()
			return
		elif ((opt == "-u") | (opt == "--username")):
			username = arg
			
	if len(username) == 0:
		username=input('username:')
		if (len(username) == 0):
			userDel_usage()
			return
		
	status, message = removeUser(username)
	if status == "ok":
		if len(message) > 0:
			xdoc = minidom.parseString(message)
			error = xdoc.getElementsByTagName('message')
			print(error[0].childNodes[0].nodeValue)
		else:
			print('User '+username+' removed from IBM Spectrum LSF Application Center.')
	else:
		print(message)
	return
	
def userUpdate_usage():
	print ( (_getmsg("userupd_usage") + "\n") )
	
def main_userUpdate(argv):
	if len(argv) == 0:
		userUpdate_usage()
		return

	filepath = ''
	try:
		opts, args = getopt.getopt(argv, "hf:", ['help','file='])
	except getopt.GetoptError:
		userUpdate_usage()
		return
	
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			userUpdate_usage()
			return
		elif ((opt == "-f") | (opt == "--file")):
			filepath = arg
	
	if os.path.isfile(filepath) == False:
		print (  _getmsg("file_notfound").format(filepath) )
		return
	try:
		with open(filepath, 'rb') as csvfile:
			reader = csv.reader(csvfile, delimiter=',')
			for row in reader: 
				if len(row) < 2:
					print (  _getmsg("invalid_file_format").format(reader.line_num, filepath) )
					continue
				username = row[0].strip()
				email = row[1].strip()
				if len (username) == 0 or len (email) == 0:
					print (  _getmsg("invalid_file_format").format(reader.line_num, filepath) )
					continue
				status, message = updateUser(username, email)
				if status == "ok":
					if len(message) > 0:
						xdoc = minidom.parseString(message)
						error = xdoc.getElementsByTagName('message')
						print (  _getmsg("invalid_line_value").format(reader.line_num, filepath, error[0].childNodes[0].nodeValue) )
					else:
						print (  _getmsg("user_updated").format(username) )
				else:
					print(message)
					return
	except IOError as e:
		print(str(e))
		return
	
	return

def jobdata_usage():
	print ( (_getmsg("jobdata_usage") + "\n") )

def main_jobdata(argv):
	if len(argv) == 0:
		jobdata_usage()
		return
	jobId = ''
	list = False
	try:
		opts, args = getopt.getopt(argv, "hl",['help','list'])
	except getopt.GetoptError:
		jobdata_usage()
		return
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			jobdata_usage()
			return
		elif ((opt == "-l") | (opt == "--list")):
			list = True
	if len(args) <= 0:
		print ( _getmsg("app_specify_jobid") )
		return
	jobId = args[0]
	if list == False:
		print ( _getmsg("app_specify_param") )
		jobdata_usage()
		return
	files = jobdataList(jobId)
	if len(files) > 0:
		print ( _getmsg("app_title") )
	else:
		return
	try:
		for f in files:
			fileArray = f.split("*")
			if len(fileArray) == 5:
				print("%-20s%-40s" % (fileArray[0], fileArray[1]))
	except TypeError:
		print (  _getmsg("app_nojob_data").format(jobId) )
		return

def pacinfo_usage():
	print ( (_getmsg("pacinfo_usage") + "\n") )

def main_pacinfo(argv):
	
	try:
		opts, args = getopt.getopt(argv, "h",['help'])
	except getopt.GetoptError:
		pacinfo_usage()
		return
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			pacinfo_usage()
			return
	if len(args) > 0:
		pacinfo_usage()
		return
	
	# Invoke the /ws/version web service
	status, content = getProductInfo()
	
	version = ''
	buildNo = ''
	buildDate = ''
	productName = ''
	# If status is error, do nothing.
	if status == "ok":
		# Parsing returned XML.
		tree = ET.fromstring(content)
		version = tree.find('version')
		buildNo = tree.find('buildNo')
		buildDate = tree.find('buildDate')
		productName = tree.find('productName')
		# Or display all product information
		print("%s Version %s Build %s, %s" % (checkFieldValidity(productName), checkFieldValidity(version), checkFieldValidity(buildNo), checkFieldValidity(buildDate)))
	else:
		# Display error message
		print(content)
		
	# Always return whatever it returns ok or error.
	return

def notification_usage():
	print ( (_getmsg("notification_usage") + "\n") )

def main_notification(argv):
	if len(argv) == 0:
		notification_usage()
		return
	workloadId = ''
	params=''
	setting = False
	register = False
	inputParams={}
	try:
		opts, args = getopt.getopt(argv, "hsr:p:",['help','settings', 'register=','param='])
	except getopt.GetoptError:
		notification_usage()
		return
	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			notification_usage()
			return
		elif ((opt == "-s") | (opt == "--settings")):
			setting = True
		elif ((opt == "-r") | (opt == "--register")):
			register = True
			workloadId = arg
		elif ((opt == "-p") | (opt == "--param")):
			params = arg
	if setting == True and register == True:
		print ( _getmsg("notificaiton_usage_error") )
		notification_usage()
		return

	if setting == True:
		if len(params) > 0:
			print ( _getmsg("notificaiton_usage_setting_error") )
			notification_usage()
			return
		status, message = getNotificationSetting()
		if status == "ok":
			xdoc = minidom.parseString(message)
			node = xdoc.getElementsByTagName('UserName')
			if len(node) > 0:
			        print ( _getmsg("NotificationSetting_title").format(node[0].childNodes[0].nodeValue))
			node = xdoc.getElementsByTagName('UserEmail')
			if len(node) > 0:
				if node[0].childNodes[0].nodeValue == '-':
					print ( _getmsg("NotificationSetting_without_email"))
				else:
					print ( _getmsg("NotificationSetting_email").format(node[0].childNodes[0].nodeValue))

			print ( _getmsg("NotificationSetting_parameters") )
			params = xdoc.getElementsByTagName('AppParam')
			for param in params:
				id = ''
				label = ''
				mandatory = ''
				value = ''
				dValue = ''
				for node in param.childNodes:
					if node.nodeName == 'id':
						id = node.childNodes[0].nodeValue
					if node.nodeName == 'value' and len(node.childNodes) > 0:
						value = node.childNodes[0].nodeValue
					if node.nodeName == 'defaultValue' and len(node.childNodes) > 0:
						dValue = node.childNodes[0].nodeValue
					if node.nodeName == 'label':
						label = node.childNodes[0].nodeValue
				print('%s=%s' % (id, value))
		else:
			print(message)
		return
	if register == True:
		p = re.compile('^[1-9]{1}[0-9]{0,}$')
		if p.match(workloadId.lower()) == None:
			print ( _getmsg("notification_workload_id_invalid") )
			return

		if len(params) > 0:
			for pp in params.split(';'):
				if len(pp) > 0:
					nv = pp.split('=')
					if len(nv) > 1:
						inputParams[nv[0]] = nv[1]
					else:
						print ( _getmsg("notification_parameter_form_invalid") )                     
						return
		status, message = registerNotification(workloadId, inputParams)
		if status == "ok":
			xdoc = minidom.parseString(message)
			msg = xdoc.getElementsByTagName('message')
			print(msg[0].childNodes[0].nodeValue)
		else:
			print(message)
		return
	return


def flow_usage():
	print((_getmsg("flow_usage") + "\n"))

def main_flow(argv):
	flowname = ''
	flowid = ''
	username = ''
	flowstate = ''
	try:
		opts, args = getopt.getopt(argv, "hf:i:u:s:", ['help', 'flowname=', 'flowid=', 'username=', 'state='])
	except getopt.GetoptError:
		flow_usage()
		return

	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			flow_usage()
			return
		elif ((opt == "-f") | (opt == "--flowname")):
			flowname = arg
		elif ((opt == "-i") | (opt == "--flowid")):
			flowid = arg
		elif ((opt == "-u") | (opt == "--username")):
			username = arg
		elif ((opt == "-s") | (opt == "--state")):
			flowstate = arg

	status, message = getPseudoFlowInstances(flowid, flowname, username, flowstate)
	if status == 'ok':
		tree = ET.fromstring(message)
		flows =tree.iter("pseudoFlowInstance")
		showFlowInfo(flows)
	else:
		print(message)

def utc_to_local(utc):
    if utc in ['-', '']:
        return utc
    utc_dt = datetime.strptime(utc[:-5], '%Y-%m-%dT%H:%M:%S')
    timestamp = calendar.timegm(utc_dt.timetuple())
    local_dt = datetime.fromtimestamp(timestamp)
    delta = timedelta(days=local_dt.day-utc_dt.day,
                      hours=local_dt.hour-utc_dt.hour,
                      minutes=local_dt.minute-utc_dt.minute)
    sign = (delta >= timedelta(microseconds=1))
    delta = str(abs(delta))
    h_offset, m_offset, _ = delta.split(':')
    local = local_dt.strftime('%Y-%m-%d %H:%M:%S')
    if sign:
        local += ' GMT+'
    else:
        local += ' GMT-'
    return local + str(h_offset).zfill(2) + ':' + str(m_offset).zfill(2)

def showFlowInfo(flows):
	print ( _getmsg("flow_info_title") )
	for xdoc in flows:
		flowid     = xdoc.find('id').text
		user       = xdoc.find('user').text
		name       = xdoc.find('fullName').text
		state      = xdoc.find('state')
		start_time = xdoc.find('startTime')
		end_time   = xdoc.find('endTime')
		project_name = xdoc.find('projectName')
		description = xdoc.find('description')
		print('%-8s%-16s%-31s%-10s%-30s%-30s%-25s%s' % (flowid, SubStr(user, 16-1), SubStr(name, 31-1), checkFieldValidity(state), checkFieldValidity(start_time), checkFieldValidity(end_time),checkFieldValidity(project_name),checkFieldValidity(description)))

def flowaction_usage():
	print ( (_getmsg("flowaction_usage") + "\n") )

def main_flowaction(argv):
	action = ''
	flowid = ''
	varlist = ''
	try:
		opts, args = getopt.getopt(argv, "ha:v:", ['help', 'action=', 'variable_list='])
	except getopt.GetoptError:
		flowaction_usage()
		return

	for opt, arg in opts:
		if ((opt == "-h") | (opt == "--help")):
			flowaction_usage()
			return
		elif ((opt == "-a") | (opt == "--action")):
			action = arg
		elif ((opt == "-v") | (opt == "--variable_list")):
			varlist = arg

	if len(args) <= 0 and len(action) <= 0:
		flowaction_usage()
		return
	if len(args) <= 0:
		print ( _getmsg("flowaction_specify_flowid") )
		return
	if len(args) >0 :
		flowid = args[0]

	status, message = doFlowInstanceAction(action, varlist, flowid)
	print(message)

def main(argv):
	logging.basicConfig(filename='pacclient.log', level=logging.DEBUG)
	logging.debug('Started')

	try:
		if ((len(argv) <= 0) | (argv[0] == 'help')):
			main_usage()
			return
		if argv[0] == 'logon':
			main_logon(argv[1:])
			return
		if argv[0] == 'submit':
			main_submit(argv[1:])
			return 
		if argv[0] == 'job':
			main_job(argv[1:])
			return	
		if argv[0] == 'download':
			main_download(argv[1:])
			return
		if argv[0] == 'logout':
			main_logout(argv[1:])
			return
		if argv[0] == 'ping':
			main_ping(argv[1:])
			return
		if argv[0] == 'jobaction':
			main_jobaction(argv[1:])
			return
		if argv[0] == 'app':
			main_app(argv[1:])
			return
		if argv[0] == 'jobdata':
			main_jobdata(argv[1:])
			return
		if argv[0] == 'usercmd':
			main_usercmd(argv[1:])
			return
		if argv[0] == 'upload':
			main_upload(argv[1:])
			return
		if argv[0] == 'pacinfo':
			main_pacinfo(argv[1:])
			return
		if argv[0] == 'useradd':
			main_userAdd(argv[1:])
			return
		if argv[0] == 'userdel':
			main_userDel(argv[1:])
			return	
		if argv[0] == 'userupd':
			main_userUpdate(argv[1:])
			return	
		if argv[0] == 'notification':
			main_notification(argv[1:])
			return
		if argv[0] == 'flowdef':
			main_flowDef(argv[1:])
			return
		if argv[0] == 'flowdefaction':
			main_flowDefaction(argv[1:])
			return
		if argv[0] == 'flow':
			main_flow(argv[1:])
			return
		if argv[0] == 'flowaction':
			main_flowaction(argv[1:])
			return
	
		print ( _getmsg("app_subcmd_notsupported") % argv[0] )
		main_usage()
		return
	except socket.error:
		errno, errstr = sys.exc_info()[:2]
		if errno == socket.timeout:
			print ( _getmsg("app_timeout") )
		else:
			print ( _getmsg("app_socket_err") )
	except (KeyboardInterrupt,EOFError):
		pass
	
if __name__ == "__main__":

	# define getmsg method to get translation message
	# based on current system locale setting
	_getmsg = getTranslations().gettext
	
	if len(sys.argv) <= 1:
		main_usage()
	else:
		main(sys.argv[1:])

