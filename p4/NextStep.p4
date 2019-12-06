/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _NEXT_STEP_
#define _NEXT_STEP_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

control NextStep(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    action drop() {
        // mark for drop
        ig_dprsr_md.drop_ctl = ig_dprsr_md.drop_ctl | 0x1;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
    }

    action recirculate_for_harvest() {
        // drop second data header, since first header has data we read out
        hdr.d1.setInvalid();
        
        // recirculate for harvest
        ig_tm_md.ucast_egress_port = ig_md.switchml_md.ingress_port[8:7] ++ 7w68;
        ig_tm_md.bypass_egress = 1w1;
        ig_md.switchml_md.packet_type = packet_type_t.HARVEST;
    }

    action broadcast_eth() {
        // set the switch as the source MAC address
        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        // send to multicast group; egress will fill in destination IP and MAC address
        ig_tm_md.mcast_grp_a = ig_md.switchml_md.mgid;
        ig_md.switchml_md.packet_type = packet_type_t.EGRESS;
    }
    
    action broadcast_udp() {
        // set the switch as the source IP
        hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        broadcast_eth();
    }
    
    action retransmit_eth() {
        // swap source and destination MAC addresses
        hdr.ethernet.dst_addr = hdr.ethernet.src_addr;
        //hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        // send back out ingress port
        ig_tm_md.ucast_egress_port = ig_md.switchml_md.ingress_port;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
    }
    
    action retransmit_udp() {
        // swap source and destination IPs
        hdr.ipv4.dst_addr = hdr.ipv4.src_addr;
        //hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        retransmit_eth();
    }
    
    table next_step {
        key = {
            ig_md.switchml_md.packet_type : ternary;
            ig_md.switchml_md.first_last_flag : ternary; // 1: last 0: first
            ig_md.switchml_md.map_result : ternary;
            hdr.ib_bth.isValid() : ternary;
            hdr.udp.isValid() : ternary;
            //ig_dprsr_md.drop_ctl : ternary;
        }
        actions = {
            recirculate_for_harvest;
            drop;
            broadcast_udp;
            retransmit_udp;
            NoAction;
        }
        size = 9;
        const entries = {
            //        packet type | last |map result|RoCE|  UDP

            // for CONSUME packets that are the last packet, recirculate for harvest
            (packet_type_t.CONSUME,     1,         _,    _,   _) : recirculate_for_harvest();
            // for CONSUME packets that are retransmitted packets to a full slot, recirculate for harvest
            (packet_type_t.CONSUME,     0,         0,    _,   _) : drop(); // first consume packet for slot
            (packet_type_t.CONSUME,     0,         _,    _,   _) : recirculate_for_harvest();
            // drop others
            (packet_type_t.CONSUME,     _,         _,    _,   _) : drop();

            // broadcast any HARVEST packets that are UDP, not retransmitted, and are the last packet 
            (packet_type_t.HARVEST,     1,         0,  false, true) : broadcast_udp();
            // drop any HARVEST packets that are not retransmitted and are the last packet
            (packet_type_t.HARVEST,     1,         0,    _,   _) : drop(); // TODO: support other formats
            // retransmit any other HARVEST packets that are UDP and 
            (packet_type_t.HARVEST,     0,         0,    _,   _) : drop(); // shouldn't ever get here
            (packet_type_t.HARVEST,     0,         _,  false, true) : retransmit_udp();
            // drop any other HARVEST packets
            (packet_type_t.HARVEST,     _,         _,    _,   _) : drop(); // TODO: support other formats
            // ignore other packet types
        }
        const default_action = NoAction;
    }
    
    apply {
        next_step.apply();
    }
}

#endif /* _NEXT_STEP_ */
