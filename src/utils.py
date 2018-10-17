import os
import json
import shutil
import subprocess
import logging

FORMAT = '%(name)s %(asctime)-15s - %(levelname)s -%(message)s'
logging.basicConfig(format=FORMAT, filename="/var/log/aerospike/hyc_asd_mgr.log",
                filemode='a', level=logging.DEBUG)
log = logging

def dump_data(payload):

    return json.dumps(payload)

def load_data(payload):

    return json.loads(payload)
