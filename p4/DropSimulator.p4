// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _DROP_SIMULATOR_
#define _DROP_SIMULATOR_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

control IngressDropSimulator(
    // used for drop probability and to signal ingress drop
    inout port_metadata_t port_metadata) {

    Random<drop_probability_t>() rng;
    
    apply {
        // If drop probability from parser is nonzero, decide if we should drop this packet.
        // Do so by adding random value to drop probability.
        // Use saturating addition so that the result never wraps around.
        // A result of 0xffff means to drop the packet.
        // This will be consumed later in the pipeline when checking bitmaps.
        if (port_metadata.ingress_drop_probability != 0) {
            port_metadata.ingress_drop_probability = rng.get() |+| port_metadata.ingress_drop_probability; 
        }

        // BUG: these seem to generate the same instruction. Grr.
        //port_metadata.ingress_drop_probability = rng.get() |-| port_metadata.ingress_drop_probability; 
        //port_metadata.ingress_drop_probability = port_metadata.ingress_drop_probability |-| rng.get();
    }
}

control EgressDropSimulator(
    // used for drop probability
    inout port_metadata_t port_metadata,
    // used to signal egress drop
    out bool simulate_egress_drop) {

    Random<drop_probability_t>() rng;
    
    apply {
        // If drop probability from parser is nonzero, decide if we should drop this packet.
        // Do so by adding random value to drop probability.
        // Use saturating addition so that the result never wraps around.
        // A result of 0xffff means to drop the packet.
        if (port_metadata.egress_drop_probability != 0) {
            port_metadata.egress_drop_probability = rng.get() |+| port_metadata.egress_drop_probability; 
        }
        
        simulate_egress_drop = false;
        if (port_metadata.egress_drop_probability == 0xffff) {
            simulate_egress_drop = true;
        }
    }
}


#endif /* _DROP_SIMULATOR_ */
