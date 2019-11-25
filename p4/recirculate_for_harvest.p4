/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _RECIRCULATE_FOR_HARVEST_
#define _RECIRCULATE_FOR_HARVEST_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

control RecirculateForHarvest(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    apply {
        // drop second data header, since first header has data we read out
        hdr.d1.setInvalid();
        
        // recirculate for harvest
        ig_tm_md.ucast_egress_port = ig_intr_md.ingress_port[8:7] ++ 7w68;
        ig_tm_md.bypass_egress = 1w1;
        ig_md.switchml_md.packet_type = packet_type_t.HARVEST;
    }
}

#endif /* _RECIRCULATE_FOR_HARVEST_ */
