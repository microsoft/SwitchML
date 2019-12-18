/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _MANTISSA_SUM_
#define _MANTISSA_SUM_

#include "types.p4"
#include "headers.p4"

// Mantissa sum value calculator
//
// Each control handles two mantissas.
control MantissaSum(
    inout mantissa_t mantissa0,
    inout mantissa_t mantissa1,
    in header_t hdr,
    inout ingress_metadata_t ig_md) {

    Register<mantissa_pair_t, pool_index_t>(num_pools) mantissas;

    // Write both mantissas and read first one
    RegisterAction<mantissa_pair_t, pool_index_t, mantissa_t>(mantissas) mantissa_write_read0_register_action = {
        void apply(inout mantissa_pair_t value, out mantissa_t read_value) {
            value.first = mantissa0;
            value.second = mantissa1;
            read_value = value.first;
        }
    };

    action mantissa_write_read0_action() {
        mantissa0 = mantissa_write_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // compute sum of both mantissas and read first one
    RegisterAction<mantissa_pair_t, pool_index_t, mantissa_t>(mantissas) mantissa_sum_read0_register_action = {
        void apply(inout mantissa_pair_t value, out mantissa_t read_value) {
            value.first  = value.first  + mantissa0;
            value.second = value.second + mantissa1;
            read_value = value.first;
        }
    };

    action mantissa_sum_read0_action() {
        mantissa0 = mantissa_sum_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // read first sum register
    RegisterAction<mantissa_pair_t, pool_index_t, mantissa_t>(mantissas) mantissa_read0_register_action = {
        void apply(inout mantissa_pair_t value, out mantissa_t read_value) {
            read_value = value.first;
        }
    };

    action mantissa_read0_action() {
        mantissa0 = mantissa_read0_register_action.execute(ig_md.switchml_md.pool_index);
    }

    // read second sum register
    RegisterAction<mantissa_pair_t, pool_index_t, mantissa_t>(mantissas) mantissa_read1_register_action = {
        void apply(inout mantissa_pair_t value, out mantissa_t read_value) {
            read_value = value.second;
        }
    };

    action mantissa_read1_action() {
        mantissa1 = mantissa_read1_register_action.execute(ig_md.switchml_md.pool_index);
    }

    /* If bitmap_before is 0 and type is CONSUME, just write values. */
    /* If bitmap_before is not zero and type is CONSUME, add values and read first value. */
    /* If map_result is not zero and type is CONSUME, just read first value. */
    /* If type is HARVEST, read second value. */
    table mantissa_sum {
        key = {
            ig_md.switchml_md.worker_bitmap_before : ternary;
            ig_md.switchml_md.map_result : ternary;
            ig_md.switchml_md.packet_type: ternary;
        }
        actions = {
            mantissa_write_read0_action;
            mantissa_sum_read0_action;
            mantissa_read0_action;
            mantissa_read1_action;
            NoAction;
        }
        size = 4;
        const entries = {
            // if bitmap_before is all 0's and type is CONSUME, this is the first packet for slot, so just write values and read first value
            (32w0,    _, packet_type_t.CONSUME) : mantissa_write_read0_action();
            // if bitmap_before is nonzero, map_result is all 0's,  and type is CONSUME, compute sum of values and read first value
            (   _, 32w0, packet_type_t.CONSUME) : mantissa_sum_read0_action();
            // if bitmap_before is nonzero, map_result is nonzero, and type is CONSUME, this is a retransmission, so just read first value
            (   _,    _, packet_type_t.CONSUME) : mantissa_read0_action();
            // if type is HARVEST, read second value
            (   _,    _, packet_type_t.HARVEST) : mantissa_read1_action();
            // if bitmap_before is all 0's and type is CONSUME, this is the first packet for slot, so just write values and read first value
            (32w0,    _, packet_type_t.CONSUME) : mantissa_write_read0_action();
        }
        // if none of the above are true, do nothing.
        const default_action = NoAction;
    }

    apply {
        mantissa_sum.apply();
    }
}

#endif /* _MANTISSA_SUM_ */
