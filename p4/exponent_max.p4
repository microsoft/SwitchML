/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _EXPONENT_MAX_
#define _EXPONENT_MAX_

#include "types.p4"
#include "headers.p4"

// Exponent max value calculator
//
// Each control handles two exponents.
// Since the same max operation can be repeated with the same result, we don't check for retransmissions here.
control ExponentMax(
    in exponent_t exponent0,
    in exponent_t exponent1,
    out exponent_t max_exponent0,
    out exponent_t max_exponent1,
    in header_t hdr,
    inout ingress_metadata_t ig_md) {

    Register<exponent_pair_t, pool_index_t>(num_pools) exponents;

    // Write both exponents and read first one
    RegisterAction<exponent_pair_t, pool_index_t, exponent_t>(exponents) exponent_write_read0_register_action = {
        void apply(inout exponent_pair_t value, out exponent_t read_value) {
            value.first = exponent0;
            value.second = exponent1;
            read_value = value.first;
        }
    };

    action exponent_write_read0_action() {
        max_exponent0 = exponent_write_read0_register_action.execute(hdr.switchml_md.pool_index);
    }

    // compute max of both exponents and read first one
    RegisterAction<exponent_pair_t, pool_index_t, exponent_t>(exponents) exponent_max_read0_register_action = {
        void apply(inout exponent_pair_t value, out exponent_t read_value) {
            value.first  = max(value.first,  exponent0);
            value.second = max(value.second, exponent1);
            read_value = value.first;
        }
    };

    action exponent_max_read0_action() {
        max_exponent0 = exponent_max_read0_register_action.execute(hdr.switchml_md.pool_index);
    }

    // read first max register
    RegisterAction<exponent_pair_t, pool_index_t, exponent_t>(exponents) exponent_read0_register_action = {
        void apply(inout exponent_pair_t value, out exponent_t read_value) {
            read_value = value.first;
        }
    };

    action exponent_read0_action() {
        max_exponent0 = exponent_read0_register_action.execute(hdr.switchml_md.pool_index);
    }

    // read second max register
    RegisterAction<exponent_pair_t, pool_index_t, exponent_t>(exponents) exponent_read1_register_action = {
        void apply(inout exponent_pair_t value, out exponent_t read_value) {
            read_value = value.second;
        }
    };

    action exponent_read1_action() {
        max_exponent1 = exponent_read1_register_action.execute(hdr.switchml_md.pool_index);
    }

    /* If bitmap_before is 0 and type is CONSUME, just write values. */
    /* If bitmap_before is not zero and type is CONSUME, add values and read first value. */
    /* If map_result is not zero and type is CONSUME, just read first value. */
    /* If type is HARVEST, read second value. */
    table exponent_max {
        key = {
            ig_md.worker_bitmap_before : ternary;
            ig_md.map_result : ternary;
            hdr.switchml_md.packet_type: ternary;
        }
        actions = {
            exponent_write_read0_action;
            exponent_max_read0_action;
            exponent_read0_action;
            exponent_read1_action;
        }
        size = 4;
    }

    apply {
        exponent_max.apply();
    }
}

#endif /* _EXPONENT_MAX_ */
