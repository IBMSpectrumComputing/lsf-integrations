#!/bin/bash
#**************************************************************************
#  Copyright International Business Machines Corp, 2018. 
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#**************************************************************************

#VNCGeomerty=1024x768   # Uncomment this option to overwrite the same value which is user defined in pmc.conf 

################### Log function ################################
#define the log file, overwrite the default, see ${GUI_CONFDIR}/application/LOG_FUNC
. ${GUI_CONFDIR}/application/COMMON
. ${GUI_CONFDIR}/application/LOG_FUNC

LOG_LEVEL=2   # 0 - ERROR, 1 - WARN, 2 - INFO, 3 - DEBUG

################### Environment variables ######################
# Env variables section
# Remote application name
app_name="${app_name}"
# User who will connect to the remote server
user_name="${user_name}"
# The server which has the application installed
# host_name="${host_name}"
# LSF job id
job_id="${job_id}"
# LSF user job repository
job_repo="${job_repo}"
# The file to be opened on the remote server with the specified application
cmd_file="${cmd_file}"
# Windows, Linux or any is OK
platform="${RUNNING_OS}"
# Password of the windows server to run the application
user_pwd="${password}"
# FOR ICON VIEW - Application install path (with parameters) on Windows server
win_app_cmd="${WIN_APP_CMD}"
# FOR DATA PROCESS - Application install path (with parameters and input file) on Windows server
win_app_pre_post_cmd="${WIN_PRE_POST_CMD}"
# FOR ICON VIEW -  Application install path (with parameters) on Linux server
linux_app_cmd="${LINUX_APP_CMD}"
# FOR DATA PROCESS - Application install path (with parameters and input file) on Linux server
linux_app_pre_post_cmd="${LINUX_PRE_POST_CMD}"
# For windows to mount user shared path (work directory) from Linux NFS server
smb_shared_path="${SMB_SHARED_PATH}"
# To keep the user vnc session, options "Yes" - keep, "No" - not keep.
#keep_user_vnc_session="${KEEP_USER_SESSION}"
keep_user_vnc_session="Yes"
# If the Windows console required to run application
win_console_required="${WIN_CONSOLE_REQUIRED}"
# If the application is running on PAC master
run_on_pac_master="${RUN_ON_PAC_MASTER}"

# System variables section, do not change
vnc_script_top=${GUI_CONFDIR}/application/vnc/app_process
# For Linux, 2 scripts are used, script 1 is to create a VNC session, script 2 is to open the application in the new created VNC session
linux_startVNC_script=${vnc_script_top}/linux_appprocess_startVncSession.sh
linux_open_app_script=${vnc_script_top}/linux_open_app.sh
# For Windows, one script is used to create the user session and open application
win_startVNC_script=${vnc_script_top}/win_appprocess_startVncSession.sh
gen_encryptVNCPasswd_script=${vnc_script_top}/gen_encryptVNCPasswd.sh
session_conf="${GUI_CONFDIR}/host_session.conf"
platform_windows="Windows"
platform_linux="Linux"
platform_windows_arch="NTX64"
platform_linux_arch="X86_64"

################### Functions ##########################
function linux_run_app() {
    if [ x"$cmd_file" != "x" ]; then
        # Check if this file exist in the remote Linux host
        result=`lsrun -m $exe_host ls "$cmd_file" 2>&1`
        if [ $? -ne 0 ]; then
            LOG_ERROR "File \"$cmd_file\" verify failed on host \"$exe_host\", cause: $result."
            exit 1
        fi
        
        #if [ "$linux_app_pre_post_cmd" = "undefined" -o x"$linux_app_pre_post_cmd" = "x" ]; then
        if [ "$linux_app_cmd" = "undefined" -o x"$linux_app_cmd" = "x" ]; then
            LOG_ERROR "Linux application command is not defined for opening an input File."
            exit 1;
        fi
        #linux_app_cmd="$linux_app_pre_post_cmd"
        LOG_DEBUG "linux_app_cmd is ready: $linux_app_cmd"
    else
        if [ "$linux_app_cmd" = "undefined" -o x"$linux_app_cmd" = "x" ]; then
            LOG_ERROR "Linux application command is not defined."
            exit 1;
           fi
    fi    
    
    linux_app_cmd=`echo $linux_app_cmd | sed "s#\"#\'#g"`
    
    vnc_info_file_dir="${job_repo}/.vnc/$exe_host/$app_name"
    LOG_DEBUG "Creating $vnc_info_file_dir"
    if [ ! -d "$vnc_info_file_dir" ]; then
        mkdir -p "$vnc_info_file_dir"
        LOG_DEBUG "Created "
    else    
        LOG_DEBUG "Directory exists"
    fi
    
    chmod 777 $vnc_info_file_dir > /dev/null 2>&1

    vnc_info_file="$vnc_info_file_dir/vnc.session";

    reuse=0

    if [ -f "${vnc_info_file}" ]; then
        
        SID=`grep "^[   ]*SID=" $vnc_info_file | sed -e "s/^.*=//g"`
        PID=`grep "PID=" ${vnc_info_file} |cut -d "=" -f2`

        if [ "${exe_host}" = "" ]; then
            vinfo=$(ps -q ${PID} -o pid=)
        else
            vinfo=$( lsrun -m ${exe_host} ps -q ${PID} -o pid= )
        fi
        
        if [ -n "$vinfo" ]; then
            LOG_DEBUG "$vnc_info_file exists and it's alive, return this session info for reuse"
            vncPort=`cat ${vnc_info_file} | grep port= | awk -F = '{print $2}'`
            vncPassword=`cat ${vnc_info_file} | grep password= | awk -F = '{print $2}'`
            repository=`dirname ${vnc_info_file}`
            screen_width=`cat ${vnc_info_file} | grep width= | awk -F = '{print $2}'`
            screen_height=`cat ${vnc_info_file} | grep height= | awk -F = '{print $2}'`
            encryptPwd=`xxd -ps ${repository}/.vnc.passwd`
            LOG_DEBUG "VNC Session info: $platform;$user_name;${exe_host};${vncPort};${encryptPwd};${vncPassword};${screen_width};${screen_height};${SID};${PID};${vnc_info_file}"
            vnc_info="${exe_host};${vncPort};${encryptPwd};${vncPassword};${screen_width};${screen_height};${SID};${PID};${vnc_info_file}"
            echo "$platform;$user_name;${exe_host};${vncPort};${encryptPwd};${vncPassword};${screen_width};${screen_height};${SID};${PID};${vnc_info_file}"
            reuse=1
        fi
    fi

    if [ $reuse -eq 0 ]; then
        LOG_DEBUG "No exsiting vnc session available, creating new session..."
        vnc_info=$( $linux_startVNC_script $vnc_info_file $user_name $exe_host $keep_user_vnc_session $VNCGeomerty )
        if [ $? -ne 0 -o -z "$vnc_info" ]; then
            LOG_ERROR "Failed to start VNC server on Linux host \"$exe_host\": $vnc_info"
            exit 203
        fi
        LOG_DEBUG "VNC session created: $platform;$user_name;$vnc_info"
        echo "$platform;$user_name;$vnc_info"
    fi

    LOG_DEBUG "Starting application $linux_app_cmd ..."
    linux_app_cmd="`echo $linux_app_cmd | sed 's#\\"#\\\\\\"#g'`"
    display_settings=`echo $vnc_info | awk -F";" '{print $7}'`
    LOG_DEBUG "Calling [$linux_open_app_script $user_name $linux_app_cmd $exe_host $display_settings $vnc_info_file $cmd_file"
    nohup $linux_open_app_script $user_name $linux_app_cmd $exe_host $display_settings $vnc_info_file $cmd_file > /dev/null 2>&1 &
}

function win_run_app() {
    if [ x"$cmd_file" != "x" ]; then            
        if [ "$win_app_pre_post_cmd" = "undefined" -o x"$win_app_pre_post_cmd" = "x" ]; then
            LOG_ERROR "Windows application command is not defined for opening a input File."
            exit 1;
        fi
        win_app_cmd="$win_app_pre_post_cmd"
    else
        if [ "$win_app_cmd" = "undefined" -o x"$win_app_cmd" = "x" ]; then
            LOG_ERROR "Windows application command is not defined."
            exit 1;
           fi
    fi
        
    if [ x"$user_pwd_tmp_file" == "x" ]; then
        LOG_ERROR "Failed to generate Windows password file \"$user_pwd_tmp_file\" in \"$app_name\"."
        exit 1
    fi
    
    pwd=`cat $user_pwd_tmp_file`
    if [ x"$pwd" == "x" ]; then
        LOG_ERROR "The Windows password is not set for the Windows user \"$user_name\". Select System & Settings>Settings>Windows Password for LSF Hosts and configure the user password."
        exit 1
    fi
	
	# Generate a 8 bit random password
	# vnc_passwd=`cat /proc/sys/kernel/random/uuid | awk -F- '{print $1}'`
	# encry_passwd=`"$gen_encryptVNCPasswd_script" "$vnc_passwd"`
    #if [ $? != 0 ]; then
    #    exit 1
    #fi
	
	vnc_info_file=${job_repo}/"$user_name"_vncsession.win
    vnc_info=`"$win_startVNC_script" "$vnc_info_file" "$user_name" "$job_id" "$exe_host" "$win_app_cmd" "$cmd_file" "$smb_shared_path" "$win_console_required" "$keep_user_vnc_session" "$pwd" "$VNCGeomerty"`
	if [ $? != 0 ]; then
        LOG_ERROR "Failed to start VNC server on host \"$exe_host\" by user \"$user_name\", cause: $result"
        exit 1
    fi
	
	LOG_DEBUG "The vnc_info value is $vnc_info"
    echo "$platform;$user_name;$vnc_info"	
}

function checkWinMaxSession() {
    host="$1"
    if [ -f "$session_conf" ]; then
         maxRDPCount=`cat "$session_conf" | grep -v "^#" | sed 's/#.*//' | sed  -r 's/\s+//g' | grep -i "^${host}:" | sed 's/\r$//' | awk -F: '{print $2}'`
         if [ x"$maxRDPCount" = "x" ]; then
             LOG_WARN "Maximum number of active sessions has not been configured for host \"$host\" in the file $GUI_CONFDIR\"$session_conf\". Host \"$host\" will not be selected as a resource."
             exit 1
         fi
         
         # If the current user session is active, if yes, it means this user can reuse this session
         my_rdp=`lsrun -m ${host} "query session ${user_name}" | sed 's/\r$//' | grep -c \" Active \"`
         if [ $my_rdp -gt 0 ]; then
             LOG_DEBUG "The current user \"${user_name}\" session is active on host \"${host}\", reuse it."
             echo "Y"
             return
         fi
         
         activeCount=`lsrun -m ${host} "query session" | sed 's/\r$//' | grep -c \" Active \"`
         LOG_DEBUG "maxRDPCount:$maxRDPCount, host:$host, activeCount:$activeCount"
         if [ $activeCount -ge $maxRDPCount ]; then
             LOG_WARN "Active RDP session count has exceeded the maximum number of allowed connections \"$maxRDPCount\" on Windows host \"${host}\", contact Administrator to reduce the active RDP sessions."
             echo "N"
             return
         fi
    else 
        LOG_ERROR "The file \"$session_conf\" does not exist. This file is required when Remote Desktop Connection is selected in a template that launches an application."
        exit 1     
    fi
    echo "Y"
}

# dynamic select execution host by LSF
function select_exehost() {
    # select a Windows host
    if [ "$platform" = "$platform_windows" ]; then
        exe_host=`lsrun -R "type=NTX64 && defined(${app_name})" hostname | sed 's/\r$//' 2>error.log.tmp`
        if [ x"${exe_host}" = "x" ]; then
            err=`cat error.log.tmp`
            if [ x"$err" != "x" ]; then
                echo $err | grep "Failed to logon user" >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    LOG_ERROR_NOECHO "To run application \"${app_name}\", IBM Spectrum LSF Application Center requires your Windows password. The currently configured Windows password for user \"${user_name}\" is not valid. Go to the [Windows Authentication] page to specify/update your Windows password."
                    exit 200
                else
                    LOG_ERROR_NOECHO "Failed to select an LSF host to run application ${app_name}. Reason: $err."
                    echo "$err" >&2
                    exit 201
                fi
            else
                LOG_ERROR_NOECHO "No available Windows host in LSF cluster for running application ${app_name}."
                exit 202
            fi
            rm -f error.log.tmp
            exit 1
        fi
        exe_host_OK="`checkWinMaxSession "$exe_host"`"
        exclude_hosts="$exe_host"
        while [[ "$exe_host_OK" != "Y" ]]; do        
            win_hosts=`su ${user_name} -s /bin/sh -c "lshosts -w -R \"type=NTX64 && defined(${app_name}) && ncpus > 0\"" | grep -v "^HOST_NAME" | grep -i -v "$exclude_hosts" | awk '{print $1}'`
            if [ x"$win_hosts" = "x" ]; then
                exe_host_OK="N"
                break 
            fi
            for win_host in "$win_hosts"; do 
                exe_host_OK=`checkWinMaxSession "$win_host"`
                if [ "$exe_host_OK" != "Y" ]; then
                    exclude_hosts="$exclude_hosts\\|$win_host"
                    break;
                else
                    exe_host=$win_host
                fi
            done            
        done
        
        if [ "$exe_host_OK" != "Y" ]; then
            LOG_ERROR_NOECHO "No available Windows host in LSF cluster for running application ${app_name}."
             exit 202
        fi
        
    # select a Linux host    
    elif [ "$platform" = "$platform_linux" ]; then
        exe_host=`lsrun -R "type=X86_64 && defined(${app_name})" hostname | sed 's/\r$//' 2>error.log.tmp`
        if [ x"${exe_host}" = "x" ]; then
            err=`cat error.log.tmp`
            if [ x"$err" != "x" ]; then
                LOG_ERROR_NOECHO "Failed to run command on Linux host, cause: $err."
                echo "$err" >&2
                exit 203
            else
                LOG_ERROR_NOECHO "No available Linux host in LSF cluster for running application ${app_name}." 
                exit 204
            fi
            rm -f error.log.tmp
            exit 1
        fi
        LOG_DEBUG "find remote host: $exe_host "
    else
        LOG_ERROR "The ($platform) operating system is not supported. Supported operating systems are: \"$platform_windows [$platform_windows_arch], $platform_linux [$platform_linux_arch]\"" >&2
        exit 1
    fi
}

function is_windows_console_used() {
    local host=$1
    local win_user=`lsrun -m ${host} "query session" | grep '^ console.* Active'| awk '{print $2}'`
    local session_exist=`lsrun -m ${host} 'query process ${win_user} | findstr vncserver.exe' | grep '^ ${win_user}.* console.* vncserver.exe'`
    if [ x"$session_exist" != "x" ]; then 
        echo "Yes"
    else
        echo "No"
    fi    
}
################### Main ###############################
# dynamic select host by LSF
if [ "$run_on_pac_master" = "Yes" -a "$platform" = "$platform_linux" ]; then
    exe_host=`hostname -s`
else
    select_exehost
fi

if [ "$platform" = "$platform_windows" ]; then
    win_run_app
else
    LOG_DEBUG "To start on linux host: $exe_host"
    linux_run_app
fi
