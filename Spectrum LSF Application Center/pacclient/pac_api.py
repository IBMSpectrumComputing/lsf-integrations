#!/usr/bin/env python3

import sys
import os
import getopt
import http.client as httplib
import httplib2
from xml.etree import ElementTree as ET
from xml.dom import minidom
from xml.parsers.expat import ExpatError
import getpass
import locale
import gettext
import urllib
import urllib3
from urllib.parse import quote
import re

PACCONTEXT='platform'
PACPASSFILE='.pacpass'
ACCEPT_TYPE='text/plain,application/xml,text/xml,multipart/mixed'
ERROR_STR='errMsg'
#After fix this should be treated as TAG
NOTE_STR='<' +'note' +'>'
ERROR_TAG='<' + ERROR_STR + '>'
ACTION_STR='actionMsg'
ACTION_TAG='<' + ACTION_STR + '>'
CMD_STR='cmdMsg'
CMD_TAG='<' + CMD_STR + '>'
APP_NAME='APPLICATION_NAME'

def getSysLocale():
	lc, encoding = locale.getdefaultlocale()
	if not lc:
		lc = 'en_US'	
	return lc

def getTranslations():
	#  All translation files are under mo/<LOCALE>/LC_MESSAGES/pacclient.mo
	mo_location = os.path.dirname(os.path.abspath(__file__)) + '/nls'
	APP_NAME = "pacclient"

	#  Set default system locale
	#  DEFAULT_LANGUAGES = os.environ.get('LANG', '').split(':')
	DEFAULT_LANGUAGES = ['en']

	# Determine current system locale settings
	languages = []
	lc, encoding = locale.getdefaultlocale()
	if lc:
		languages = [lc]

	# Concat all languages
	# gettext will use the first available translation in the list
	languages += DEFAULT_LANGUAGES
	
	# Get transtion using gettext API
	gettext.install (True)
	gettext.bindtextdomain (APP_NAME, mo_location)
	gettext.textdomain (APP_NAME)
	return (gettext.translation (APP_NAME, mo_location, languages = languages, fallback = True))

_getmsg = getTranslations().gettext

def parseUrl(param_url):
	if len(param_url) == 0:
		return param_url,PACCONTEXT
	find_index = -1
	if param_url.startswith("http://"):
		find_index = 7
	if param_url.startswith("https://"):
		find_index = 8
	if find_index == -1:
		return param_url,PACCONTEXT
	slash_index = param_url.find("/",find_index)
	context = ""
	if slash_index > -1:
		context = param_url[slash_index+1:len(param_url)]
		param_url = param_url[0:slash_index+1]
	if param_url.endswith("/") == False:
		param_url = param_url + '/' 
	if (context == '/') or (len(context) == 0) :
		context = PACCONTEXT
	if context.endswith("/") == False:
		context = context + '/'
	return param_url,context

def downloadFile(srcName, dstPath, jobId, cmd):

	url,token = getToken();
	
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		print ( _getmsg("must_logon_pac") )
		return
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
	
	url_file = url + 'webservice/pacclient/file/' + jobId
	if cmd == '':
		body=getFileNameByFullPath(srcName)
	else:
		body=getFileNameByFullPath(srcName) + '|' + cmd

	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_file, 'GET', body=body, headers=headers)
		content = contentb.decode()
		
		# Check response content
		if len(content) <= 0:
			fileName = getFileNameByFullPath(srcName)
			if response['status'] == '404':
				print ( _getmsg("downloadfailed_notfound") % fileName )
			elif response['status'] == '403':
				print ( _getmsg("downalodfile_errnopermission") % fileName )
			else:
				print ( _getmsg("downalodfile_nopermission_notfound") % fileName )
			return
		else:
			# Parse content and download files
			parseDownloadContent(dstPath, content)
		
	except (AttributeError, httplib.IncompleteRead):
		print ( _getmsg("connect_ws_err") % url )
	except IOError:
		print ( "   --" + (_getmsg("permission_denied_writefile") % getDestFilePath(dstPath, srcName) ) )

def getFileNameByFullPath(filePath):
	nList = []
	if filePath[0] != '/':
		# For Windows path
		nList = filePath.split('\\')
	else:
		# For Linux path
		nList = filePath.split('/')
	fName = nList.pop()
	return fName

def getDestFilePath(dstPath, filePath):
	fName = getFileNameByFullPath(filePath)
	# Arrange the file path
	if dstPath[-1] != getFileSeparator():
		dstName= dstPath + getFileSeparator() + fName
	else:
		dstName= dstPath + fName
	return dstName

def parseDownloadContent(dstPath, content):
	"""
	Parse the HTTP response when downloading multiple files
	Store them into dstPath
	"""
	# Get the boundary and trim the \r\n\t
	boundary = content.split("\n")[1].strip()
	
	# Split content with boundary to parse the files
	fileSections = content.split(boundary)
	fileNum = len(fileSections) - 1
	
	# Loop the file sections and store the file to destination path
	for fileHeaders in fileSections:
		# If has Content-ID in this section, it contains one file
		if 'Content-ID:' in fileHeaders:
			
			# Get file name
			tempArray = fileHeaders.split("Content-ID: ")
			fName = tempArray[1][1:tempArray[1].index(">")]
			
			fName = getFileNameByFullPath(fName)
			
			# Arrange the file path
			if dstPath[-1] != getFileSeparator():
				dstName= dstPath + getFileSeparator() + fName
			else:
				dstName= dstPath + fName
			
			# Get the file content
			# Important logic
			strlength = len(fileHeaders)
			startIndex = fileHeaders.index(">") + 5
			# Remove extra characters
			endIndex = strlength
			if fileNum > 1:
				endIndex = strlength - 2
			fileContent = fileHeaders[startIndex : endIndex]
			
			# Tip message for downloading files
			print (  _getmsg("downloading_file").format(fName, dstName) )
			
			try:
				# Write file 
				f = open(dstName,'wb')
				f.write(fileContent.encode())
				f.close()
			except IOError:
				print ( "   --" + (_getmsg("permission_denied_writefile") % dstName) )

def downloadJobFiles(jobId, dstPath, dFile, cmd):
	# If you specify download files with -f option, use webservice/pacclient/file/{id} API to download
	if len(dFile) > 0:
		print ( _getmsg("start_download") )
		downloadFile(dFile, dstPath, jobId, cmd)
		return
	
	# Download all files of one job
	url, token = getToken();
	
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		print ( _getmsg("must_logon_pac") )
		return
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	if os.access(dstPath, os.W_OK) == 0:
		print ( _getmsg("dirpermission_denied") % dstPath )
		return
	url_jobfiles= url + 'webservice/pacclient/jobfiles/' + jobId

	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_jobfiles, 'GET', headers=headers)
		content = contentb.decode()
		if ('\\' not in content) and ('/' not in content):
			print(content)
			return
		if (response['status'] != '200'):
			print ( _getmsg("connect_ws_err") % url )
			return
		
		files = content.split(';')
		
		if len(files) <= 0:
			print (  _getmsg("app_nojob_data").format(jobId) )
			return
		
		print ( _getmsg("start_download") )
		# Download all files in job directory
		for ff in files:
			if len(ff) <= 0:
				break
			downloadUtil(dstPath, ff, jobId, cmd)
	except AttributeError:
		print ( _getmsg("connect_ws_err") % url )
		
def downloadUtil(dstPath, dFile, jobId, cmd):
	"""
	download a file from server into local host path :dstPath.
	"""
	# hostname*filepath*fileType*fileSize*controlFlag;
	fileArray = dFile.split("*")
	
	# Don't download job directory
	if ((len(fileArray) == 5) and (fileArray[2] == 'DIR')):
		return
	
	# If file size is 0, remember it and check it later
	fileSize = ''
	controlFlag = 'true'
	if ((len(fileArray) == 5) and (fileArray[2] != 'DIR')):
		fileSize = fileArray[3]
		controlFlag = fileArray[4]
	
	if ((len(fileArray) == 5) | (len(fileArray) == 2)):
		dFile = fileArray[1]
	
	# If has no control permission on job file, show error message
	if controlFlag == 'false':
		print ( _getmsg("downalodfile_errnopermission") % dFile )
		return
	
	if dFile[0] != '/':
		# For Windows path
		nList = dFile.split('\\')
	else:
		# For Linux path
		nList = dFile.split('/')
	
	fName= nList.pop()
	if fName[-1] == ' ':
		fName = fName[0:-1]
	if len(dstPath) > 0:
		if dstPath[-1] != getFileSeparator():
			dstName= dstPath + getFileSeparator() + fName
		else:
			dstName= dstPath + fName
	else:
		dstName= fName
	# print (  _getmsg("downloading_file").format(fName,dstName) )
	
	# For 0 kb file, just create it
	# if fileSize == '0':
	#	f=open(dstName,'wb')
	#	f.close()
	#	return
	
	# For other files, download it from server
	downloadFile(dFile, dstPath, jobId, cmd)

def downloadMultipleFiles(dstPath, files, jobId, specifiedFileList, cmd):
	"""
	download specified job files from server into local host path: dstPath.
	"""
	if len(specifiedFileList) <= 0:
		return
	
	dFileList = specifiedFileList.split(',')
	for dFile in dFileList:
		# We support wild cards: ? * []
		if ('*' in dFile) | ('?' in dFile) | ('[' in dFile) | ('[!' in dFile):
			# File name includes wild card characters
			orignalFile = dFile
			dFile = dFile.replace('?', '.')
			dFile = dFile.replace('*', '.*')
			dFile = dFile.replace('[!', '[^')
			
			dFile = '^' + dFile + "$"
			
			pattern = re.compile(dFile)
			downloadFlag = False
			for file in files:
				# If file is empty string, skip it.
				if len(file) <= 0:
					continue
				
				# hostname*filepath*fileType*fileSize*controlFlag;
				fileArray = file.split("*")
					
				# Don't download job directory
				if ((len(fileArray) == 5) and (fileArray[2] == 'DIR')):
					continue
				
				fileAbsoPath = fileArray[1]
				
				if fileAbsoPath[0] != '/':
					# For Windows path
					fileStrList = fileAbsoPath.split('\\')
				else:
					# For Linux path
					fileStrList = fileAbsoPath.split('/')
	
				fileName = fileStrList.pop()
				if fileName[-1] == ' ':
					fileName = fileName[0:-1]
				
				# Search file name from job file list
				if pattern.match(fileName):
					# Set download flag
					downloadFlag = True
					# Download specified file
					downloadSpecifiedFile(dstPath, files, jobId, fileAbsoPath, cmd)
			
			# If don't download any files, print error message
			if downloadFlag == False:
				print ( _getmsg("downloadfailed_notfound") % orignalFile )
				return
		else:
			# Download specified file
			downloadSpecifiedFile(dstPath, files, jobId, dFile, cmd)


def downloadSpecifiedFile(dstPath, files, jobId, specifiedFile, cmd):
	"""
	download a specified file from server into local host path: dstPath.
	"""
	fileSize = ''
	controlFlag = 'true'
	specifiedFileList = ''
	downloadFlag = False
	for dFile in files:
		# hostname*filepath*fileType*fileSize*controlFlag;
		fileArray = dFile.split("*")
	
		# Don't download job directory
		if ((len(fileArray) == 5) and (fileArray[2] == 'DIR')):
			continue
	
		# If file size is 0, remember it and check it later
		if ((len(fileArray) == 5) and (fileArray[2] != 'DIR')):
			fileSize = fileArray[3]
			controlFlag = fileArray[4]
	
		if ((len(fileArray) == 5) | (len(fileArray) == 2)):
			dFile = fileArray[1]
			
		if dFile.endswith(specifiedFile):
			downloadFlag = True
			break
	
	if downloadFlag == False:
		print ( _getmsg("downloadfailed_notfound") % specifiedFile )
		return
	
	# If has no control permission on job file, show error message
	if controlFlag == 'false':
		print ( _getmsg("downalodfile_errnopermission") % dFile )
		return
	
	if dFile[0] != '/':
		# For Windows path
		nList = dFile.split('\\')
	else:
		# For Linux path
		nList = dFile.split('/')
	
	fName= nList.pop()
	if fName[-1] == ' ':
		fName = fName[0:-1]
	if len(dstPath) > 0:
		if dstPath[-1] != getFileSeparator():
			dstName= dstPath + getFileSeparator() + fName
		else:
			dstName= dstPath + fName
	else:
		dstName= fName
			
	print (  _getmsg("downloading_file").format(fName,dstName) )
	
	# For 0 kb file, just create it
	if fileSize == '0':
		f=open(dstName,'wb')
		f.close()
		return
	
	# For other files, download it from server
	downloadFile(dFile, dstPath, jobId, cmd)


def uploadUtil(dstPath, dFile, jobId):
	"""
	upload a file to server :dstPath.
	"""
	if dstPath.strip()=='':
		dstPath = 'current job directory'
	nList = dFile.split(',')
	fName= nList
	for ff in fName:
			if len(ff) <= 0:
				break
			if dstPath.strip()=='':	
				print (  _getmsg("uploading_file_currentjobdir").format(ff) )
			else:
				print (  _getmsg("uploading_file_jobdir").format(ff,dstPath) )
				
def uploadLargeFile(jobId, dstPath, dFile):
	url, token = getToken();
		
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		print ( _getmsg("must_logon_pac") )
		return
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	boundary='4k89ogja023oh1-gkdfk903jf9wngmujfs95m'
	print ( _getmsg("start_uploading") )
	uploadUtil(dstPath, dFile, jobId)
	url_upfile = url + 'webservice/pacclient/uplargefile/' + jobId
	fileSize = os.path.getsize(dFile)
	# 500Mb
	chunksize = 536870912
	
	# Calculate the chunkamount
	if fileSize % chunksize != 0:
		chunkamount = fileSize / chunksize + 1
	else:
		chunkamount = fileSize / chunksize
		
	chunkid = 0
	fileobj = open(dFile, 'rb')
	while fileSize > 0:
		chunkid += 1
		if (fileSize - chunksize) <= 0:
			chunksize = fileSize
		fileContent = fileobj.read(chunksize).decode()
		fileSize -= chunksize
		try:
			status, body = encode_body_uplargefile(boundary, dstPath, fileContent, dFile, chunkid, chunkamount)
		except MemoryError:
			print ( _getmsg("memory_not_enough") )
			return

		headers = {'Content-Type': 'multipart/mixed; boundary=' + boundary,
			'Accept': 'text/plain;', 'Cookie': 'platform_token=' + token, 'Content-Length': str(len(body))}
		if (token.startswith('OAuth2')):
			user, authtoken = checkOAuthToken(token)
			headers = {'Content-Type': 'multipart/mixed; boundary=' + boundary, 'Accept': 'text/plain;', 
				'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 'Content-Length': str(len(body))}

		try:
			response, contentb = http.request(url_upfile, 'POST', body=body, headers=headers)
			content = contentb.decode()
			# Upload failed or there are some issues for uploading
			if "successfully" not in content:
				print(content)
				return
			if response['status'] != '200':
				print ( _getmsg("uploadfailed_connectws") )
				return
		except AttributeError:
			print ( _getmsg("connect_ws_err") % url )
			return
	# Print the returned message	
	print(content)

def uploadJobFiles(jobId, dstPath, dFile):
	url, token = getToken();
		
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		print ( _getmsg("must_logon_pac") )
		return
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	boundary='4k89ogja023oh1-gkdfk903jf9wngmujfs95m'
	try:
		status,body = encode_body_upfile(boundary, dstPath, dFile)
	except MemoryError:
		print ( _getmsg("notenoughmem_upload") )
		return
	
	if status == 'error':
		print(body)
	headers = {'Content-Type': 'multipart/mixed; boundary=' + boundary, 'Accept': 'text/plain;', 
		'Cookie': 'platform_token=' + token, 'Content-Length': str(len(body)), 
		'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'multipart/mixed; boundary=' + boundary, 'Accept': 'text/plain;', 
			'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 'Content-Length': str(len(body)), 
			'Accept-Language': getSysLocale().replace("_", "-").lower()}

	url_upfile = url + 'webservice/pacclient/upfile/' + jobId

	try:
		print ( _getmsg("start_uploading") )
		uploadUtil(dstPath, dFile, jobId)
		response, content = http.request(url_upfile, 'POST', body=body, headers=headers)
		if response['status'] == '200':
			print(content.decode())
		else:
			print ( _getmsg("uploadfailed_connectws") )
	except AttributeError:
		print ( _getmsg("connect_ws_err") % url )
		
def jobdataList(jobId):
	url, token = getToken()
		
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		print ( _getmsg("must_logon_pac") )
		return
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_jobfiles= url + 'webservice/pacclient/jobfiles/' + jobId
	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_jobfiles, 'GET', headers=headers)
		content = contentb.decode()
		if ('\\' not in content) and ('/' not in content):
		    print(content)
		    return ''
		files = content.split(';')
		return files
	except AttributeError:
		print ( _getmsg("connect_ws_err") % url )
    
def logon(url, username, password):
	if url[len(url) -1 ] != '/':
		url += '/'

	# Check whether or not to use the X509 client authentication
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	#Get the http connection
	http = getHttp(url,x509Flag)
	
	# Initial the variables
	url_logon= url + 'webservice/pacclient/logon/'
	headers = {}
	body = ''
	
	# If not X509 client authentication, use the normal way.
	# When set the username value, that is to say you want to use the normal authentication to logon.
	if ( (x509Flag == False) | (len(username) > 0) ):
		url_check, token = getToken()
		if ( (url_check != url) | (False == token.startswith("platform_token=" + username + "#quote#")) ):
			token = "platform_token="
		headers = {'Content-Type': 'application/xml', 'Cookie': token, 'Accept': ACCEPT_TYPE, 
			'Accept-Language': getSysLocale().replace("_", "-").lower()}
		body='<User><name>%s</name> <pass>%s</pass> </User>' % (username, password)
	else:
		headers = {'Content-Type': 'application/xml', 'Accept': ACCEPT_TYPE, 
			'Accept-Language': getSysLocale().replace("_", "-").lower()}
		body='<User></User>'
		# http object add the certificate for http request
		http.add_certificate(keypemfile, certpemfile, '')
		
	try:
		response, contentb = http.request(url_logon, 'GET', body=body, headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc=minidom.parseString(content)
			tk=xdoc.getElementsByTagName("token")
			jtk=xdoc.getElementsByTagName("jtoken")
			
			if x509Flag == True:
				if len(username) <= 0:
					# For X509 client authentication
					username = xdoc.getElementsByTagName("name")
					if len(username) > 0:
						print (  _getmsg("logon_pac_as").format(username[0].childNodes[0].nodeValue) )
						saveToken(url, '', jtk)
					else:
						try:
							err=xdoc.getElementsByTagName("errMsg")
							print(err[0].childNodes[0].nodeValue)
						except IndexError:
							print ( _getmsg("connect_ws_err") % url )
				else:
					if len(tk) > 0:
						print (  _getmsg("logon_pac_as").format(username) )
						#print tk[0].childNodes[0].nodeValue
						saveToken(url, tk[0].childNodes[0].nodeValue,jtk)
					else:
						err=xdoc.getElementsByTagName("errMsg")
						print(err[0].childNodes[0].nodeValue)
			else:
				if len(tk) > 0:
					print (  _getmsg("logon_pac_as").format(username) )
					#print tk[0].childNodes[0].nodeValue
					saveToken(url, tk[0].childNodes[0].nodeValue, jtk)
				else:
					err=xdoc.getElementsByTagName("errMsg")
					print(err[0].childNodes[0].nodeValue)
		else:
			print ( _getmsg("failed_connect_wsurl") % url_logon )
	except (AttributeError, httplib2.ServerNotFoundError, httplib.InvalidURL, ExpatError):
		print ( _getmsg("connect_ws_err") % url )

def logout():
	url, token = getToken()

	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)

	if ( (x509Flag == False) & (len(token) <= 0) ):
		print ( _getmsg("must_logon_pac") )
		return
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# For X.509 client authentication, don't need to send HTTP request to logout
		# We can only tell user that you have logout successfully
		http.add_certificate(keypemfile, certpemfile, '')
		#print "you have logout successfully."
		
	url_logout= url + 'webservice/pacclient/logout/'
	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_logout, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			if content == 'ok':
				if os.name == 'nt':	
					fpath=os.environ['HOMEPATH']
					if len(fpath) > 0:
						fpath = os.environ['HOMEDRIVE'] + fpath + '\\' +PACPASSFILE
					else:
						fpath += '\\' + PACPASSFILE
				else:
					fpath = os.environ['HOME'] + '/' + PACPASSFILE
				os.remove(fpath)
				print ( _getmsg("logout_success") )
			else:
				print(content.decode())
		else:
			print ( _getmsg("failed_connect_wsurl") % url_logout )
	except AttributeError:
		print ( _getmsg("connect_ws_err") % url )
		
def getJobListInfo(parameter):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_job = url + 'webservice/pacclient/jobs?' + parameter
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_job, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc=ET.fromstring(content)
			if ERROR_TAG in content:
				err=xdoc.find(ERROR_STR)
				return 'error', err.text
			elif xdoc.find(NOTE_STR):
				err=xdoc.find(NOTE_STR)
				return 'error', err.text
			else:
				return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_job
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url 

def getJobInfo(jobId):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_job = url + 'webservice/pacclient/jobs/' + jobId
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_job, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc=minidom.parseString(content)
			if ERROR_TAG in content:
				err=xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
			else:
				return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_job
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url

def getJobForStatus(jobStatus):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_job = url + 'webservice/pacclient/jobsforstatus/' + jobStatus
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_job, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc=minidom.parseString(content)
			if ERROR_TAG in content:
				err=xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
			else:
				return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_job
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url
	
def getJobForName(jobName):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_job = url + 'webservice/pacclient/jobsforname/' + jobName
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_job, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc=minidom.parseString(content)
			if ERROR_TAG in content:
				err=xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
			else:
				return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_job
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url

def saveToken(url, token,jtoken):
	#if len(token) <= 0:
	#	return
	if len(jtoken) > 0:
		token = token + ",JSESSIONID=" + jtoken[0].childNodes[0].nodeValue
	if os.name == 'nt':	
		fpath=os.environ['HOMEPATH']
		if len(fpath) > 0:
			fpath = os.environ['HOMEDRIVE'] + fpath + '\\' +PACPASSFILE
		else:
			fpath += '\\' + PACPASSFILE
	else:
		fpath = os.environ['HOME'] + '/' + PACPASSFILE
	try:
		ff= open(fpath, "w")
	except IOError as e:
		print (  _getmsg("cannot_openfile").format(fpath,e.strerror) )
	else:
		ff.write(url)
		ff.write('\n')
		ff.write(token)
		ff.close

def getToken():
	token=''
	url=''
	if os.name == 'nt':	
		fpath=os.environ['HOMEPATH']
		if len(fpath) > 0:
			fpath = os.environ['HOMEDRIVE'] + fpath + '\\' + PACPASSFILE
		else:
			fpath += '\\' + PACPASSFILE
	else:
		fpath = os.environ['HOME'] + '/' + PACPASSFILE
	try:
		ff= open(fpath, "rb")		
	except IOError:
		return url,token
	else:
		url_token=ff.read().decode().split('\n')
		ff.close()
		if len(url_token) <= 1:
			return url, token
		url=url_token[0]
		token=url_token[1].replace('"', '#quote#')
		if len(token) <= 0:
			return url, token
		else:
			#return url, 'platform_token='+token
			return url, token

def getFileSeparator():
	if os.name == 'nt':
		return '\\'
	else:
		return '/'

def submitJob(jobDict):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')

	if len(jobDict) == 0:
		return 'error', _getmsg("file_nojob_param")
	if  APP_NAME not in jobDict.keys():
		return 'error', _getmsg("published_app_notfound") % APP_NAME
	
	boundary='bqJky99mlBWa-ZuqjC53mG6EzbmlxB'
	if 'PARAMS'  in jobDict.keys():
		job_params=jobDict['PARAMS']
	else:
		job_params={}
	
	try:
		if job_params['NOTIFY_ENABLE'] == None:
			pass
	except KeyError:
		job_params['NOTIFY_ENABLE'] = 'Y'

	if 'INPUT_FILES' in jobDict.keys():
		job_files=jobDict['INPUT_FILES']
	else:
		job_files={}

	body = encode_body(boundary, jobDict[APP_NAME], job_params, job_files)
	if body == None:
		return 'error', _getmsg("wrong_inputfile_param")
	if "Submit job failed" in body:
		return 'error', body
	headers = {'Content-Type': 'multipart/mixed; boundary='+boundary,
		'Accept': 'text/xml,application/xml;', 'Cookie': 'platform_token=' + token,
		'Content-Length': str(len(body)), 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'multipart/mixed; boundary='+boundary, 
			'Accept': 'text/xml,application/xml;', 'Content-Length': str(len(body)),
    		'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
    		'Accept-Language': getSysLocale().replace("_", "-").lower()}

	url_submit = url + 'webservice/pacclient/submitapp'
	try:
		response, contentb = http.request(url_submit, 'POST', body=body, headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc=minidom.parseString(content)
			if ERROR_TAG not in content:
				jobIdTag=xdoc.getElementsByTagName("id")
				return 'ok', jobIdTag[0].childNodes[0].nodeValue
			else:
				err=xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
		else:
			return 'error', _getmsg("failed_connws_submit")
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url
	
def doJobAction(jobAction, jobId):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_jobaction = url + 'webservice/pacclient/jobOperation/' + jobAction +'/' + jobId
	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_jobaction, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc = minidom.parseString(content)
			if ERROR_TAG in content:
				err = xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
			elif ACTION_TAG in content:
				action = xdoc.getElementsByTagName(ACTION_STR)
				return 'ok', action[0].childNodes[0].nodeValue
			else:
				return 'error', _getmsg("failed_connws_logon")
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_jobaction
	except (AttributeError, ExpatError):
		return 'error', _getmsg("ws_notready_url") % url_jobaction
		
def getflowDef(flowName, userName, published, status):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
	
	url_flowdefs = url + 'ws/flow/definitions' +'?flowname='+flowName +'&username='+ userName +'&status='+ status 
	if published == True:
		url_flowdefs = url_flowdefs +'&published='+ str(published)
	
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_flowdefs, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			return 'ok', content
		else:
			xdoc = minidom.parseString(content)
			message = xdoc.getElementsByTagName('message')
			return 'error', message[0].childNodes[0].nodeValue
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url_flowdefs
		
def doflowDefAction(flowAction, flowName, flowPath, variables, comment, forceFlag,version):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
	
	body = ''	
	if ((flowAction == 'submit') | (flowAction == 'publish') | 
	    (flowAction == 'unpublish') | (flowAction == 'hold') | 
	    (flowAction == 'release') ):      
		url_flowaction = url + 'ws/flow/definitions/' + flowAction
		data = {'flownames': flowName,'variables': variables}
		headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'platform_token=' + token, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()} 
		if (token.startswith('OAuth2')):
			user, authtoken = checkOAuthToken(token)
			headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
				'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

		try:
			response, contentb = http.request(url_flowaction, 'POST', urllib.urlencode(data), headers=headers)
			content = contentb.decode()
			xdoc = minidom.parseString(content)
			message = xdoc.getElementsByTagName('message')

			if response['status'] == '200':
				return 'ok', message[0].childNodes[0].childNodes[0].nodeValue
			else:
				return 'error', message[0].childNodes[0].nodeValue
		except (AttributeError, ExpatError):
			return 'error', _getmsg("ws_notready_url") % url_flowaction
	elif (flowAction == "delete") :      
		url_flowaction = url + 'ws/flow/definitions/' + flowName +'?force='+ str(forceFlag)
		headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'platform_token=' + token, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()} 
		if (token.startswith('OAuth2')):
			user, authtoken = checkOAuthToken(token)
			headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
				'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

		try:
			response, contentb = http.request(url_flowaction, 'DELETE', headers=headers)
			content = contentb.decode()
			if response['status'] == '204':
				return 'ok', 'Flow has been deleted'
			else:
				xdoc = minidom.parseString(content)
				err = xdoc.getElementsByTagName("message")
				return 'error', err[0].childNodes[0].nodeValue
		except (AttributeError, ExpatError):
			return 'error', _getmsg("ws_notready_url") % url_flowaction 
	elif (flowAction == "commit") :      
		url_flowaction = url + 'ws/flow/definitions/' + flowAction
		data = {'filepath': flowPath,'comment': comment,'version': version}
		headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'platform_token=' + token, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
		if (token.startswith('OAuth2')):
			user, authtoken = checkOAuthToken(token)
			headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
				'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

		try:
			response, contentb = http.request(url_flowaction, 'POST', urllib.urlencode(data), headers=headers)
			content = contentb.decode()
			xdoc = minidom.parseString(content)
			message = xdoc.getElementsByTagName("message")

			if response['status'] == '200':
				return 'ok', message[0].childNodes[0].childNodes[0].nodeValue
			else:
				return 'error', message[0].childNodes[0].nodeValue
		except (AttributeError, ExpatError):
			return 'error', _getmsg("ws_notready_url") % url_flowaction 

def doUserCmd(userCmd):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')

	body = '<UserCmd><cmd>%s</cmd></UserCmd>' % (userCmd)
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token,
		'Accept': 'text/xml', 'Content-Length': str(len(body)), 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'text/xml', 'Content-Length': str(len(body)), 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	url_usercmd = url + 'webservice/pacclient/userCmd'
	try:
		response, contentb = http.request(url_usercmd, 'POST', body=body, headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc = minidom.parseString(content)
			msg = ''
			if ERROR_TAG in content:
				err = xdoc.getElementsByTagName(ERROR_STR)
				if ((err.length > 0) and (err[0].childNodes.length > 0)):
					msg = err[0].childNodes[0].nodeValue
				return 'error', msg
			elif CMD_STR in content:
				cmd = xdoc.getElementsByTagName(CMD_STR)
				if ((cmd.length > 0) and (cmd[0].childNodes.length > 0)):
					msg = cmd[0].childNodes[0].nodeValue
				return 'ok', msg
			else:
				return 'error', _getmsg("failed_connws_logon")
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_usercmd 
	except (AttributeError, ExpatError):
		return 'error', _getmsg("ws_notready_url") % url_usercmd

		
def ping(url):
	if url[len(url) -1 ] != '/':
		url += '/'
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	http = getHttp(url,x509Flag)
	if x509Flag == True:
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_ping = url + 'webservice/pacclient/ping/'
	body = url
	headers = {'Content-Type': 'text/plain', 'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	#if (token.startswith('OAuth2')):
	#	user, authtoken = checkOAuthToken(token)
	#	headers = {'Content-Type': 'text/plain', 'Auth-User': user, 
	#		'Accept': ACCEPT_TYPE, 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, content = http.request(url_ping, 'GET', body=body, headers=headers)
		if response['status'] == '200':
			print(content.decode())
		else:
			print ( _getmsg("ws_notready_url") % url_ping )
	except (AttributeError, httplib2.ServerNotFoundError, httplib.InvalidURL):
		print ( _getmsg("connect_ws_err") % url )
	
def removeQuote(str):
	"""
	Remove the single or double quote. for example: 'abc' --> abc
	"""
	while len(str) > 2:
		if ((str[0] == '"') & (str[-1] == '"')):
			str = str[1:-1]
		elif ((str[0] == "'") & (str[-1] == "'")):
			str = str[1:-1]
		else:
			break
	return str

def getAllAppStatus():
	url, token = getToken()

	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)

	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")

	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_app = url + 'webservice/pacclient/appStatus'
	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_app, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc = minidom.parseString(content)
			if ERROR_TAG in content:
				err=xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
			else:
				return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_app
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url
	
def getAppParameter(appName):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_app = url + 'webservice/pacclient/appParams'
	body = appName
	headers = {'Content-Type': 'text/plain', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_app, 'GET', body = body, headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			xdoc = minidom.parseString(content)
			if ERROR_TAG in content:
				err=xdoc.getElementsByTagName(ERROR_STR)
				return 'error', err[0].childNodes[0].nodeValue
			else:
				return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_app
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url

# Get product information function
def getProductInfo():
	# Get url
	url, token = getToken()
	
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	# Init the http object
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	# Arrange the URI
	url_app = url + 'ws/version'
	# Arrange the http request headers
	headers = {'Content-Type': 'text/plain', 'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'text/plain', 'Auth-User': user, 'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		# Send the request with GET method
		response, contentb = http.request(url_app, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			# Response status code is 200: OK
			if 'simple_error.jsp' in content:
				return 'error', _getmsg("internal_server_error")
			return 'ok', content
		elif response['status'] == '500':
			# Response status code is 500: Interal Server Error
			return 'error', _getmsg("internal_server_error")
		elif response['status'] == '404':
			# Response status code is 404: No service was found.
			return 'error', _getmsg("no_service_found")
		else:
			# In general, give a common error message for other status codes.
			return 'error', _getmsg("failed_connect_wsurl") % url_app
	except (AttributeError):
		# Parameter exception when send request.
		return 'error', _getmsg("connect_ws_err") % url


def encode_body(boundary, appName, params, inputFiles):
	slash = getFileSeparator()
	boundary2='_Part_1_701508.1145579811786'
	def encode_appname():
		return ('--' + boundary,
                'Content-Disposition: form-data; name="AppName"',
		'Content-ID: <AppName>',
                '', appName)

	def encode_paramshead():
		return('--' + boundary,
		'Content-Disposition: form-data; name="data"',
		'Content-Type: multipart/mixed; boundary='+ boundary2,
		'Accept-Language:' + getSysLocale().replace("_", "-").lower(),
		'Content-ID: <data>', '')

	def encode_param(param_name):
		return('--' + boundary2,
		'Content-Disposition: form-data; name="%s"' % param_name,
		'Content-Type: application/xml; charset=UTF-8',
		'Content-Transfer-Encoding: 8bit',
		'Accept-Language:' + getSysLocale().replace("_", "-").lower(),
		'', '<AppParam><id>%s</id><value>%s</value><type></type></AppParam>' %(param_name, params[param_name]))

	def encode_fileparam(param_name, param_value):
		return('--' + boundary2,
		'Content-Disposition: form-data; name="%s"' % param_name,
		'Content-Type: application/xml; charset=UTF-8',
		'Content-Transfer-Encoding: 8bit',
		'Accept-Language:' + getSysLocale().replace("_", "-").lower(),
		'', '<AppParam><id>%s</id><value>%s</value><type>file</type></AppParam>' %(param_name, param_value))

	def encode_file(filepath, filename):
		return('--' + boundary,
			'Content-Disposition: form-data; name="%s"; filename="%s"' %(filename, filename),
			'Content-Type: application/octet-stream',
			'Content-Transfer-Encoding: binary',
			'Accept-Language:' + getSysLocale().replace("_", "-").lower(),
			'Content-ID: <%s>' % quote(filename),
			'', open(filepath, 'rb').read().decode())

	lines = []
	upType = ''
	upFlag = False
	lines.extend(encode_appname())
	lines.extend(encode_paramshead())
	for name in params:
		lines.extend (encode_param(name))
	for name in inputFiles:
		value=inputFiles[name]
		valueStr=inputFiles[name]
		# Specify multiple files
		valueArray = valueStr.split('#')
		filepathList = ''
		for value in valueArray:
			if ',' in value:
				try:
					upType = value.split(',')[1]
					if (upType == 'link') | (upType == 'copy') | (upType == 'path'):
						# lines.extend (encode_fileparam(name, value))
						if upType == 'copy':
							print ( _getmsg("copying_serverfile") % value.split(',')[0] )
					else:
						upFlag = True
						value = value.replace('\\', '/').split('/').pop()	
						#lines.extend (encode_fileparam(name, filename))
					
					if filepathList == '':
						filepathList = value
					else:
						filepathList += ';' + value
					
				except IndexError:
					return
			else:
				return
		lines.extend (encode_fileparam(name, filepathList))
	
	lines.extend (('--%s--' % boundary2, ''))
	if upFlag == True:
		for name in inputFiles:
			valueStr=inputFiles[name]
			# Specify multiple files
			valueArray = valueStr.split('#')
			for value in valueArray:
				if ',' in value:
					upType = value.split(',')[1]
					filepath = value.split(',')[0]
					if upType == 'upload':
						filename = filepath.replace('\\', '/').split('/').pop()
						try:
							lines.extend(encode_file(filepath, filename))
						except IOError:
							return _getmsg("submitjob_failed_filedirnotfound") % filepath
						print ( _getmsg("uploading_inputfile") % filepath )
	lines.extend (('--%s--' % boundary, ''))
	return '\r\n'.join (lines)

def encode_body_uplargefile(boundary, dir, fileContent, file, chunkid, chunkamount):
	slash = getFileSeparator()
	dir = quote(dir)
	def encode_dir():
		return ('--' + boundary,
			'Content-Disposition: form-data; name="DirName"',
			'Content-ID: <DirName>',
			'', dir)
	def encode_chunkid():
		return ('--' + boundary,
			'Content-Disposition: form-data; name="chunkid"',
			'Content-ID: <chunkid>',
			'', str(chunkid))
	def encode_chunkbase(filename):
		return ('--' + boundary,
			'Content-Disposition: form-data; name="chunkbase"',
			'Content-ID: <chunkbase>',
			'', filename)
	def encode_chunkmount():
		return ('--' + boundary,
			'Content-Disposition: form-data; name="chunkamount"',
			'Content-ID: <chunkamount>',
			'', str(chunkamount))

	def encode_file(filename):
		return('--' + boundary,
			'Content-Disposition: form-data; name="%s"; filename="%s"' %(filename, filename),
			'Content-Type: application/octet-stream',
			'Content-Transfer-Encoding: binary',
			'Content-ID: <%s>' % filename,
			'', fileContent)

	lines = []
	lines.extend(encode_dir())
	lines.extend(encode_chunkid())
	lines.extend(encode_chunkmount())
	filename = file.replace('\\', '/').split('/').pop()
	filename = quote(filename)
	lines.extend(encode_chunkbase(filename))
	chunkFilename = ".%s.%d" %(filename, chunkid)
	lines.extend(encode_file(chunkFilename))
	lines.extend (('--%s--' % boundary, ''))
	return 'ok','\r\n'.join (lines)	

def encode_body_upfile(boundary, dir, filelist):
	slash = getFileSeparator()
	def encode_dir():
		return ('--' + boundary,
			'Content-Disposition: form-data; name="DirName"',
			'Content-ID: <DirName>',
			'', quote(dir))

	def encode_file(filepath, filename):
		return('--' + boundary,
			'Content-Disposition: form-data; name="%s"; filename="%s"' %(filename, filename),
			'Content-Type: application/octet-stream',
			'Content-Transfer-Encoding: binary',
			'Accept-Language:' + getSysLocale().replace("_", "-").lower(),
			'Content-ID: <%s>' % quote(filename),
			'', open(filepath, 'rb').read().decode())

	lines = []
	lines.extend(encode_dir())
	files = filelist.split(',')
	for f in files:
		filename = f.replace('\\', '/').split('/').pop()
		try:
			lines.extend(encode_file(f, filename))
		except IOError:
			return 'error', _getmsg("failed_to_readfile") % f
	lines.extend (('--%s--' % boundary, ''))
	return 'ok','\r\n'.join (lines)

def checkOAuthToken(token):
	tokenVal = token.split('#')[1]
	tokenArr = tokenVal.split('::')
	return tokenArr[0], tokenArr[1]

# Check the X509 PEM key/cert files whether or not exist.
# Return three value: X509Cert flag, keypemfile path, certpemfile path
# If X509Cert flag is False, the other values are empty string
def checkX509PEMCert(url):
	# If url is invalid for https, won't check cert.
	if ( (len(url) == 0) | ('https' not in url.lower()) ):
		return False, '', ''
	
	# Get the current path for key/cert files
	cwdPath = os.getcwd() + getFileSeparator();
	
	# Create the variables of key/cert files absolute path
	keypemfile = cwdPath + '.key.pem'
	certpemfile = cwdPath + '.cert.pem'
	
	# Check .key.pem and .cer.pem whether or not exist
	if ( ( os.path.isfile(keypemfile) == True ) & ( os.path.isfile(certpemfile) == True ) ):
		return True, keypemfile, certpemfile
	else:
		return False, '', ''

#Get HTTP
def getHttp(url,x509Flag):
	
	if ( x509Flag == True ):
		return httplib2.Http(disable_ssl_certificate_validation=True)
	#Check whether or not https is enabled
	sslHandshakeRequiredFlag, pemFile = checkSSLHandshakeRequired(url)

	#If the file exists and SSL Handshake is required(httplib2 version is 0.7+)
	if ( (len(pemFile) > 0) & (sslHandshakeRequiredFlag == True) ):
		http = httplib2.Http(ca_certs=pemFile, disable_ssl_certificate_validation=True)
	else:
		http = httplib2.Http()
	return http

# Return two values: HTTPS flag, pemFile path
# If HTTPS flag is False, the other value is an empty string
def checkSSLHandshakeRequired(url):
	
	httpsInURL = False;
	if ( (len(url) != 0) & ('https' in url.lower()) ):
		httpsInURL = True;
	
	#Check if httplib version is 7 or above
	#if httplib2.__version__ >= '0.7.0':
	#	newVersion = True
	#else:
	#	newVersion = False
	newVersion = True
		
	# Create if the cacert.pem file exists under the current directory
	if httpsInURL == True:
		pemFile = 'cacert.pem' 
		if ( (newVersion == True)  & ( os.path.isfile(pemFile) == True ) ):
			return True, pemFile
		else:
			if ( newVersion == True ):
				print ( _getmsg("https_certificate_missing") )
				exit();
	return False, ''


def addUser(username, email, roles):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_useradd = url + 'ws/user'

	#constract xml as the request body
	body = '<user name="%username" email="%email">'.replace('%username',username).replace('%email',email)
	
	if len(roles) > 0:
		body += '<roles>'
		role = '<role name="%role" />'
		
		if roles.find(',') < 0:
			body += (role.replace('%role', roles.lstrip().rstrip()) + '</roles>')
		else:
			for x in roles.split(','):
				if len(x) > 0:
					body += role.replace('%role', x.lstrip().rstrip())

			body += '</roles>'
		
	body += '</user>'
	
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_useradd, 'POST', body = body, headers=headers)
		content = contentb.decode()
		
		if response['status'] == '204':
			return 'ok', ''
		elif response['status'] == '200':
			return 'ok', content
		elif response['status'] == '403':
			return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_useradd
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url	
	
	
def removeUser(username):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_userdel = url + 'ws/user/' + username
	
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_userdel, 'DELETE', headers=headers)
		content = contentb.decode()
		
		if response['status'] == '204':
			return 'ok', ''
		elif response['status'] == '200':
			return 'ok', content
		elif response['status'] == '403':
			return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_userdel
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url	
	
def updateUser(username, email):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_userupdate = url + 'ws/user'

	body = '<user name="%username" email="%email">'.replace('%username',username).replace('%email',email)
	
	body += '</user>'
	
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_userupdate, 'PUT', body = body, headers=headers)
		content = contentb.decode()
		
		if response['status'] == '204':
			return 'ok', ''
		elif response['status'] == '200':
			return 'ok', content
		elif response['status'] == '403':
			return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_userupdate
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url	
	
def getNotificationSetting():
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
		
	url_notificationSetting = url + 'ws/notifications/settings' 
	headers = {'Content-Type': 'plain/text', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'plain/text', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_notificationSetting, 'GET', headers=headers)
		content = contentb.decode()
		if '<error>' in content:
			err=xdoc.getElementsByTagName('message')
			return 'error', err[0].childNodes[0].nodeValue
		if response['status'] == '200':
			return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_notificationSetting
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url
	
def encode_notification_params( params):
	param_list = ['NOTIFY_ENABLE', 'NOTIFY_EVENTS', 'NOTIFY_CHANNELS' ]

	paramDict={}
	for p in param_list:
		paramDict[p] = p
	lines = []
	lines.append('<NotificationParams>');
	for name in params:
		try:
			if paramDict[name] == None:
				pass
		except KeyError:
			print ( _getmsg("notification_parameter_name_invalid").format(name))                     
			exit();
		lines.append('<AppParam><id>%s</id><value>%s</value></AppParam>' %(name, params[name]))
	lines.append('</NotificationParams>');
	return '\n'.join (lines)

def registerNotification(jobId, params):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')

	if len(params) == 0:
		params['NOTIFY_ENABLE'] = 'Y'
	body = encode_notification_params(params)
	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Content-Length': str(len(body)), 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Content-Length': str(len(body)), 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	url_register = url + 'ws/notifications/register?workloadId='  + jobId
	try:
		response, contentb = http.request(url_register, 'POST', body=body, headers=headers)
		content = contentb.decode()
		xdoc=minidom.parseString(content)
		if '<error>' in content:
			err=xdoc.getElementsByTagName('message')
			return 'error', err[0].childNodes[0].nodeValue
		if response['status'] == '200':
			return 'ok', content
		else:
			return 'error', _getmsg("failed_connect_wsurl") % url_register
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url


def getPseudoFlowInstances(flowid, flowname, username, flowstate):
	url, token = getToken()

	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)

	if ((x509Flag == False) & (len(token) <= 0)):
		return 'error', _getmsg("must_logon_pac")

	http = getHttp(url, x509Flag)
	if ((x509Flag == True) & (len(token) <= 0)):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')

	url_flows = url + 'ws/flow/instances'
	args = {"id":flowid, "flowname":flowname, "username":username, "state":flowstate}
	first = True
	for key, val in args.iteritems():
		if not val:
			continue
		if first:
			url_flows = url_flows+ "?" + key + "=" + val
			first = False
		else:
			url_flows = url_flows+ "&" + key + "=" + val

	headers = {'Content-Type': 'application/xml', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/xml', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_flows, 'GET', headers=headers)
		content = contentb.decode()
		if response['status'] == '200':
			return 'ok', content
		else:
			xdoc = minidom.parseString(content)
			message = xdoc.getElementsByTagName('message')
			return 'error', message[0].childNodes[0].nodeValue
	except (AttributeError, ExpatError):
		return 'error', _getmsg("connect_ws_err") % url_flows

def doFlowInstanceAction(action, varlist, flowid):
	url, token = getToken()
			
	x509Flag, keypemfile, certpemfile = checkX509PEMCert(url)
	
	if ( (x509Flag == False) & (len(token) <= 0) ):
		return 'error', _getmsg("must_logon_pac")
	
	http = getHttp(url,x509Flag)
	if ( (x509Flag == True) & (len(token) <= 0) ):
		# X509Flag is True and token is empty, then add the key/cert files into http request.
		http.add_certificate(keypemfile, certpemfile, '')
	
	url_flowaction = url + 'ws/flow/instances/' + action
	data = {'ids': flowid,'variables': varlist}
	headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'platform_token=' + token, 
		'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()} 
	if (token.startswith('OAuth2')):
		user, authtoken = checkOAuthToken(token)
		headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Auth-User': user, 'Authorization': 'Bearer ' + authtoken, 
			'Accept': 'application/xml', 'Accept-Language': getSysLocale().replace("_", "-").lower()}

	try:
		response, contentb = http.request(url_flowaction, 'POST', urllib.urlencode(data), headers=headers)
		content = contentb.decode()
		xdoc = minidom.parseString(content)
		message = xdoc.getElementsByTagName('message')
							
		if response['status'] == '200':
			return 'ok', message[0].childNodes[0].childNodes[0].nodeValue
		else:
			return 'error', message[0].childNodes[0].nodeValue
	except (AttributeError, ExpatError):
		return 'error', _getmsg("ws_notready_url") % url_flowaction 

def main(argv):
	"""
	url=input("URL:")
	if len(url) == 0:
		print ( _getmsg("wrong_url_format") )
		return
	u=input("Username:")
	
	if len(u) == 0:
		print ( _getmsg("empty_username_err") )
		return
	p=getpass.getpass()
	if len(p) == 0:
		print ( _getmsg("password_cannot_empty") )
		return
	logon(url, u, p)
	"""
	getJobInfo('356')
	
	downloadJobFiles('353', 'c:\\webservice\\350' )
	"""
	JobDict={}
	
	JobDict[APP_NAME]='FLUENT:FLUENT_WEB'                 #format: "app_type:app_name"
	JobDict['PARAMS']= {'JOB_NAME': 'FF_20100329',
	                    'RELEASE': '6.3.26',
			    'CONSOLE_SUPPORT': 'No'}
	JobDict['INPUT_FILES']={ 'FLUENT_JOURNAL':'C:\\portal_demo\\fluent\\fluent-test.jou,upload',
	                         'CAS_INPUT_FILE':'C:\\portal_demo\\fluent\\fluent-test.cas.gz,upload'}
	JobDict['RETURN_FILES']={ 'TARGET_DIR':'C:\jobResults', 'FILES':['*.zip', '*.txt']}
	status, message = submitJob(JobDict)
	print('status =' + status)
	print('message =' + message)
	"""
	
if __name__ == "__main__":
	main(sys.argv[1:])

