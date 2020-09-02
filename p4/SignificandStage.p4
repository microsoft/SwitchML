/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _SIGNIFICAND_STAGE_
#define _SIGNIFICAND_STAGE_

#include "types.p4"
#include "headers.p4"

#include "SignificandSum.p4"

// Significand stage value calculator
//
// Each control handles two significands.
control SignificandStage<HDR_T, MD_T>(
    inout significand_t significand0a,
    inout significand_t significand0b,
    inout significand_t significand1a,
    inout significand_t significand1b,
    inout significand_t significand2a,
    inout significand_t significand2b,
    inout significand_t significand3a,
    inout significand_t significand3b,
    in header_t hdr,
    inout switchml_md_h switchml_md) {

    SignificandSum() sum0;
    SignificandSum() sum1;
    SignificandSum() sum2;
    SignificandSum() sum3;
    
    apply {
        sum0.apply(significand0a, significand0b, hdr, switchml_md);
        sum1.apply(significand1a, significand1b, hdr, switchml_md);
        sum2.apply(significand2a, significand2b, hdr, switchml_md);
        sum3.apply(significand3a, significand3b, hdr, switchml_md);
    }
}

#endif /* _SIGNIFICAND_STAGE_ */
