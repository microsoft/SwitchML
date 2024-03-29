// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _EXPONENT_MAX_
#define _EXPONENT_MAX_

#include "types.p4"
#include "headers.p4"

// Exponent max value calculator
//
// Each control handles two exponents.
control ExponentMax(
    in exponent8_t exponent0,
    in exponent8_t exponent1,
    out exponent8_t max_exponent0,
    out exponent8_t max_exponent1,
    in ingress_metadata_t ig_md) {

    Register<exponent8_pair_t, pool_index_t>(register_size) exponents;

    // Write both exponents and read first one
    RegisterAction<exponent8_pair_t, pool_index_t, exponent8_t>(exponents) exponent_write_read0_register_action = {
        void apply(inout exponent8_pair_t value, out exponent8_t read_value) {
            value.first = exponent0;
            value.second = exponent1;
            read_value = value.first;
        }
    };

    action exponent_write_read0_action() {
        max_exponent0 = exponent_write_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // compute max of both exponents and read first one
    RegisterAction<exponent8_pair_t, pool_index_t, exponent8_t>(exponents) exponent_max_read0_register_action = {
        void apply(inout exponent8_pair_t value, out exponent8_t read_value) {
            value.first  = max(value.first,  exponent0);
            value.second = max(value.second, exponent1);
            read_value = value.first;
        }
    };

    action exponent_max_read0_action() {
        max_exponent0 = exponent_max_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // read first max register
    RegisterAction<exponent8_pair_t, pool_index_t, exponent8_t>(exponents) exponent_read0_register_action = {
        void apply(inout exponent8_pair_t value, out exponent8_t read_value) {
            read_value = value.first;
        }
    };

    action exponent_read0_action() {
        max_exponent0 = exponent_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // read second max register
    RegisterAction<exponent8_pair_t, pool_index_t, exponent8_t>(exponents) exponent_read1_register_action = {
        void apply(inout exponent8_pair_t value, out exponent8_t read_value) {
            read_value = value.second;
        }
    };

    action exponent_read1_action() {
        max_exponent1 = exponent_read1_register_action.execute(ig_md.switchml_md.pool_index);
    }

    /* If bitmap_before is 0 and type is CONSUME0, just write values. */
    /* If bitmap_before is not zero and type is CONSUME0, compute max of values and read first value. */
    /* If map_result is not zero and type is CONSUME0, just read first value. */
    /* If type is HARVEST, read second value. */
    table exponent_max {
        key = {
            ig_md.worker_bitmap_before : ternary;
            ig_md.map_result : ternary;
            ig_md.switchml_md.packet_type: ternary;
        }
        actions = {
            exponent_write_read0_action;
            exponent_max_read0_action;
            exponent_read0_action;
            exponent_read1_action;
            NoAction;
        }
        size = 4;
        const entries = {
            // if bitmap_before is all 0's and type is CONSUME0, this is the first packet for slot, so just write values and read first value
            (32w0,    _, packet_type_t.CONSUME0) : exponent_write_read0_action();
            // if bitmap_before is nonzero, map_result is all 0's,  and type is CONSUME0, compute max of values and read first value
            (   _, 32w0, packet_type_t.CONSUME0) : exponent_max_read0_action();
            // if bitmap_before is nonzero, map_result is nonzero, and type is CONSUME0, this is a retransmission, so just read first value
            (   _,    _, packet_type_t.CONSUME0) : exponent_read0_action();
            // if type is HARVEST, read second value
            (   _,    _, packet_type_t.HARVEST7) : exponent_read1_action();
        }
        // if none of the above are true, do nothing.
        const default_action = NoAction;
    }

    apply {
        exponent_max.apply();
    }
}

#endif /* _EXPONENT_MAX_ */
