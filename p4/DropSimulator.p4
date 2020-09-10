// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _DROP_SIMULATOR_
#define _DROP_SIMULATOR_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

// // use in ingress to capture random number for simulating drops
// control DropRNG(
//     //in ingress_intrinsic_metadata_t ig_intr_md,
//     inout drop_random_value_t drop_random_value) {

//     // Random number generator
//     Random<drop_random_value_t>() rng;

//     // // Hash timestamp to approximate random number
//     // // (in case we didn't want to use the random number generator)
//     // Hash<bit<12>>(HashAlgorithm_t.RANDOM) hash;
    
//     apply {
//         drop_random_value = rng.get();
//         //ig_md.drop_random_value = hash.get({ig_intr_md.ingress_mac_tstamp});
//     }
// }

//
// ingress drop simulation takes place in update_and_check_worker_bitmap table.
//

// use in egress to simulate drops of packets leaving the switch
control EgressDropSimulator(
    inout switchml_md_h switchml_md,
    inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {

    Random<drop_probability_t>() rng;
    //Random<drop_random_value_t>() rng;
    //drop_probability_t random_value;
    drop_probability_t drop_probability;
    drop_probability_t random_value;
    drop_probability_t drop_value;
    
    action drop() {
        switchml_md.packet_type = packet_type_t.IGNORE;
        eg_dprsr_md.drop_ctl[0:0] = 1;
    }

    action set_drop_probability(drop_probability_t probability) {
        drop_probability = probability;
    }
    
    table probability_store {
        actions = {
            @defaultonly set_drop_probability;
            @defaultonly NoAction;
        }
        default_action = NoAction;
        size = 1;
    }
    
    apply {
        probability_store.apply();
        //random_value = rng.get();
        //drop_value = drop_probability - (1w0 ++ rng.get());
        drop_value = drop_probability |-| rng.get();

        //if (drop_value[15:15] == 1) { //}
        
        // if (drop_value != 0) {
        //     drop();
        // }
    }
}


#endif /* _DROP_SIMULATOR_ */
