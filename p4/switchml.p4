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
#include "registers.p4"

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
    DEFINE_SWAP_BYTES(ingress)
#endif
    
    //
    // instantiate data/exponent registers
    //
    
    // create macro to instantate data registers for one pipe stage
    #define DEFSTAGE(AA, BB, CC, DD) \
    STAGE(data_pair_t, index_t, data_t, data_reg, register_size, \
        hdr.d0.d, hdr.d1.d, ig_md.address, ig_md.opcode, \
        AA, BB, CC, DD)

    // instantiate data registers (8 stages, or 32 2x32b registers, for 256B)
    DEFSTAGE(00, 01, 02, 03)
    DEFSTAGE(04, 05, 06, 07)
    DEFSTAGE(08, 09, 10, 11)
    DEFSTAGE(12, 13, 14, 15)
    DEFSTAGE(16, 17, 18, 19)
    DEFSTAGE(20, 21, 22, 23)
    DEFSTAGE(24, 25, 26, 27)
    DEFSTAGE(28, 29, 30, 31)

    // define exponent registers
    STAGE(exponent_pair_t, index_t, exponent_t, exponent_reg, register_size, \
        hdr.e0.e, hdr.e1.e, ig_md.address, ig_md.opcode, \
        0, 1, 2, 3)


    action extract_opcode_and_address() {
        // update metadata with fake opcode and address
        ig_md.opcode  = hdr.ib_bth.opcode[1:0];
        ig_md.address = 24w0 ++ hdr.ib_bth.psn[7:0];
    }

    action invalidate_second_header() {
        hdr.d1.setInvalid();
    }
    
    apply {
        // if this is a valid SwitchML/RoCE packet
        if (hdr.ib_bth.isValid()) {
            extract_opcode_and_address();

#ifdef INCLUDE_SWAP_BYTES
            // try doing hton() for the first 24 elements of each header
            //swap_bytes1_tbl.apply();
            APPLY_SWAP_BYTES1(ingress);

            // this is the rest of the hton(); it fails with a compiler bug right now
            //swap_bytes2_tbl.apply();
#endif
            
            // get bitmask for this job
            // get set for this job
            // get num_workers for this job

            // update the bitmap
            // check the bitmap

            // update exponents

            // count workers

            // aggregate data
            // apply data register tables (8 stages + 1 stage for exponents)
            APPLY_STAGE(exponent_reg, 0, 1, 2, 3);

            APPLY_STAGE(data_reg, 00, 01, 02, 03);
            APPLY_STAGE(data_reg, 04, 05, 06, 07);
            APPLY_STAGE(data_reg, 08, 09, 10, 11);
            APPLY_STAGE(data_reg, 12, 13, 14, 15);
            APPLY_STAGE(data_reg, 16, 17, 18, 19);
            APPLY_STAGE(data_reg, 20, 21, 22, 23);
            APPLY_STAGE(data_reg, 24, 25, 26, 27);
            APPLY_STAGE(data_reg, 28, 29, 30, 31);

            // We have consumed both the d0 and d1 headers, and filled the d0 headers with the values we read out.
            // Now drop the d1 header and (if this is the last packet) recirculate.
            invalidate_second_header();
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

#ifdef INCLUDE_SWAP_BYTES
    DEFINE_SWAP_BYTES(egress)
#endif
    
    apply {
        if (hdr.ib_bth.isValid()) {
#ifdef INCLUDE_SWAP_BYTES
            APPLY_SWAP_BYTES1(egress);
            //APPLY_SWAP_BYTES2(egress);
#endif
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

