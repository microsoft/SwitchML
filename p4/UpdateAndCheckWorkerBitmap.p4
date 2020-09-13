// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _UPDATE_WORKER_BITMAP_
#define _UPDATE_WORKER_BITMAP_

control UpdateAndCheckWorkerBitmap(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    //Hash<drop_probability_t>(HashAlgorithm_t.RANDOM) rng;
    //Random<drop_probability_t>() rng;

    //drop_probability_t drop_calculation;

    Register<worker_bitmap_pair_t, pool_index_by2_t>(num_slots) worker_bitmap;

    RegisterAction<worker_bitmap_pair_t, pool_index_by2_t, worker_bitmap_t>(worker_bitmap) worker_bitmap_update_set0 = {
        void apply(inout worker_bitmap_pair_t value, out worker_bitmap_t return_value) {
            //if (ig_md.drop_calculation == 0) {
                return_value = value.first; // return first set
                value.first  = value.first  | ig_md.worker_bitmap;    // add bit to first set
                // // TODO: BUG: this works around a compiler bug; remove outer ~ after it's fixed
                // value.second = ~(value.second & (~ig_md.worker_bitmap)); // remove bit from second set
                // This is the correct computation that works with SDE 9.1.0 and above
                value.second = value.second & (~ig_md.worker_bitmap); // remove bit from second set
            //}
        }
    };

    RegisterAction<worker_bitmap_pair_t, pool_index_by2_t, worker_bitmap_t>(worker_bitmap) worker_bitmap_update_set1 = {
        void apply(inout worker_bitmap_pair_t value, out worker_bitmap_t return_value) {
            //if (ig_md.drop_calculation == 0) {
                return_value = value.second; // return second set
                // // TODO: BUG: this works around a compiler bug; remove outer ~ after it's fixed
                // value.first  = ~(value.first  & (~ig_md.worker_bitmap)); // remove bit from first set
                // This is the correct computation that works with SDE 9.1.0 and above
                value.first  = value.first & (~ig_md.worker_bitmap); // remove bit from first set
                value.second = value.second | ig_md.worker_bitmap;    // add bit to second set
            //}
        }
    };

    action drop() {
        // mark for drop; mark as IGNORE so we don't further process this packet
        ig_dprsr_md.drop_ctl[0:0] = 1;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
    }

    action simulate_drop() {
        drop();
    }
    
    action check_worker_bitmap_action() {
        // set map result to nonzero if this packet is a retransmission
        ig_md.switchml_md.map_result = ig_md.switchml_md.worker_bitmap_before & ig_md.worker_bitmap;
        // compute same updated bitmap that was stored in the register
        //ig_md.switchml_md.worker_bitmap_after = ig_md.switchml_md.worker_bitmap_before | ig_md.worker_bitmap;

        // store original ingress port to be used in retransmissions (TODO: use worker ID instead?)
        ig_md.switchml_md.ingress_port = ig_intr_md.ingress_port;

    }    

    action update_worker_bitmap_set0_action() {
        ig_md.switchml_md.worker_bitmap_before = worker_bitmap_update_set0.execute(ig_md.switchml_md.pool_index[14:1]);
        check_worker_bitmap_action();
    }

    action update_worker_bitmap_set1_action() {
        ig_md.switchml_md.worker_bitmap_before = worker_bitmap_update_set1.execute(ig_md.switchml_md.pool_index[14:1]);
        check_worker_bitmap_action();
    }

    table update_and_check_worker_bitmap {
        key = {
            //ig_md.pool_set : ternary;
            ig_md.switchml_md.pool_index : ternary;
            ig_md.switchml_md.packet_type : ternary;  // only act on packets of type CONSUME0
            //ig_md.pool_remaining : ternary; // if sign bit is set, pool index was too large, so drop
            ig_md.port_metadata.ingress_drop_probability : ternary; // if nonzero, drop packet
            //ig_md.drop_calculation : ternary; // if sign bit is set, pool index was too large, so drop
            //drop_calculation : ternary; // if sign bit is set, pool index was too large, so drop
            // TODO: disable for now
            //ig_md.switchml_md.drop_random_value : range; // use to simulate drops
        }
        actions = {
            update_worker_bitmap_set0_action;
            update_worker_bitmap_set1_action;
            drop;
            simulate_drop;
            NoAction;
        }
        const entries = {
            // drop packets indicated by the drop simulator
            (            _, packet_type_t.CONSUME0, 0xffff) : simulate_drop();
            
            // direct updates to the correct set
            (15w0 &&& 15w1, packet_type_t.CONSUME0,      _) : update_worker_bitmap_set0_action();
            (15w1 &&& 15w1, packet_type_t.CONSUME0,      _) : update_worker_bitmap_set1_action();

            
            // // drop packets that have indices that extend beyond what's allowed
            // (            _, packet_type_t.CONSUME0, 0x8000 &&& 0x8000) : drop();

            // // direct updates to the correct set
            // (15w0 &&& 15w1, packet_type_t.CONSUME, 0x0000 &&& 0x8000,                 _) : update_worker_bitmap_set0_action();
            // (15w1 &&& 15w1, packet_type_t.CONSUME, 0x0000 &&& 0x8000,                 _) : update_worker_bitmap_set1_action();
            // // drop packets that have indices that extend beyond what's allowed
            // (            _, packet_type_t.CONSUME, 0x8000 &&& 0x8000,                 _) : drop();
            // drop packets that have been randomly selected
            //(            _, packet_type_t.CONSUME,                 _, 0x8000 &&& 0x8000) : drop();
        }
        const default_action = NoAction;
    }

    //Random<drop_probability_t>() rng;
    
    apply {
        //ig_md.drop_calculation = rng.get({ig_intr_md.ingress_mac_tstamp});
        //drop_calculation = rng.get({ig_intr_md.ingress_mac_tstamp});
        //drop_calculation = rng.get();

        update_and_check_worker_bitmap.apply();
        
        // ig_md.drop_calculation = ig_md.drop_calculation |-| rng.get();

        // if (ig_md.drop_calculation != 0) {
        //     update_and_check_worker_bitmap.apply();
        // } else {
        //     drop();
        // }
        
    }
}


#endif /* _UPDATE_WORKER_BITMAP_ */
