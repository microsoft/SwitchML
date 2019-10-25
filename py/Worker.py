######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


class Worker(object):

    def __init__(self, mac, ip, front_panel_port, lane, speed, fec):
        self.mac = mac
        self.ip = ip
        self.front_panel_port = front_panel_port
        self.lane = lane
        self.speed = speed
        self.fec = fec

        # things not set by default
        self.rid = None
