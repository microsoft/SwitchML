/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _COUNT_WORKERS_
#define _COUNT_WORKERS_

control CountWorkers(
    in header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Register<num_workers_pair_t, pool_index_t>(num_pools) worker_count;

    RegisterAction<num_workers_pair_t, pool_index_t, num_workers_t>(worker_count) worker_count_action = {
        void apply(inout num_workers_pair_t value, out num_workers_t read_value) {
            read_value = value.first;
            if (value.first == 0) {
                value.first = ig_md.num_workers;
            } else {
                value.first = value.first - 1;
            }
        }
    };

    action count_workers_action() {
        ig_md.first_last_flag = worker_count_action.execute(hdr.switchml_md.pool_index);
    }

    RegisterAction<num_workers_pair_t, pool_index_t, num_workers_t>(worker_count) read_worker_count_action = {
        void apply(inout num_workers_pair_t value, out num_workers_t read_value) {
            read_value = value.first;
        }
    };

    action read_count_workers_action() {
        ig_md.first_last_flag = read_worker_count_action.execute(hdr.switchml_md.pool_index);
    }

    // if no bits are set in the map result, this was the first time we
    // saw this packet, so decrement worker count. Otherwise, it's a
    // retransmission, so just read the worker count.
    // Only act if packet type is CONSUME
    table count_workers {
        key = {
            ig_md.map_result : ternary;
            hdr.switchml_md.packet_type: exact;
        }
        actions = {
            count_workers_action;
            read_count_workers_action;
        }
        size = 4;
    }

    apply {
        count_workers.apply();
    }
}

#endif /* _COUNT_WORKERS_ */
