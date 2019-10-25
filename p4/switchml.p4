/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#include <core.p4>

#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

// define constants and sizes
#include "configuration.p4"
#include "types.p4"
#include "headers.p4"
#include "parsers.p4"
//#include "registers.p4"

#include "get_worker_bitmap.p4"
#include "drop_simulator.p4"
#include "update_and_check_worker_bitmap.p4"
#include "exponent_max.p4"
#include "mantissa_stage.p4"
#include "count_workers.p4"
#include "set_dst_addr.p4"
#include "forward.p4"
#include "recirculate_for_harvest.p4"

#ifdef INCLUDE_SWAP_BYTES
#include "swap_bytes.p4"
#endif


control SwitchMLIngress(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {
    
    
    
#ifdef INCLUDE_SWAP_BYTES
    // define swap_bytes tables
    //DEFINE_SWAP_BYTES(ingress)
#endif

#ifdef INCLUDE_SWAP_BYTES
    // convert from little- to big-endian, first half
    // WARNING: swaps each pair of values (0 & 1, 2 & 3, etc.)
    action hton1() {
        HTONNTOH(hdr.d0, 00, 01, 02, 03);
        HTONNTOH(hdr.d0, 04, 05, 06, 07);
        HTONNTOH(hdr.d0, 08, 09, 10, 11);
        HTONNTOH(hdr.d0, 12, 13, 14, 15);
        HTONNTOH(hdr.d1, 00, 01, 02, 03);
        HTONNTOH(hdr.d1, 04, 05, 06, 07);
        HTONNTOH(hdr.d1, 08, 09, 10, 11);
        HTONNTOH(hdr.d1, 12, 13, 14, 15);
    }

    // convert from little- to big-endian, second half
    // WARNING: swaps each pair of values (0 & 1, 2 & 3, etc.)
    action hton2() {
        HTONNTOH(hdr.d0, 16, 17, 18, 19);
        HTONNTOH(hdr.d0, 20, 21, 22, 23);
        HTONNTOH(hdr.d0, 24, 25, 26, 27);
        HTONNTOH(hdr.d0, 28, 29, 30, 31);
        HTONNTOH(hdr.d1, 16, 17, 18, 19);
        HTONNTOH(hdr.d1, 20, 21, 22, 23);
        HTONNTOH(hdr.d1, 24, 25, 26, 27);
        HTONNTOH(hdr.d1, 28, 29, 30, 31);
    }

    // convert back from big to little-endian
    // TODO: currently fails with more than a few swaps
    action ntoh() {
        HTONNTOH(hdr.d0, 00, 01, 02, 03);
        HTONNTOH(hdr.d0, 04, 05, 06, 07);
        HTONNTOH(hdr.d0, 08, 09, 10, 11);
        //HTONNTOH(hdr.d0, 12, 13, 14, 15);
    }
#endif

    //
    // instantiate controls for  of tables and actions
    //

    GetWorkerBitmap() get_worker_bitmap;
    DropRNG() drop_rng;
    UpdateAndCheckWorkerBitmap() update_and_check_worker_bitmap;

    ExponentMax() exponent_max;

    MantissaStage() mantissas_00_01_02_03;
    MantissaStage() mantissas_04_05_06_07;
    MantissaStage() mantissas_08_09_10_11;
    MantissaStage() mantissas_12_13_14_15;
    MantissaStage() mantissas_16_17_18_19;
    MantissaStage() mantissas_20_21_22_23;
    MantissaStage() mantissas_24_25_26_27;
    MantissaStage() mantissas_28_29_30_31;
    
    CountWorkers() count_workers;
    Forward() forward;

    RecirculateForHarvest() recirculate_for_harvest;

    apply {

        // if switchml_md header isn't valid, this packet came from outside the switch
        if (! hdr.switchml_md.isValid()) { // skip if recirculated with metadata header
            // get worker masks, pool base index, other parameters for this packet
            // add switchml_md header
            get_worker_bitmap.apply(hdr, ig_md, ig_intr_md, ig_prsr_md, ig_dprsr_md, ig_tm_md);

            // support dropping packets with some probability by commputing random number here
            drop_rng.apply(hdr.switchml_md.drop_random_value);
        
            // record packet reception and check if this packet is a retransmission.
            // If drop simulation says to, drop packet and clear switchml_md valid bit
            update_and_check_worker_bitmap.apply(hdr, ig_md, ig_dprsr_md);
        }

        // detect when we have received all the packets for a slot
        count_workers.apply(hdr, ig_md, ig_dprsr_md);

        // update max exponents
        // for now, we'll stick with the original SwitchML design and use 1 16-bit exponent (half of the register unit). 
        exponent_max.apply(hdr.exponents.e0, hdr.exponents.e0, hdr.exponents.e0, _, hdr, ig_md);

        // aggregate mantissas
        // use a macro to reduce a little typing.
#define APPLY_MANTISSA_STAGE(AA, BB, CC, DD)       \
        mantissas_##AA##_##BB##_##CC##_##DD.apply( \
            hdr.d0.d##AA, hdr.d1.d##AA,            \
            hdr.d0.d##BB, hdr.d1.d##BB,            \
            hdr.d0.d##CC, hdr.d1.d##CC,            \
            hdr.d0.d##DD, hdr.d1.d##DD,            \
            hdr, ig_md)
        
        APPLY_MANTISSA_STAGE(00, 01, 02, 03);
        APPLY_MANTISSA_STAGE(04, 05, 06, 07);
        APPLY_MANTISSA_STAGE(08, 09, 10, 11);
        APPLY_MANTISSA_STAGE(12, 13, 14, 15);
        APPLY_MANTISSA_STAGE(16, 17, 18, 19);
        APPLY_MANTISSA_STAGE(20, 21, 22, 23);
        APPLY_MANTISSA_STAGE(24, 25, 26, 27);
        APPLY_MANTISSA_STAGE(28, 29, 30, 31);

        
        if (hdr.switchml_md.packet_type == packet_type_t.CONSUME) {
            // Finished consuming SwitchML packet; now recirculate to finish harvesting values
            recirculate_for_harvest.apply(hdr, ig_intr_md, ig_tm_md);
        } else if (hdr.switchml_md.packet_type == packet_type_t.HARVEST) {
            // Finished harvesting SwitchML packet; now either broadcast or forward
            if (ig_md.map_result != 0) { // retransmission
                if (ig_md.first_last_flag == 0) {
                    if (hdr.ib_bth.isValid()) {
                        // do nothing for either RoCE type for  now
                        ig_dprsr_md.drop_ctl = 0x1;
                    } else {
                        if (hdr.udp.isValid()) {
                            hdr.ipv4.dst_addr = hdr.ipv4.src_addr;
                        } 
                        ig_tm_md.ucast_egress_port = ig_intr_md.ingress_port;
                        hdr.ethernet.dst_addr = hdr.ethernet.src_addr;
                    }
                }
            } else {
                if (ig_md.first_last_flag == 1) {
                    if (hdr.ib_bth.isValid()) {
                        // do nothing for either RoCE type for  now
                        ig_dprsr_md.drop_ctl = 0x1;
                    } else {
                        if (hdr.udp.isValid()) {
                            hdr.ipv4.dst_addr = hdr.ipv4.src_addr;
                        } 
                        ig_tm_md.mcast_grp_a = 1;
                        hdr.ethernet.dst_addr = hdr.ethernet.src_addr;
                    }
                }
            }
        } else {
            // not SwitchML packet for us, so just forward
            if (ig_dprsr_md.drop_ctl[0:0] == 1w0) {
                forward.apply(hdr, ig_md, ig_dprsr_md, ig_tm_md);
            }
        }
    }
}


control SwitchMLEgress(
    inout header_t hdr,
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_oport_md) {

    EgressDropSimulator() egress_drop_sim;
    SetDestinationAddress() set_dst_addr;
    
    apply {
        // simulate packet drops
        // (will clear switchml_md valid bit if packet is dropped)
        if (hdr.switchml_md.isValid()) {
            egress_drop_sim.apply(hdr.switchml_md, eg_intr_dprs_md);
        }

        // for multicast packets, fill in correct destination address based on 
        if (hdr.switchml_md.isValid()) {
            set_dst_addr.apply(eg_intr_md, hdr);
            // get rid of SwitchML metadata header before packet leaves the switch
            hdr.switchml_md.setInvalid();
        }

    }
}

Pipeline(
    SwitchMLIngressParser(),
    SwitchMLIngress(),
    SwitchMLIngressDeparser(),
    SwitchMLEgressParser(),
    SwitchMLEgress(),
    SwitchMLEgressDeparser()) pipe;

Switch(pipe) main;

