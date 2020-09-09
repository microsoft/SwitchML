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
control SignificandStage(
    in significand_t significand0a,
    in significand_t significand0b,
    in significand_t significand1a,
    in significand_t significand1b,
    in significand_t significand2a,
    in significand_t significand2b,
    in significand_t significand3a,
    in significand_t significand3b,
    out significand_t significand0a_out,
    out significand_t significand0b_out,
    out significand_t significand1a_out,
    out significand_t significand1b_out,
    out significand_t significand2a_out,
    out significand_t significand2b_out,
    out significand_t significand3a_out,
    out significand_t significand3b_out,
    inout switchml_md_h switchml_md) {

    SignificandSum() sum0;
    SignificandSum() sum1;
    SignificandSum() sum2;
    SignificandSum() sum3;
    
    apply {
        sum0.apply(significand0a, significand0b, significand0a_out, significand0b_out, switchml_md);
        sum1.apply(significand1a, significand1b, significand1a_out, significand1b_out, switchml_md);
        sum2.apply(significand2a, significand2b, significand2a_out, significand2b_out, switchml_md);
        sum3.apply(significand3a, significand3b, significand3a_out, significand3b_out, switchml_md);
    }
}

#endif /* _SIGNIFICAND_STAGE_ */
