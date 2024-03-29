// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _GET_WORKER_BITMAP_
#define _GET_WORKER_BITMAP_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"


control GetWorkerBitmap(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {
    
    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) receive_counter;

    Hash<pool_index_t>(HashAlgorithm_t.IDENTITY) pool_index_hash;
    Hash<bit<32>>(HashAlgorithm_t.IDENTITY) worker_bitmap_hash;

    // packet was received with errors; set drop bit in deparser metadata
    action drop() {
        // ignore this packet and drop when it leaves pipeline
        ig_dprsr_md.drop_ctl[0:0] = 1;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
        receive_counter.count();
    }

    // packet is not a SwitchML packet; just foward
    action forward() {
        // forward this packet
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
        receive_counter.count();
    }

    action set_bitmap(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        packet_type_t packet_type,
        packet_size_t packet_size,
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap,
        worker_bitmap_t complete_bitmap,  // TODO: probably delete this
        pool_index_t pool_base,
        worker_pool_index_t pool_size_minus_1) {

        // count received packet
        receive_counter.count();
        
        // bitmap representation for this worker
        ig_md.worker_bitmap           = worker_bitmap;
        ig_md.switchml_md.num_workers = num_workers;

        // group ID for this job
        ig_md.switchml_md.mgid = mgid;

        ig_md.switchml_md.worker_type = worker_type;
        ig_md.switchml_md.worker_id = worker_id;     // Same as rid for worker; used when retransmitting RDMA packets

        ig_md.switchml_md.packet_size = packet_size;
        ig_md.switchml_md.recirc_port_selector = (queue_pair_index_t) hdr.switchml.pool_index;
        //ig_md.switchml_md.recirc_port_selector = hdr.switchml.pool_index[12:0] ++ hdr.switchml.pool_index[15:15];
        
        // move the SwitchML set bit in the MSB to the LSB to match existing software
        //ig_md.switchml_md.pool_index = hdr.switchml.pool_index[13:0] ++ hdr.switchml.pool_index[15:15]; // doesn't want to compile
        ig_md.switchml_md.pool_index = pool_index_hash.get({hdr.switchml.pool_index[13:0], hdr.switchml.pool_index[15:15]});

        // mark packet as single-packet message since it's the UDP protocol
        ig_md.switchml_md.first_packet_of_message = true;
        ig_md.switchml_md.last_packet_of_message  = true;

        // extract exponents
        ig_md.switchml_exponents_md.setValid();
        ig_md.switchml_exponents_md.e0 = hdr.exponents.e0[15:8];
        ig_md.switchml_exponents_md.e1 = hdr.exponents.e0[7:0];
        hdr.exponents.setInvalid();
        
        ig_md.switchml_udp_md.setValid();
        ig_md.switchml_udp_md.src_port = hdr.udp.src_port;
        ig_md.switchml_udp_md.dst_port = hdr.udp.dst_port;
        ig_md.switchml_udp_md.msg_type = hdr.switchml.msgType;
        ig_md.switchml_udp_md.opcode = hdr.switchml.opcode;
        ig_md.switchml_udp_md.tsi = hdr.switchml.tsi;

        // get rid of headers we don't want to recirculate
        hdr.ethernet.setInvalid();
        hdr.ipv4.setInvalid();
        hdr.udp.setInvalid();
        hdr.switchml.setInvalid();
    }
    
    table get_worker_bitmap {
        key = {
            // use ternary matches to support matching on:
            // * ingress port only like the original design
            // * source IP and UDP destination port for the SwitchML Eth protocol
            // * source IP and UDP destination port for the SwitchML UDP protocol
            // * source IP and destination QP number for the RoCE protocols
            // * also, parser error values so we can drop bad packets
            ig_intr_md.ingress_port   : ternary;
            hdr.ethernet.src_addr     : ternary;
            hdr.ethernet.dst_addr     : ternary;
            hdr.ipv4.src_addr         : ternary;
            hdr.ipv4.dst_addr         : ternary;
            hdr.udp.dst_port          : ternary;
            //hdr.ib_bth.partition_key  : ternary;
            //hdr.ib_bth.dst_qp         : ternary;
            //ig_prsr_md.parser_err     : ternary;
        }
        
        actions = {
            drop;
            set_bitmap;
            @defaultonly forward;
        }
        const default_action = forward;
        
        size = max_num_workers;

        // count received packets
        counters = receive_counter;
    }

    apply {
        get_worker_bitmap.apply();
    }
}

#endif /* _GET_WORKER_BITMAP_ */
