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

class ComponentStop(object):

    def on_get(self, req, resp):
        resp.status = HTTP_OK

def is_service_up():
    cmd = "pidof asd"
    ret = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=True)
    out, err = ret.communicate()
    status = ret.returncode

    if status:
        return False

    return True

def create_mesh_config(mesh_addrs, mesh_port):
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

            else:
                output_file.write(filedata[n])
                continue

    log.debug("Mesh config created")
    return

def create_multicast_config(multi_addr, multi_port):
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

services = {
	'register_udf': RegisterUDF(),
	'unregister_udf': UnRegisterUDF(),
	'component_stop' : ComponentStop(),
       }


args = ["etcdip", "svc_label", "svc_idx", "mode","ip", "port"]

etcd_server_ip = None
service_type   = None
service_idx    = None
mode           = None
ip_addr        = None
port_to_use    = None

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


if mode != '':
    FILE_IN_USE = MODDED_FILE
    if mode == 'mesh':
        create_mesh_config(ip_addr, port_to_use)

    elif mode == 'multicast':
        create_multicast_config(ip_addr, port_to_use)

if etcd_server_ip == '' and service_type == '' and service_idx == '':
    etcd_server_ip = "127.0.0.1"
    service_type   = "AS_Server"
    service_idx    = 1

print (etcd_server_ip, service_type, service_idx, mode, ip_addr, port_to_use)

# Creating AsdManager instance
component_mgr  = ComponentMgr(etcd_server_ip, service_type, service_idx, VERSION)
