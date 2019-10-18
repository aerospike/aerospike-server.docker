#!/usr/bin/env python
#
# Copyright 2018 Cachebox, Inc. All rights reserved. This software
# is property of Cachebox, Inc and contains trade secrects,
# confidential & proprietary information. Use, disclosure or copying
# this without explicit written permission from Cachebox, Inc is
# prohibited.
#
# Author: Cachebox, Inc (sales@cachebox.com)
#
import sys
import os
import time
import subprocess
import falcon
import copy
from threading import Lock, Thread

from ha_lib.python.ha_lib import *
from utils import *

#
# Global services dictionary.
# Any new method to be supported must be added into this dictionary.
#
COMPONENT_SERVICE = "aerospike"
VERSION           = "v1.0"
HTTP_OK           = falcon.HTTP_200
HTTP_ACCEPTED     = falcon.HTTP_202
HTTP_UNAVAILABLE  = falcon.HTTP_503
HTTP_ERROR        = falcon.HTTP_400
UDF_DIR           = "/etc/aerospike"

MESH_CONFIG_FILE       = "/etc/aerospike/aerospike_mesh.conf"
MULTICAST_CONFIG_FILE  = "/etc/aerospike/aerospike_multicast.conf"
MODDED_FILE            = "/etc/aerospike/modded.conf"
FILE_IN_USE            = None

#
# String Markers inserted in config file
#
CLEAN_DISKS_MARKER = "CLEAN_DISKS"
DIRTY_DISKS_MARKER = "DIRTY_DISKS"
MEMORY_PER_NS_MARKER = "MEMORY_PER_NS"
MWC_MEMORY_MARKER = "MWC_MEMORY"
PWQ_MEMORY_MARKER = "PWQ_MEMORY"

memory_config = {
    "lite" : {
        "max-write-cache" : 256*1024*1024,
        "post-write-queue" : 64,
        "memory_per_ns": 3,
        "system" : 1,
    },
    "standard": {
        "max-write-cache" : 256*1024*1024,
        "post-write-queue" : 256,
        "memory_per_ns": 4,
        "system" : 2,
    },
    "performance": {
        "max-write-cache" : 512*1024*1024,
        "post-write-queue" : 1024,
        "memory_per_ns": 8,
        "system" : 4,
    },
}

MIGRATION_PROFILES = tuple(memory_config.keys())
DEFAULT_PROFILE = "lite"
SELECTED_PROFILE = DEFAULT_PROFILE


def is_service_up():
    cmd = "pidof asd"
    ret = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=True)
    out, err = ret.communicate()
    status = ret.returncode

    if status:
        log.error("is_service_up failed!!!")
        log.error("stdout: %s" %out)
        log.error("stderr: %s" %err)
        log.error("status: %s" %status)
        return False

    return True

def get_memory_config(unused):
    return copy.copy(memory_config[SELECTED_PROFILE])

def get_disks_for_config(no_disks):
    disks = ['sdc', 'sdd', 'sde', 'sdf', 'sdg', 'sdh', 'sdi', 'sdj', 'sdk', 'sdl']
    dev_str = "\t\tdevice /dev/"

    no_disks = int(no_disks)

    disks_to_use = disks[:no_disks]
    clean = disks_to_use[:(no_disks/2)]
    dirty = disks_to_use[(no_disks/2):]

    clean_str = dirty_str = ""
    for d in clean:
        tmp_str = dev_str + d + "\n"
        clean_str = clean_str + tmp_str

    for d in dirty:
        tmp_str = dev_str + d + "\n"
        dirty_str = dirty_str + tmp_str

    return (clean_str, dirty_str)

def create_mesh_config(mesh_addrs, mesh_port, memory, disks):

    if not memory:
        log.debug("Memory not set using default")
        memory = 10
    mem_config = get_memory_config(int(memory))

    if not disks:
        log/debug("Disk not set using default")
        disks = 2
    (clean_str, dirty_str) = get_disks_for_config(disks)

    with open(MESH_CONFIG_FILE, 'r') as input_file, open(MODDED_FILE, 'w+') as output_file:
        filedata = input_file.readlines()

        update_port = 0
        for n, line in enumerate(filedata):
            if line.startswith("#"):
                output_file.write(filedata[n])
                continue

            elif line.strip().startswith("mode mesh"):
                update_port = 1
                output_file.write(filedata[n])
                continue

            elif line.strip().startswith("port") and update_port:
                filedata[n] = "\t\tport %s\n" %mesh_port
                output_file.write(filedata[n])
                for ip in mesh_addrs.split(","):
                    new_str = "\t\tmesh-seed-address-port %s %s\n" %(ip, mesh_port)
                    output_file.write(new_str)

                update_port = 0
                continue

            elif line.strip().startswith(CLEAN_DISKS_MARKER):
                output_file.write(clean_str)
                continue

            elif line.strip().startswith(DIRTY_DISKS_MARKER):
                output_file.write(dirty_str)
                continue

            elif line.strip().startswith(MEMORY_PER_NS_MARKER):
                new_str = "\tmemory-size %sG\n" %mem_config["memory_per_ns"]
                output_file.write(new_str)
                continue

            elif line.strip().startswith(MWC_MEMORY_MARKER):
                new_str = "\t\tmax-write-cache %s\n" %mem_config["max-write-cache"]
                output_file.write(new_str)
                continue

            elif line.strip().startswith(PWQ_MEMORY_MARKER):
                new_str = "\t\tpost-write-queue %s\n" %mem_config["post-write-queue"]
                output_file.write(new_str)
                continue

            else:
                output_file.write(filedata[n])
                continue

    log.debug("Mesh config created")
    return

def create_multicast_config(multi_addr, multi_port, memory, disks):
    if not memory:
        log.debug("Memory not set using default")
        memory = 10
    mem_config = get_memory_config(int(memory))

    if not disks:
        log.debug("Disk not set using default")
        disks = 2
    (clean_str, dirty_str) = get_disks_for_config(disks)

    with open(MULTICAST_CONFIG_FILE, 'r') as input_file, open(MODDED_FILE, 'w+') as output_file:
        filedata = input_file.readlines()

        update_port = 0
        for n, line in enumerate(filedata):
            if line.startswith("#"):
                output_file.write(filedata[n])
                continue
            elif line.strip().startswith("multicast-group"):
                filedata[n] = "\t\tmulticast-group %s\n" %multi_addr
                output_file.write(filedata[n])
                update_port = 1
                continue
            elif line.strip().startswith("port") and update_port:
                filedata[n] = "\t\tport %s\n" %multi_port
                output_file.write(filedata[n])
                update_port = 0
                continue
            elif line.strip().startswith(CLEAN_DISKS_MARKER):
                output_file.write(clean_str)
                continue
            elif line.strip().startswith(DIRTY_DISKS_MARKER):
                output_file.write(dirty_str)
                continue
            elif line.strip().startswith(MEMORY_PER_NS_MARKER):
                new_str = "\tmemory-size %sG\n" %mem_config["memory_per_ns"]
                output_file.write(new_str)
                continue
            elif line.strip().startswith(MWC_MEMORY_MARKER):
                new_str = "\t\tmax-write-cache %s\n" %mem_config["max-write-cache"]
                output_file.write(new_str)
                continue
            elif line.strip().startswith(PWQ_MEMORY_MARKER):
                new_str = "\t\tpost-write-queue %s\n" %mem_config["post-write-queue"]
                output_file.write(new_str)
                continue
            else:
                output_file.write(filedata[n])
                continue

    log.debug("Multicast config created")
    return

def start_asd_service():
    if FILE_IN_USE:
        cmd = "/usr/bin/asd --config-file %s" %FILE_IN_USE
    else:
        cmd = "/usr/bin/asd"

    log.debug("Executing %s" %cmd)
    return os.system(cmd)

def is_service_avaliable():
    cmd = "aql -c \"show namespaces\""
    ret = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=True)
    out, err = ret.communicate()
    status = ret.returncode
    if status:
        log.error("is_service_available failed!!!")
        log.error("stdout: %s" %out)
        log.error("stderr: %s" %err)
        log.error("status: %s" %status)
        return False

    return True

class RegisterUDF(object):

    def on_post(self, req, resp):

        log.debug("In RegisterUDF")
        data = req.stream.read()
        data = data.decode()

        # We may be running Register UDF just after starting the docker
        # where asd service may not been started yet, wait for some time
        retry_cnt = 12
        while retry_cnt:
           if is_service_avaliable():
              break
           else:
              time.sleep(5)
              retry_cnt = retry_cnt - 1
              log.debug("Retrying register_udf. Aerospike daemon is still not up.")

        if retry_cnt == 0:
           resp.status = HTTP_UNAVAILABLE
           log.debug("UDF apply failed because Aerospike daemon is not running.")
           return

        data_dict = load_data(data)
        udf_file  = data_dict['udf_file']
        log.debug("Register UDF file : %s" %udf_file)
        udf_path = '%s/%s' %(UDF_DIR, udf_file)
        log.debug("Register UDF path : %s" %udf_path)

        if os.path.isfile(udf_path) == False:
            log.debug("Register UDF file not present: %s" %udf_path)
            resp.status = HTTP_ERROR
            return

        cmd = "aql -c \"register module '%s'\"" %udf_path
        log.debug("Register UDF cmd is : %s" %cmd)
        ret = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=True)
        out, err = ret.communicate()
        status = ret.returncode
        if status:
            log.error("Error in registering udf with aerospike cmd: %s" %cmd)
            resp.status = HTTP_ERROR
            return

        resp.status = HTTP_OK
        log.info(" UDF: %s registered successfully." %udf_file)
        return

class UnRegisterUDF(object):

    def on_post(self, req, resp):

        log.debug("In UnRegisterUDF")
        data = req.stream.read()
        data = data.decode()

        data_dict = load_data(data)
        udf_file  = data_dict['udf_file']
        log.debug("UnRegister UDF: %s" %udf_file)
        cmd = "aql -c \"remove module %s\"" %udf_file
        log.debug("UnRegister UDF cmd : %s" %cmd)
        ret = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=True)
        out, err = ret.communicate()
        status = ret.returncode
        #Ignore error case for now
        if status:
            resp.status = HTTP_OK

        resp.status = HTTP_OK

#
# ComponentMgr Class:
# Creates an instance of halib with itself.
# Mgr is started at first component_start
#
class ComponentMgr(Thread):
    def __init__(self, etcd_server_ip, service_type, service_idx, VERSION,
                   lease_interval = 120):

        Thread.__init__(self)
        self.setDaemon(True)
        self.started = False
        self.failure_retry = 3
        services["component_start"] = self

        self.halib = HALib(etcd_server_ip, VERSION, service_type, services,
                                service_idx)
        log.debug("HALib started")

    def on_post(self, req, resp, doc):
        if not self.started:
            log.info("Starting service")
            ret = start_asd_service()
            if ret:
                log.error("Failed to start asd service")
                resp.status = HTTP_UNAVAILABLE
                return

            self.start()
            resp.status  = HTTP_ACCEPTED
            return

        else:
            #Nothing to do. Return Success
            resp.status  = HTTP_OK
            log.info("component_start received again!!!")
            pass

    def on_get(self, req, resp):
        log.debug("In get comp_start")

        if not is_service_up():
            st_msg = "Aerospike service down. Component_start failed!!"
            log.error(st_msg)
            resp.body = json.dumps({"status": 2, "status_msg": st_msg})

        if is_service_avaliable():
            st_msg = "Aerospike service started successfully"
            resp.body = json.dumps({"status": 1, "status_msg": st_msg})
        else:
            st_msg = "Aerospike service start in progress"
            resp.body = json.dumps({"status": 0, "status_msg": st_msg})

        resp.status = HTTP_OK

    def run(self):
        log.debug("Starting hb thread")
        st = is_service_avaliable()
        while not st:
            log.debug("Waiting for asd service to come up")
            time.sleep(10)
            st = is_service_avaliable()

        self.started = True
        log.debug("Aerospike started and running!!")

        lease_duration = self.halib.get_health_lease()
        hb_update_duration = lease_duration / 4
        while (True):
            if (not is_service_up() and self.failure_retry > 0):
                log.error("service not up!! Retry cnt: %s" %self.failure_retry)
                self.failure_retry -= 1
                time.sleep(hb_update_duration)
                continue

            if (not is_service_avaliable() and self.failure_retry > 0):
                log.error("service not available!! Retry cnt: %s" %self.failure_retry)
                self.failure_retry -= 1
                time.sleep(hb_update_duration)
                continue

            if (self.failure_retry == 0):
                log.error("Failure_retry count exhausted!! Will not renew lease")
                break

            self.failure_retry = 3
            self.halib.set_health(True)
            log.info("Updated health lease")
            time.sleep(hb_update_duration)

        log.error("asd health is down")
        self.started = False
        log.error("%s service is down" %COMPONENT_SERVICE)
        self.halib.set_health(False)
        return

class ComponentStop(object):

    def on_get(self, req, resp):
        resp.status = HTTP_OK


services = {
	'register_udf': RegisterUDF(),
	'unregister_udf': UnRegisterUDF(),
	'component_stop' : ComponentStop(),
       }


args = ["etcdip", "svc_label", "svc_idx", "mode","ip", "port", "memory", "disks"]

etcd_server_ip = None
service_type   = None
service_idx    = None
mode           = None
ip_addr        = None
port_to_use    = None
memory         = None
disks          = None
profile        = DEFAULT_PROFILE

for arg in sys.argv:
    if arg.startswith("etcdip"):
        etcd_server_ip = arg.split("=")[1]
        continue

    elif arg.startswith("svc_label"):
        service_type = arg.split("=")[1]
        continue

    elif arg.startswith("svc_idx"):
        service_idx = arg.split("=")[1]
        continue

    elif arg.startswith("mode"):
        mode = arg.split("=")[1]
        continue

    elif arg.startswith("ip"):
        ip_addr = arg.split("=")[1]
        continue

    elif arg.startswith("port"):
        port_to_use = arg.split("=")[1]
        continue

    elif arg.startswith("memory"):
        memory = arg.split("=")[1]
        continue

    elif arg.startswith("disks"):
        disks = arg.split("=")[1]
        continue

    elif arg.startswith("migration_profile"):
        profile = arg.split("=")[1].lower()
        continue

SELECTED_PROFILE = profile if profile in MIGRATION_PROFILES else DEFAULT_PROFILE
log.info("Selected migration config %s" % (SELECTED_PROFILE))

if mode != '':
    FILE_IN_USE = MODDED_FILE
    if mode == 'mesh':
        create_mesh_config(ip_addr, port_to_use, memory, disks)

    elif mode == 'multicast':
        create_multicast_config(ip_addr, port_to_use, memory, disks)

if etcd_server_ip == '' and service_type == '' and service_idx == '':
    etcd_server_ip = "127.0.0.1"
    service_type   = "AS_Server"
    service_idx    = 1

print (etcd_server_ip, service_type, service_idx, mode, ip_addr, port_to_use,
        memory, disks, SELECTED_PROFILE)

# Creating AsdManager instance
component_mgr  = ComponentMgr(etcd_server_ip, service_type, service_idx, VERSION)
