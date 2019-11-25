#!/usr/bin/env python
######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import os
import sys
import signal
import argparse
import logging
from pprint import pprint, pformat

import rlcompleter
import readline

# add BF Python to search path
sys.path.append(os.environ['SDE_INSTALL'] + "/lib/python2.7/site-packages/tofino")
#sys.path.append("/u/jacob/arista/python/tofino-9.0.0")

# Import BFRT GRPC stuff
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

# set up options
argparser = argparse.ArgumentParser(description="SwitchML controller.")
argparser.add_argument('--grpc_server', type=str, default='localhost', help='GRPC server name/address')
argparser.add_argument('--grpc_port', type=int, default=50052, help='GRPC server port')
argparser.add_argument('--program', type=str, default='switchml', help='P4 program name')
args = argparser.parse_args()

# configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('SwitchML')
#if not len(logger.handlers):
#    logger.addHandler(logging.StreamHandler())

logger.info("SwitchML controller starting up...")
logger.info("""\n
******************************
*** Hit Control-\ to exit! ***
******************************
""")

# connect to GRPC server
logger.info("Connecting to GRPC server {}:{} and binding to program {}...".format(args.grpc_server, args.grpc_port, args.program))
c = gc.ClientInterface("{}:{}".format(args.grpc_server, args.grpc_port), 0, 0, is_master=False)
c.bind_pipeline_config(args.program)

# get all tables for program
bfrt_info = c.bfrt_info_get(args.program)


#
# configure job
#

 # Print overall list of tables
logger.info(pformat(bfrt_info.table_dict))


# mac, ip, and udp port number that switch will respond to for SwitchML
# port number is associated with a mask for use with legacy SwitchML code
switch_mac           = "06:00:00:00:00:01"
switch_ip            = "198.19.200.200"
switch_udp_port      = 0xbee0
switch_udp_port_mask = 0xfff0
switch_mgid          = 1234

# set_up_job(switch_ip, switch_mac, switch_udp_port, switch_udp_port_mask, switch_mgid,
#            [Worker(mac="b8:83:03:73:a6:a0", ip="198.19.200.49", front_panel_port= 9, lane=0, speed=100, fec='none'),
#             Worker(mac="b8:83:03:74:01:8c", ip="198.19.200.50", front_panel_port=10, lane=0, speed=100, fec='none')])

# setup job for model
from Job import Job
from Worker import Worker
job = Job(gc, bfrt_info,
          switch_ip, switch_mac, switch_udp_port, switch_udp_port_mask, switch_mgid,
          [Worker(mac="b8:83:03:73:a6:a0", ip="198.19.200.49", front_panel_port=1, lane=1, speed=10, fec='none'),
           Worker(mac="b8:83:03:74:01:8c", ip="198.19.200.50", front_panel_port=1, lane=0, speed=10, fec='none')])

# Done with configuration
#logger.info("Switch configured! Hit Ctrl-\ to exit.")
logger.info("Switch configured successfully!")


# start CLI
job.run()

# exit (bug workaround)
logger.info("Exiting!")

# flush logs, stdout, stderr
logging.shutdown()
sys.stdout.flush()
sys.stderr.flush()
        
# exit (bug workaround)
os.kill(os.getpid(), signal.SIGTERM)

