/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

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

    // packet was received with errors; set drop bit in deparser metadata
    action drop() {
        // ignore this packet and drop when it leaves pipeline
        ig_dprsr_md.drop_ctl = ig_dprsr_md.drop_ctl | 0x1;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
    }

    // packet is not a SwitchML packet; just foward
    action forward() {
        // forward this packet
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
    }

    action set_bitmap(
        MulticastGroupId_t mgid,
        packet_type_t packet_type,
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap,
        worker_bitmap_t complete_bitmap,
        pool_index_t pool_base,
        worker_pool_index_t pool_size_minus_1) {

        // bitmap representation for this worker
        ig_md.worker_bitmap   = worker_bitmap;
        ig_md.num_workers     = num_workers;
        ig_md.complete_bitmap = complete_bitmap;

        // group ID for this job
        ig_md.switchml_md.mgid = mgid;
        
        //
        // Pool parameters
        //
        
        // packet index is 0-based; we add this to pool_offset to get the
        // physical pool index that's correct for this job
        // TODO: fix this so that container sizes match when we add the base to the index
        //ig_md.switchml_md.pool_index = pool_base + (1w0 ++ hdr.switchml.pool_index);
        ig_md.switchml_md.pool_index = (1w0 ++ hdr.switchml.pool_index);
        
        // use LSB of pool index to determine which set this packet is targeting.
        ig_md.pool_set = hdr.switchml.pool_index[0:0];
        
        // use this to check if pool index in packet is too large
        // if it's negative, the index in the packet is too big, so drop
        ig_md.pool_remaining = pool_size_minus_1 - hdr.switchml.pool_index;
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
            hdr.ib_bth.partition_key  : ternary;
            hdr.ib_bth.dst_qp         : ternary;
            ig_prsr_md.parser_err     : ternary;
        }
        
        actions = {
            drop;
            forward;
            set_bitmap;
        }
        const default_action = forward;
        
        // create some extra table space to support parser error entries
        size = max_num_workers + 16;
    }

    apply {
        get_worker_bitmap.apply();
    }
}

#endif /* _GET_WORKER_BITMAP_ */