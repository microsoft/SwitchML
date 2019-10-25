import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc
import sys
import os
import signal

import readline
from cmd import Cmd


# import table definitions
from GetWorkerBitmap import GetWorkerBitmap, Worker
from UpdateAndCheckWorkerBitmap import UpdateAndCheckWorkerBitmap
from CountWorkers import CountWorkers
from ExponentMax import ExponentMax
from MantissaStage import MantissaStage
from SetDstAddr import SetDstAddr
from PRE import PRE
from Worker import Worker
from Ports import Ports

class Job(Cmd, object):

    #
    # command interface helpers
    #
    
    def parse_arg(self, arg):
        'Convert arg string to tuple'
        return tuple(arg.split())
        
    def run(self):
        while True:
            try:
                self.cmdloop()
            except KeyboardInterrupt:
                sys.stdout.write('<KeyboardInterrupt>\n')

    def emptyline(self):
        'Do nothing when empty line entered at command prompt.'
        pass

    #
    # commands
    #
    
    def do_exit(self, args):
        'Exit program.'
        # exit (bug workaround)
        os.kill(os.getpid(), signal.SIGTERM)
        # never reached
        return -1

    def do_EOF(self, args):
        'Exit on EOF.'
        print "Exiting on EOF."
        return self.do_exit(args)

    def do_clear(self, arg):
        'Clear all registers.'
        print "Clearing all registers..."
        for x in self.registers_to_clear:
            x.clear_registers()
        print "Registers cleared."


    def do_reset(self, arg):
        'Reinitialize all switch state.'
        self.configure_job()

    #
    # state management for job
    #

    def configure_job(self):
        # first, delete all old ports and add new ports for workers,
        self.ports = Ports(self.gc, self.bfrt_info)
        self.ports.delete_all_ports()
        for worker in self.workers:
            self.ports.add_port(worker.front_panel_port, worker.lane, worker.speed, worker.fec)
        

        # add workers to worker bitmap table
        self.get_worker_bitmap = GetWorkerBitmap(self.gc, self.bfrt_info)
        match_priority = 10       # not sure if this matters
        pool_base = 0             # TODO: for now, support only one pool at base index 0
        pool_size = 22528         # TODO: for now, use entire switch for single pool
        worker_mask = 0x00000001  # initial worker mask
        num_workers = len(self.workers)
        for worker in self.workers:
            self.get_worker_bitmap.add_udp_entry(self.switch_mac, self.switch_ip, self.switch_udp_port, self.switch_udp_port_mask,
                                                 worker.mac, worker.ip, worker_mask, num_workers,
                                                 match_priority, self.switch_mgid, pool_base, pool_size)
            # shift mask one bit to left for next worker
            worker_mask = worker_mask << 1


        
        # add update rules for bitmap and clear register
        self.update_and_check_worker_bitmap = UpdateAndCheckWorkerBitmap(self.gc, self.bfrt_info)
        self.registers_to_clear = [self.update_and_check_worker_bitmap]
        
        # add rules for worker count and clear register
        self.count_workers = CountWorkers(self.gc, self.bfrt_info)
        self.registers_to_clear.append(self.count_workers)
        
        # add rules for exponent max calculation and clear register
        self.exponent_max = ExponentMax(self.gc, self.bfrt_info)
        self.registers_to_clear.append(self.exponent_max)
        
        # add rules for data registers and clear registers
        self.mantissas_00_01_02_03 = MantissaStage(self.gc, self.bfrt_info,  0,  1,  2,  3)
        self.registers_to_clear.append(self.mantissas_00_01_02_03)
        self.mantissas_04_05_06_07 = MantissaStage(self.gc, self.bfrt_info,  4,  5,  6,  7)
        self.registers_to_clear.append(self.mantissas_04_05_06_07)
        self.mantissas_08_09_10_11 = MantissaStage(self.gc, self.bfrt_info,  8,  9, 10, 11)
        self.registers_to_clear.append(self.mantissas_08_09_10_11)
        self.mantissas_12_13_14_15 = MantissaStage(self.gc, self.bfrt_info, 12, 13, 14, 15)
        self.registers_to_clear.append(self.mantissas_12_13_14_15)
        self.mantissas_16_17_18_19 = MantissaStage(self.gc, self.bfrt_info, 16, 17, 18, 19)
        self.registers_to_clear.append(self.mantissas_16_17_18_19)
        self.mantissas_20_21_22_23 = MantissaStage(self.gc, self.bfrt_info, 20, 21, 22, 23)
        self.registers_to_clear.append(self.mantissas_20_21_22_23)
        self.mantissas_24_25_26_27 = MantissaStage(self.gc, self.bfrt_info, 24, 25, 26, 27)
        self.registers_to_clear.append(self.mantissas_24_25_26_27)
        self.mantissas_28_29_30_31 = MantissaStage(self.gc, self.bfrt_info, 28, 29, 30, 31)
        self.registers_to_clear.append(self.mantissas_28_29_30_31)
    
        #
        # configure multicast group
        #
        
        # we allocate each worker its own rid.
        rid = 1
        for worker in self.workers:
            worker.rid = rid
            rid = rid + 1
            
        # add workers to multicast group   
        self.pre = PRE(self.gc, self.bfrt_info)
        self.pre.add_workers(self.switch_mgid, self.workers)
            
        # now add workers to set_dst_addr table in egress
        self.set_dst_addr = SetDstAddr(self.gc, self.bfrt_info)
        for worker in self.workers:
            worker.rid = 0 # TODO: set real rid
            self.set_dst_addr.add_udp_entry(worker.mac, worker.ip, worker.rid,
                                            self.ports.get_dev_port(worker.front_panel_port, worker.lane))


    
    def __init__(self, gc, bfrt_info,
                 switch_ip, switch_mac, switch_udp_port, switch_udp_port_mask, switch_mgid, workers):
        # call Cmd constructor
        super(Job, self).__init__()
        self.intro = "SwitchML command loop. Use 'help' or '?' to list commands."
        self.prompt = "-> "

        # capture connection state
        self.gc = gc
        self.bfrt_info = bfrt_info

        # check that this job can be configured
        if len(workers) > 32:
            logger.error("Sorry, can't support more than 32 workers in the current design.")
        
        # capture job state
        self.switch_ip = switch_ip
        self.switch_mac = switch_mac
        self.switch_udp_port = switch_udp_port
        self.switch_udp_port_mask = switch_udp_port_mask
        self.switch_mgid = switch_mgid
        self.workers = workers
        
        # configure job
        self.configure_job()


