#ifndef _REGISTERS_
#define _REGISTERS_

#include "types.p4"

// // helper macro to swap bytes
// #define SWAP_BYTES(NAME) \
// (NAME[7:0] ++ NAME[15:8] ++ NAME[23:16] ++ NAME[31:24])

//
// Define a register, actions, and table.
// Each register holds a pair of values.
// Each ALU supports up to 4 register actions. 
//
// Parameters:
// * PAIR_T: data pair type for storage in register
// * INDEX_T: register index type
// * RETURN_T: data type for returning values from register action
// * REGISTER_NAME: text used to construct names of reigsters, register actions, etc.
// * SIZE: number of elements in each register
// * DATA0_NAME: name prefix of data element in first header, to be followed by numeric suffix
// * DATA1_NAME: name prefix of data element in second header, to be followed by numeric suffix
// * ADDRESS_NAME: name of address PHV
// * NN: numeric suffix for data elements in header
//
#define REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,             \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, NN)                   \
                                                                             \
Register<PAIR_T, INDEX_T>(SIZE) REGISTER_NAME##_##NN;                        \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_write_read0 = {                                             \
    void apply(inout PAIR_T value, out RETURN_T return_value) {              \
        value.first  = DATA0_NAME##NN;                                       \
        value.second = DATA1_NAME##NN;                                       \
        return_value = value.first;                                          \
    }                                                                        \
};                                                                           \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_add_read0 = {                                         \
    void apply(inout PAIR_T value, out RETURN_T return_value) {              \
        value.first  = value.first  + DATA0_NAME##NN;                        \
        value.second = value.second + DATA1_NAME##NN;                        \
        return_value = value.first;                                          \
    }                                                                        \
};                                                                           \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_read0 = {                                             \
    void apply(inout PAIR_T value, out RETURN_T return_value) {              \
        return_value = value.first;                                         \
    }                                                                        \
};                                                                           \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_read1 = {                                             \
    void apply(inout PAIR_T value, out RETURN_T return_value) {              \
        return_value = value.second;                                         \
    }                                                                        \
};                                                                           \
                                                                             \
action write_read0_##NN##() {                                                      \
    REGISTER_NAME##_##NN##_write_read0.execute(ADDRESS_NAME);                      \
}                                                                            \
action add_read0_##NN##() {                                                  \
    DATA0_NAME##NN = REGISTER_NAME##_##NN##_add_read0.execute(ADDRESS_NAME); \
}                                                                            \
action read0_##NN##() {                                                  \
    DATA0_NAME##NN = REGISTER_NAME##_##NN##_read0.execute(ADDRESS_NAME); \
}                                                                            \
action read1_##NN##() {                                                      \
    DATA0_NAME##NN = REGISTER_NAME##_##NN##_read1.execute(ADDRESS_NAME);     \
}                                                                            \
\
/* If bitmap_before is 0 and type is CONSUME, just write values. */ \
/* If bitmap_before is not zero and type is CONSUME, add values and read first value. */ \
/* If map_result is not zero and type is CONSUME, just read first value. */ \
/* If type is HARVEST, read second value. */ \
table REGISTER_NAME##_##NN##_tbl {                                           \
    key = {                                                                  \
        ig_md.worker_bitmap_before : ternary; \
        ig_md.map_result : ternary; \
        hdr.switchml_md.packet_type: ternary; \
    }                                                                        \
    actions = {                                                              \
        write_read0_##NN;                                                          \
        add_read0_##NN;                                                      \
        read0_##NN; \
        read1_##NN;                                                          \
    }                                                                        \
    size = 4;                                                                \
}

// instantiate four registers for a particular pipeline stage
#define STAGE(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE, \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME,        \
    AA, BB, CC, DD)                                           \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME,        \
    AA)                                                       \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME,        \
    BB)                                                       \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME,        \
    CC)                                                       \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME,        \
    DD)

// apply tables for a single register
#define APPLY_REGISTER(REGISTER_NAME, NN) \
REGISTER_NAME##_##NN##_tbl.apply()

// apply tables for a particular pipeline stage
#define APPLY_STAGE(REGISTER_NAME, AA, BB, CC, DD) \
APPLY_REGISTER(REGISTER_NAME, AA);                 \
APPLY_REGISTER(REGISTER_NAME, BB);                 \
APPLY_REGISTER(REGISTER_NAME, CC);                 \
APPLY_REGISTER(REGISTER_NAME, DD)

#endif /* _REGISTERS_ */
