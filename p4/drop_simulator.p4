/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _DROP_SIMULATOR_
#define _DROP_SIMULATOR_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

// use in ingress to capture random number for simulating drops
control DropRNG(
    //in ingress_intrinsic_metadata_t ig_intr_md,
    inout drop_random_value_t drop_random_value) {

    // Random number generator
    Random<drop_random_value_t>() rng;

    // // Hash timestamp to approximate random number
    // // (in case we didn't want to use the random number generator)
    // Hash<bit<12>>(HashAlgorithm_t.RANDOM) hash;
    
    apply {
        drop_random_value = rng.get();
        //ig_md.drop_random_value = hash.get({ig_intr_md.ingress_mac_tstamp});
    }
}

//
// ingress drop simulation takes place in update_and_check_worker_bitmap table.
//

// use in egress to simulate drops of packets leaving the switch
control EgressDropSimulator(
    inout switchml_md_h switchml_md,
    inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {

    action drop() {
        eg_dprsr_md.drop_ctl = eg_dprsr_md.drop_ctl | 0x1;
        // get rid of SwitchML metadata header to indicate to later stages that packet should be ignored
        switchml_md.setInvalid();
    }

    table egress_drop {
        key = {
            switchml_md.drop_random_value : range;
        }
        actions = {
            drop;
            NoAction;
        }
        size = 2;
    }
    
    apply {
        egress_drop.apply();
    }
}


#endif /* _DROP_SIMULATOR_ */
