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
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Register<worker_bitmap_pair_t, pool_index_by2_t>(num_slots) worker_bitmap;

    RegisterAction<worker_bitmap_pair_t, pool_index_by2_t, worker_bitmap_t>(worker_bitmap) worker_bitmap_update_set0 = {
        void apply(inout worker_bitmap_pair_t value, out worker_bitmap_t return_value) {
            return_value = value.first; // return first set
            value.first  = value.first  | ig_md.worker_bitmap;    // add bit to first set
            // // TODO: BUG: this works around a compiler bug; remove outer ~ after it's fixed
            // value.second = ~(value.second & (~ig_md.worker_bitmap)); // remove bit from second set
            // This is the correct computation that works with SDE 9.1.0 and above
            value.second = value.second & (~ig_md.worker_bitmap); // remove bit from second set
        }
    };

    RegisterAction<worker_bitmap_pair_t, pool_index_by2_t, worker_bitmap_t>(worker_bitmap) worker_bitmap_update_set1 = {
        void apply(inout worker_bitmap_pair_t value, out worker_bitmap_t return_value) {
            return_value = value.second; // return second set
            // // TODO: BUG: this works around a compiler bug; remove outer ~ after it's fixed
            // value.first  = ~(value.first  & (~ig_md.worker_bitmap)); // remove bit from first set
            // This is the correct computation that works with SDE 9.1.0 and above
            value.first  = value.first & (~ig_md.worker_bitmap); // remove bit from first set
            value.second = value.second | ig_md.worker_bitmap;    // add bit to second set
        }
    };

    action drop() {
        // mark for drop; mark as IGNORE so we don't further process this packet
        ig_dprsr_md.drop_ctl = ig_dprsr_md.drop_ctl | 0x1;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
    }

    action check_worker_bitmap_action() {
        // set map result to nonzero if this packet is a retransmission
        ig_md.switchml_md.map_result = ig_md.switchml_md.worker_bitmap_before & ig_md.worker_bitmap;
        // compute same updated bitmap that was stored in the register
        ig_md.switchml_md.worker_bitmap_after = ig_md.switchml_md.worker_bitmap_before | ig_md.worker_bitmap;
        ig_md.switchml_md.ingress_port = ig_intr_md.ingress_port;
    }    

    action update_worker_bitmap_set0_action() {
        ig_md.switchml_md.worker_bitmap_before = worker_bitmap_update_set0.execute(ig_md.switchml_md.pool_index[16:1]);
        check_worker_bitmap_action();
    }

    action update_worker_bitmap_set1_action() {
        ig_md.switchml_md.worker_bitmap_before = worker_bitmap_update_set1.execute(ig_md.switchml_md.pool_index[16:1]);
        check_worker_bitmap_action();
    }

    table update_and_check_worker_bitmap {
        key = {
            ig_md.pool_set : ternary;
            ig_md.switchml_md.packet_type : ternary;  // only act on packets of type CONSUME
            ig_md.pool_remaining : ternary; // if sign bit is set, pool index was too large, so drop
            // TODO: disable for now
            //ig_md.switchml_md.drop_random_value : range; // use to simulate drops
        }
        actions = {
            update_worker_bitmap_set0_action;
            update_worker_bitmap_set1_action;
            drop;
            NoAction;
        }
        size = 3;
        const entries = {
            // direct updates to the correct set
            (1w0, packet_type_t.CONSUME, 0x0000 &&& 0x8000) : update_worker_bitmap_set0_action();
            (1w1, packet_type_t.CONSUME, 0x0000 &&& 0x8000) : update_worker_bitmap_set1_action();
            // drop packets that have indices that extend beyond what's allowed
            (  _, packet_type_t.CONSUME, 0x8000 &&& 0x8000) : drop();
        }
        const default_action = NoAction;
    }

    apply {
        update_and_check_worker_bitmap.apply();
    }
}


#endif /* _UPDATE_WORKER_BITMAP_ */
