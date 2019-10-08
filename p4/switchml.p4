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

#include "types.p4"
#include "headers.p4"
#include "parsers.p4"
#include "registers.p4"

control SwitchMLIngress(
    inout header_t hdr,
    inout metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    const index_t register_size = 256;
    

    // instantiate data registers (8 stages, or 32 2x32b registers, for 256B)
    STAGE(data_pair_t, index_t, data_t, data_reg, register_size, d, 00, 01, 02, 03)
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 04, 05, 06, 07);
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 08, 09, 10, 11);
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 12, 13, 14, 15);
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 16, 17, 18, 19);
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 20, 21, 22, 23);
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 24, 25, 26, 27);
    // STAGE(data_pair_t, index_t, data_t, data, register_size, d, 28, 29, 30, 31);

    //REGISTER(data_pair_t, index_t, data_t, data, register_size, d, 00)

    // Register<data_pair_t, index_t>(register_size) data_00;
    // RegisterAction<data_pair_t, index_t, data_t>(data_00) data_00_write = {
    //     void apply(inout data_pair_t value) {
    //         value.first = hdr.d0. d00;
    //         value.second = hdr.d1. d00;
    //     }
    // };
    // RegisterAction<data_pair_t, index_t, data_t>(data_00) data_00_add_read0 = {
    //     void apply(inout data_pair_t value, out data_t read_value) {
    //         value.first = value.first + hdr.d0. d00;
    //         value.second = value.second + hdr.d1. d00;
    //         read_value = value.first;
    //     }
    // };
    // RegisterAction<data_pair_t, index_t, data_t>(data_00) data_00_max_read0 = {
    //     void apply(inout data_pair_t value, out data_t read_value) {
    //         value.first = max(value.first, hdr.d0. d00);
    //         value.second = max(value.second, hdr.d1. d00);
    //         read_value = value.first;
    //     }
    // };
    // RegisterAction<data_pair_t, index_t, data_t>(data_00) data_00_read1 = {
    //     void apply(inout data_pair_t value, out data_t read_value) {
    //         read_value = value.second;
    //     }
    // };
    // action write_00() {
    //     data_00_write.execute(ig_md.address);
    // }
    // action add_read0_00() {
    //     hdr.d0. d00 = data_00_add_read0.execute(ig_md.address);
    // }
    // action max_read0_00() {
    //     hdr.d0. d00 = data_00_max_read0.execute(ig_md.address);
    // }
    // action read1_00() {
    //     hdr.d1. d00 = data_00_read1.execute(ig_md.address);
    // }
    // table data_00_tbl {
    //     key = {
    //         ig_md.opcode : exact;
    //     }
    //     actions = {
    //         NoAction;
    //         write_00;
    //         add_read0_00;
    //         max_read0_00;
    //         read1_00;
    //     }
    //     const default_action = NoAction;
    //     size = 4;
    // }
    
    // // instantiate exponent registers (1 stage, or 4 2x8b registers, for 8B)
    // // this is one exponent for every 8 integers
    // STAGE(exponent_pair_t, index_t, exponent_t, exponent, register_size, e, 0, 1, 2, 3);

    action extract_opcode_and_address() {
        // update metadata with fake opcode and address
        ig_md.opcode  = hdr.ib_bth.opcode[1:0];
        ig_md.address = 24w0 ++ hdr.ib_bth.psn[7:0];
    }
    
    apply {
        // if this is a valid SwitchML/RoCE packet
        if (hdr.ib_bth.isValid()) {
            extract_opcode_and_address();

            // get bitmask for this job
            // get set for this job
            // get num_workers for this job

            // update the bitmap
            // check the bitmap

            // update exponents

            // count workers

            // aggregate data
            // apply data register tables (8 stages)
            APPLY_STAGE(data_reg, 00, 01, 02, 03);
        }
    }
}


control SwitchMLEgress(
    inout header_t hdr,
    inout metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_oport_md) {
    apply {
        // do nothing in egress; we bypass egress in this design
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

