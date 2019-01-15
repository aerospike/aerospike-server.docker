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

config_high = { "max-write-cache" : 536870912,
                "post-write-queue" : 2048,
                "memory_per_ns" : 10,
                "system" : 4
            }

config_low  = { "max-write-cache" : 268435456,
                "post-write-queue" : 1024,
                "memory_per_ns" : 2,
                "system" : 1,
            }

def is_service_up():
    cmd = "pidof asd"
    ret = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=True)
    out, err = ret.communicate()
    status = ret.returncode

    if status:
        return False

    return True

def get_memory_config(memory, disks):

    log.debug("Total: %s" %memory)
    if memory >= 10 and memory < 20:
        config = config_low

    elif memory >= 20:
        config = config_high

    min_req    = disks * (config['max-write-cache'] >> 20) / 1024
    min_req    = min_req + disks * (config['post-write-queue'] >> 10) + config['system']
    avail_mem  = memory - min_req

    log.debug("min_req: %s avail_mem: %s" %(min_req, avail_mem))
    if avail_mem > 2:
        config['memory_per_ns'] = avail_mem / 2
        log.debug("memory_per_ns: %s" %config['memory_per_ns'])

    return config

def get_disks_for_config(no_disks):
    disks = ['sdb', 'sdc', 'sdd', 'sde', 'sdf', 'sdg', 'sdh', 'sdi', 'sdj', 'sdk']
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
    mem_config = get_memory_config(int(memory), int(disks))

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
    mem_config = get_memory_config(int(memory), int(disks))

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
            resp.status = HTTP_ERROR

        resp.status = HTTP_OK

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
        services["component_start"] = self

        self.halib = HALib(etcd_server_ip, VERSION, service_type, services,
                                service_idx)
        log.debug("HALib started")

    def on_post(self, req, resp, doc):
        if not self.started:
            ret = start_asd_service()
            if ret:
                log.debug("Failed to start asd service")
                resp.status = HTTP_UNAVAILABLE
                return

            self.started = True
            self.start()
            log.debug("Waiting for asd service to come up")
            time.sleep(10)
            resp.status  = HTTP_OK

        else:
            #Nothing to do. Return Success
            resp.status  = HTTP_OK
            pass

    def run(self):
        while (is_service_up()):
            self.halib.set_health(True)
            log.debug("Updated health lease")
            time.sleep(self.halib.get_health_lease()/ 3)

        log.debug("asd health is down")
        self.started = False
        log.debug("%s service is down" %COMPONENT_SERVICE)
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
        memory, disks)

# Creating AsdManager instance
component_mgr  = ComponentMgr(etcd_server_ip, service_type, service_idx, VERSION)
