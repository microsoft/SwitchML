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
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    apply {
        // recirculate for harvest
        ig_tm_md.ucast_egress_port = ig_intr_md.ingress_port[8:7] ++ 7w68;
        ig_tm_md.bypass_egress = 1w1;
        hdr.switchml_md.packet_type = packet_type_t.HARVEST;
        hdr.switchml_md.opcode = opcode_t.READ1;
    }
}

#endif /* _RECIRCULATE_FOR_HARVEST_ */
