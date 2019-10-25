/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _UPDATE_WORKER_BITMAP_
#define _UPDATE_WORKER_BITMAP_

control UpdateAndCheckWorkerBitmap(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Register<worker_bitmap_pair_t, pool_index_t>(num_pools) worker_bitmap;

    RegisterAction<worker_bitmap_pair_t, pool_index_t, worker_bitmap_t>(worker_bitmap) worker_bitmap_update_set0 = {
        void apply(inout worker_bitmap_pair_t value, out worker_bitmap_t return_value) {
            return_value = value.first; // return first set
            value.first  = value.first  | ig_md.worker_bitmap;    // add bit to first set
            value.second = value.second & (~ig_md.worker_bitmap); // remove bit from second set
        }
    };

    RegisterAction<worker_bitmap_pair_t, pool_index_t, worker_bitmap_t>(worker_bitmap) worker_bitmap_update_set1 = {
        void apply(inout worker_bitmap_pair_t value, out worker_bitmap_t return_value) {
            return_value = value.second; // return second set
            value.first  = value.first  & (~ig_md.worker_bitmap); // remove bit from first set
            value.second = value.second | ig_md.worker_bitmap;    // add bit to second set
        }
    };

    action drop() {
        // mark for drop; mark as IGNORE so we don't further process this packet
        ig_dprsr_md.drop_ctl = ig_dprsr_md.drop_ctl | 0x1;
        hdr.switchml_md.packet_type = packet_type_t.IGNORE;
    }

    action check_worker_bitmap_action() {
        // set map result to nonzero if this packet is a retransmission
        ig_md.map_result          = ig_md.worker_bitmap_before & ig_md.worker_bitmap;
        // compute same updated bitmap that was stored in the register
        ig_md.worker_bitmap_after = ig_md.worker_bitmap_before | ig_md.worker_bitmap;
    }    

    action update_worker_bitmap_set0_action() {
        ig_md.worker_bitmap_before = worker_bitmap_update_set0.execute(hdr.switchml_md.pool_index);
        check_worker_bitmap_action();
    }

    action update_worker_bitmap_set1_action() {
        ig_md.worker_bitmap_before = worker_bitmap_update_set1.execute(hdr.switchml_md.pool_index);
        check_worker_bitmap_action();
    }

    table update_and_check_worker_bitmap {
        key = {
            ig_md.pool_set : ternary;
            hdr.switchml_md.packet_type : ternary;  // only act on packets of type CONSUME
            ig_md.pool_remaining : ternary; // if sign bit is set, pool index was too large, so drop
            // TODO: disable for now
            //hdr.switchml_md.drop_random_value : range; // use to simulate drops
        }
        actions = {
            update_worker_bitmap_set0_action;
            update_worker_bitmap_set1_action;
            drop;
            NoAction;
        }
        size = 3;
        const default_action = NoAction;
    }

    apply {
        update_and_check_worker_bitmap.apply();
    }
}


#endif /* _UPDATE_WORKER_BITMAP_ */
