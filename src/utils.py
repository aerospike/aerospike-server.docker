import os
import json
import shutil
import subprocess
import glog as log
from glog import GlogFormatter
import logging
import logging.handlers

def hdm_log_setup(log_file, log_level):
    fh = logging.handlers.RotatingFileHandler(
        filename=log_file, mode='a', maxBytes=10<<20, backupCount=5)
    fh.setFormatter(GlogFormatter())
    log.logger.addHandler(fh)
    log.setLevel(log_level)

hdm_log_setup('/var/log/aerospike/hyc_asd_mgr.log', logging.DEBUG)

def dump_data(payload):

    return json.dumps(payload)

def load_data(payload):

    return json.loads(payload)
