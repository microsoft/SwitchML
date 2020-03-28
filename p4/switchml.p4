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

#include "ARPandICMP.p4"
#include "GetWorkerBitmap.p4"
#include "DropSimulator.p4"
#include "UpdateAndCheckWorkerBitmap.p4"
#include "ExponentMax.p4"
#include "SignificandStage.p4"
#include "CountWorkers.p4"
#include "SetDstAddr.p4"
#include "NonSwitchMLForward.p4"
#include "NextStep.p4"

control SwitchMLIngress(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {
    
    //
    // instantiate controls for tables and actions
    //

    ARPandICMP() arp_and_icmp;
    GetWorkerBitmap() get_worker_bitmap;
    DropRNG() drop_rng;
    UpdateAndCheckWorkerBitmap() update_and_check_worker_bitmap;

    ExponentMax() exponent_max;

    SignificandStage() significands_00_01_02_03;
    SignificandStage() significands_04_05_06_07;
    SignificandStage() significands_08_09_10_11;
    SignificandStage() significands_12_13_14_15;
    SignificandStage() significands_16_17_18_19;
    SignificandStage() significands_20_21_22_23;
    SignificandStage() significands_24_25_26_27;
    SignificandStage() significands_28_29_30_31;
    
    CountWorkers() count_workers;

    NextStep() switchml_next_step;
    NonSwitchMLForward() non_switchml_forward;

    apply {

        // see if this is a SwitchML packet
        // get worker masks, pool base index, other parameters for this packet
        // add switchml_md header if it isn't already added
        get_worker_bitmap.apply(hdr, ig_md, ig_intr_md, ig_prsr_md, ig_dprsr_md, ig_tm_md);
        // handle ARP and ICMP requests
        arp_and_icmp.apply(hdr, ig_md, ig_intr_md, ig_prsr_md, ig_dprsr_md, ig_tm_md);

        // support dropping packets with some probability by commputing random number here
        drop_rng.apply(ig_md.switchml_md.drop_random_value);
        
        // for CONSUME packets, record packet reception and check if this packet is a retransmission.
        update_and_check_worker_bitmap.apply(hdr, ig_md, ig_intr_md, ig_dprsr_md);

        // detect when we have received all the packets for a slot
        count_workers.apply(hdr, ig_md, ig_dprsr_md);

        // update max exponents
        // for now, we'll stick with the original SwitchML design and use 1 16-bit exponent
        // (using just half of the register unit). 
        exponent_max.apply(hdr.exponents.e0, hdr.exponents.e0, hdr.exponents.e0, _, hdr, ig_md);

        // aggregate significands
        // use a macro to reduce a little typing.
#define APPLY_SIGNIFICAND_STAGE(AA, BB, CC, DD)       \
        significands_##AA##_##BB##_##CC##_##DD.apply( \
            hdr.d0.d##AA, hdr.d1.d##AA,            \
            hdr.d0.d##BB, hdr.d1.d##BB,            \
            hdr.d0.d##CC, hdr.d1.d##CC,            \
            hdr.d0.d##DD, hdr.d1.d##DD,            \
            hdr, ig_md)
        
        APPLY_SIGNIFICAND_STAGE(00, 01, 02, 03);
        APPLY_SIGNIFICAND_STAGE(04, 05, 06, 07);
        APPLY_SIGNIFICAND_STAGE(08, 09, 10, 11);
        APPLY_SIGNIFICAND_STAGE(12, 13, 14, 15);
        APPLY_SIGNIFICAND_STAGE(16, 17, 18, 19);
        APPLY_SIGNIFICAND_STAGE(20, 21, 22, 23);
        APPLY_SIGNIFICAND_STAGE(24, 25, 26, 27);
        APPLY_SIGNIFICAND_STAGE(28, 29, 30, 31);

        // decide what to do with this packet
        non_switchml_forward.apply(hdr, ig_md, ig_dprsr_md, ig_tm_md);
        switchml_next_step.apply(hdr, ig_md, ig_intr_md, ig_dprsr_md, ig_tm_md);
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
        egress_drop_sim.apply(eg_md.switchml_md, eg_intr_dprs_md);

        // for multicast packets, fill in correct destination address based on 
        set_dst_addr.apply(eg_md, eg_intr_md, hdr);
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

