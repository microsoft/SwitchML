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
    inout switchml_md_h switchml_md) {

    Register<significand_pair_t, pool_index_t>(register_size) significands;

    // Write both significands and read first one
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_write_read1_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            value.first = significand0;
            value.second = significand1;
            read_value = value.second;
        }
    };

    action significand_write_read1_action() {
        significand1 = significand_write_read1_register_action.execute(switchml_md.pool_index);
    }

    // compute sum of both significands and read first one
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_sum_read1_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            value.first  = value.first  + significand0;
            value.second = value.second + significand1;
            read_value = value.second;
        }
    };

    action significand_sum_read1_action() {
        significand1 = significand_sum_read1_register_action.execute(switchml_md.pool_index);
    }

    // read first sum register
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_read0_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            read_value = value.first;
        }
    };

    action significand_read0_action() {
        significand0 = significand_read0_register_action.execute(switchml_md.pool_index);
    }

    // read second sum register
    RegisterAction<significand_pair_t, pool_index_t, significand_t>(significands) significand_read1_register_action = {
        void apply(inout significand_pair_t value, out significand_t read_value) {
            read_value = value.second;
        }
    };

    action significand_read1_action() {
        significand1 = significand_read1_register_action.execute(switchml_md.pool_index);
    }

    /* If bitmap_before is 0 and type is CONSUME0, write values and read second value. */
    /* If bitmap_before is not zero and type is CONSUME0, add values and read second value. */
    /* If map_result is not zero and type is CONSUME0, just read first value. */
    /* If type is HARVEST, read second value. */
    table significand_sum {
        key = {
            switchml_md.worker_bitmap_before : ternary;
            switchml_md.map_result : ternary;
            switchml_md.packet_type: ternary;
        }
        actions = {
            significand_write_read1_action;
            significand_sum_read1_action;
            significand_read0_action;
            significand_read1_action;
            NoAction;
        }
        size = 20;
        const entries = {
            // if bitmap_before is all 0's and type is CONSUME0, this is the first packet for slot, so just write values and read second value
            (32w0,    _, packet_type_t.CONSUME0) : significand_write_read1_action();
            (32w0,    _, packet_type_t.CONSUME1) : significand_write_read1_action();
            (32w0,    _, packet_type_t.CONSUME2) : significand_write_read1_action();
            (32w0,    _, packet_type_t.CONSUME3) : significand_write_read1_action();
            // if bitmap_before is nonzero, map_result is all 0's,  and type is CONSUME0, compute sum of values and read second value
            (   _, 32w0, packet_type_t.CONSUME0) : significand_sum_read1_action();
            (   _, 32w0, packet_type_t.CONSUME1) : significand_sum_read1_action();
            (   _, 32w0, packet_type_t.CONSUME2) : significand_sum_read1_action();
            (   _, 32w0, packet_type_t.CONSUME3) : significand_sum_read1_action();
            // if bitmap_before is nonzero, map_result is nonzero, and type is CONSUME0, this is a retransmission, so just read first value
            (   _,    _, packet_type_t.CONSUME0) : significand_read0_action();
            (   _,    _, packet_type_t.CONSUME1) : significand_read0_action();
            (   _,    _, packet_type_t.CONSUME2) : significand_read0_action();
            (   _,    _, packet_type_t.CONSUME3) : significand_read0_action();
            // if type is HARVEST, read one set of values based on sequence
            (   _,    _, packet_type_t.HARVEST0) : significand_read1_action(); // extract data1 slice in pipe 3
            (   _,    _, packet_type_t.HARVEST1) : significand_read0_action(); // extract data0 slice in pipe 3
            (   _,    _, packet_type_t.HARVEST2) : significand_read1_action(); // extract data1 slice in pipe 2
            (   _,    _, packet_type_t.HARVEST3) : significand_read0_action(); // extract data0 slice in pipe 2
            (   _,    _, packet_type_t.HARVEST4) : significand_read1_action(); // extract data1 slice in pipe 1
            (   _,    _, packet_type_t.HARVEST5) : significand_read0_action(); // extract data0 slice in pipe 1
            (   _,    _, packet_type_t.HARVEST6) : significand_read1_action(); // extract data1 slice in pipe 0
            (   _,    _, packet_type_t.HARVEST7) : significand_read0_action(); // last pass; extract data0 slice in pipe 0
        }
        // if none of the above are true, do nothing.
        const default_action = NoAction;
    }

    apply {
        significand_sum.apply();
        // if (switchml_md.packet_type == packet_type_t.CONSUME0) {
        //     if (switchml_md.worker_bitmap_before == 0) {
        //         significand_write_read0_action();
        //     } else if (switchml_md.map_result == 0) {
        //         significand_sum_read0_action();
        //     } else {
        //         significand_read0_action();
        //     }
        // } else {
        //     significand_read1_action();
        // }
    }
}

#endif /* _SIGNIFICAND_SUM_ */
