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

    //DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) next_step_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) recirculate_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) broadcast_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) retransmit_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) drop_counter;

    action drop() {
        // mark for drop
        ig_dprsr_md.drop_ctl[0:0] = 1;
        //ig_md.switchml_md.packet_type = packet_type_t.IGNORE;

        //next_step_counter.count();
        //drop_counter.count(ig_md.switchml_md.pool_index);
    }

    action recirculate_for_harvest() {
        // drop second data header, since first header has data we read out
        hdr.d1.setInvalid();
        
        // recirculate for harvest
        ig_tm_md.ucast_egress_port = ig_md.switchml_md.ingress_port[8:7] ++ 7w68; // TODO: use both recirc ports
        ig_tm_md.bypass_egress = 1w1;
        ig_dprsr_md.drop_ctl[0:0] = 0;
        ig_md.switchml_md.packet_type = packet_type_t.HARVEST;

        //next_step_counter.count();
        recirculate_counter.count(ig_md.switchml_md.pool_index);
    }

    action broadcast_eth() {
        // set the switch as the source MAC address
        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        // destination address will be filled in egress pipe

        // send to multicast group; egress will fill in destination IP and MAC address
        ig_tm_md.mcast_grp_a = ig_md.switchml_md.mgid;
        ig_tm_md.level1_exclusion_id = null_level1_exclusion_id; // don't exclude any nodes
        ig_md.switchml_md.packet_type = packet_type_t.BROADCAST;
        ig_tm_md.bypass_egress = 1w0;
        ig_dprsr_md.drop_ctl[0:0] = 0;

        //next_step_counter.count();
        //broadcast_counter.count(ig_md.switchml_md.pool_index);
    }
    
    action broadcast_udp() {
        // // set the switch as the source IP
        // hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        // // destination IP will be filled in in egress pipe

        broadcast_eth();
    }
    
    action broadcast_roce() {
        // // set the switch as the source IP
        // hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        // // destination IP, QPN, PSN, etc. will be filled in in egress pipe

        // add empty ICRC header
        hdr.ib_icrc.setValid();

        broadcast_eth();
    }
    
    action retransmit_eth() {
        // // set the switch as the source MAC address
        // hdr.ethernet.dst_addr = hdr.ethernet.src_addr;
        // // destination address will be filled in egress pipe

        // send back out ingress port
        ig_tm_md.ucast_egress_port = ig_md.switchml_md.ingress_port;
        ig_md.switchml_md.packet_type = packet_type_t.RETRANSMIT;
        ig_tm_md.bypass_egress = 1w0;
        ig_dprsr_md.drop_ctl[0:0] = 0;

        //next_step_counter.count();
        //retransmit_counter.count(ig_md.switchml_md.pool_index);
    }
    
    action retransmit_udp() {
        // // swap source and destination IPs
        // ipv4_addr_t dst_addr = hdr.ipv4.dst_addr;
        // hdr.ipv4.dst_addr = hdr.ipv4.src_addr;
        // hdr.ipv4.src_addr = dst_addr;

        // // swap source and destination ports
        // udp_port_t dst_port = hdr.udp.dst_port;
        // hdr.udp.dst_port = hdr.udp.src_port;
        // hdr.udp.src_port = dst_port;

        // hdr.udp.checksum = 0;
        // ig_md.update_ipv4_checksum = true;
        
        retransmit_eth();
    }

    action retransmit_roce() {
        // // set the switch as the source IP
        // hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        // // destination IP, QPN, PSN, etc. will be filled in in egress pipe

        // add empty ICRC header
        hdr.ib_icrc.setValid();

        retransmit_eth();
    }
    
    table next_step {
        key = {
            ig_md.switchml_md.packet_type : ternary;
            ig_md.switchml_md.first_last_flag : ternary; // 1: last 0: first
            ig_md.switchml_md.map_result : ternary;
            ig_md.switchml_md.worker_type : ternary;
            //hdr.ib_bth.isValid() : ternary;
            //hdr.udp.isValid() : ternary;
            //ig_dprsr_md.drop_ctl : ternary;
        }
        actions = {
            recirculate_for_harvest;
            drop;
            broadcast_udp;
            retransmit_udp;
            broadcast_roce;
            retransmit_roce;
        }
        size = 11;
        const entries = {
            //        packet type | last |map result|worker_type

            // for CONSUME packets that are the last packet, recirculate for harvest
            (packet_type_t.CONSUME,     1,         _,          _) : recirculate_for_harvest();
            // for CONSUME packets that are retransmitted packets to a full slot, recirculate for harvest
            (packet_type_t.CONSUME,     0,         0,          _) : drop(); // first consume packet for slot
            (packet_type_t.CONSUME,     0,         _,          _) : recirculate_for_harvest();
            // drop others
            (packet_type_t.CONSUME,     _,         _,          _) : drop();

            // broadcast any HARVEST packets that are not retransmitted, are the last packet, and the protocol is implemented
            (packet_type_t.HARVEST,     1,         0, worker_type_t.SWITCHML_UDP) : broadcast_udp();
            (packet_type_t.HARVEST,     1,         0, worker_type_t.ROCEv2) : broadcast_roce();
            // drop any HARVEST packets that are not retransmitted, are the last packet, and we don't have a protocol implementation
            (packet_type_t.HARVEST,     1,         0,          _) : drop(); // TODO: support other formats
            // shouldn't ever get here, because the packet would be dropped in CONSUME
            (packet_type_t.HARVEST,     0,         0,          _) : drop(); // shouldn't ever get here
            // retransmit any other HARVEST packets for which we have an implementation
            (packet_type_t.HARVEST,     0,         _, worker_type_t.SWITCHML_UDP) : retransmit_udp();
            (packet_type_t.HARVEST,     0,         _, worker_type_t.ROCEv2) : retransmit_roce();
            // drop any other HARVEST packets
            (packet_type_t.HARVEST,     _,         _,          _) : drop(); // TODO: support other formats
            // ignore other packet types
        }
        //counters = next_step_counter;
    }
    
    apply {
        next_step.apply();

        
        // if (ig_md.switchml_md.packet_type == packet_type_t.HARVEST) {
        //     recirculate_counter.count(ig_md.switchml_md.pool_index);
        // } else
        if (ig_md.switchml_md.packet_type == packet_type_t.BROADCAST) {
            broadcast_counter.count(ig_md.switchml_md.pool_index);
        } else if (ig_md.switchml_md.packet_type == packet_type_t.RETRANSMIT) {
            retransmit_counter.count(ig_md.switchml_md.pool_index);
        } else {
            drop_counter.count(ig_md.switchml_md.pool_index);
        }
    }
}

#endif /* _NEXT_STEP_ */
