/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _SIGNIFICAND_SUM_
#define _SIGNIFICAND_SUM_

#include "types.p4"
#include "headers.p4"

// Significand sum value calculator
//
// Each control handles two significands.
control SignificandSum(
    inout significand_t significand0,
    inout significand_t significand1,
    in header_t hdr,
    inout ingress_metadata_t ig_md) {

    Register<significand_pair_t, pool_index_t>(register_size) significands;

    // Write both significands and read first one
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_write_read0_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            value.first = significand0;
            value.second = significand1;
            read_value = value.first;
        }
    };

    action significand_write_read0_action() {
        significand0 = significand_write_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // compute sum of both significands and read first one
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_sum_read0_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            value.first  = value.first  + significand0;
            value.second = value.second + significand1;
            read_value = value.first;
        }
    };

    action significand_sum_read0_action() {
        significand0 = significand_sum_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // read first sum register
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_read0_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            read_value = value.first;
        }
    };

    action significand_read0_action() {
        significand0 = significand_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // read second sum register
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_read1_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            read_value = value.second;
        }
    };

    action significand_read1_action() {
        significand1 = significand_read1_register_action.execute(ig_md.switchml_md.pool_index);
    }

    /* If bitmap_before is 0 and type is CONSUME, just write values. */
    /* If bitmap_before is not zero and type is CONSUME, add values and read first value. */
    /* If map_result is not zero and type is CONSUME, just read first value. */
    /* If type is HARVEST, read second value. */
    table significand_sum {
        key = {
            ig_md.switchml_md.worker_bitmap_before : ternary;
            ig_md.switchml_md.map_result : ternary;
            ig_md.switchml_md.packet_type: ternary;
        }
        actions = {
            significand_write_read0_action;
            significand_sum_read0_action;
            significand_read0_action;
            significand_read1_action;
            NoAction;
        }
        size = 4;
        const entries = {
            // if bitmap_before is all 0's and type is CONSUME, this is the first packet for slot, so just write values and read first value
            (32w0,    _, packet_type_t.CONSUME) : significand_write_read0_action();
            // if bitmap_before is nonzero, map_result is all 0's,  and type is CONSUME, compute sum of values and read first value
            (   _, 32w0, packet_type_t.CONSUME) : significand_sum_read0_action();
            // if bitmap_before is nonzero, map_result is nonzero, and type is CONSUME, this is a retransmission, so just read first value
            (   _,    _, packet_type_t.CONSUME) : significand_read0_action();
            // if type is HARVEST, read second value
            (   _,    _, packet_type_t.HARVEST) : significand_read1_action();
        }
        // if none of the above are true, do nothing.
        const default_action = NoAction;
    }

    apply {
        significand_sum.apply();
    }
}

#endif /* _SIGNIFICAND_SUM_ */
