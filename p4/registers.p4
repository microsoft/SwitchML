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
// * OPCODE_NAME: name of opcode PHV
// * NN: numeric suffix for data elements in header
//
#define REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,             \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, OPCODE_NAME, NN)                   \
                                                                             \
Register<PAIR_T, INDEX_T>(SIZE) REGISTER_NAME##_##NN;                        \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_write = {                                             \
    void apply(inout PAIR_T value) {                                         \
        value.first  = DATA0_NAME##NN;                                       \
        value.second = DATA1_NAME##NN;                                       \
    }                                                                        \
};                                                                           \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_add_read0 = {                                         \
    void apply(inout PAIR_T value, out RETURN_T read_value) {                \
        value.first  = value.first  + DATA0_NAME##NN;                        \
        value.second = value.second + DATA1_NAME##NN;                        \
        read_value = value.first;                                            \
    }                                                                        \
};                                                                           \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_max_read0 = {                                         \
    void apply(inout PAIR_T value, out RETURN_T read_value) {                \
        value.first  = max(value.first, DATA0_NAME##NN);                     \
        value.second = max(value.second, DATA1_NAME##NN);                    \
        read_value = value.first;                                            \
    }                                                                        \
};                                                                           \
                                                                             \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(REGISTER_NAME##_##NN)              \
REGISTER_NAME##_##NN##_read1 = {                                             \
    void apply(inout PAIR_T value, out RETURN_T read_value) {                \
        read_value = value.second;                                           \
    }                                                                        \
};                                                                           \
                                                                             \
action write_##NN##() {                                                      \
    REGISTER_NAME##_##NN##_write.execute(ADDRESS_NAME);                      \
}                                                                            \
action add_read0_##NN##() {                                                  \
    DATA0_NAME##NN = REGISTER_NAME##_##NN##_add_read0.execute(ADDRESS_NAME); \
}                                                                            \
action max_read0_##NN##() {                                                  \
    DATA0_NAME##NN = REGISTER_NAME##_##NN##_max_read0.execute(ADDRESS_NAME); \
}                                                                            \
action read1_##NN##() {                                                      \
    DATA1_NAME##NN = REGISTER_NAME##_##NN##_read1.execute(ADDRESS_NAME);     \
}                                                                            \
                                                                             \
table REGISTER_NAME##_##NN##_tbl {                                           \
    key = {                                                                  \
        OPCODE_NAME : exact;                                                 \
    }                                                                        \
    actions = {                                                              \
        NoAction;                                                            \
        write_##NN;                                                          \
        add_read0_##NN;                                                      \
        max_read0_##NN;                                                      \
        read1_##NN;                                                          \
    }                                                                        \
                                                                             \
    const default_action = NoAction;                                         \
    size = 4;                                                                \
}

// instantiate four registers for a particular pipeline stage
#define STAGE(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE, \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, OPCODE_NAME,        \
    AA, BB, CC, DD)                                           \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, OPCODE_NAME,        \
    AA)                                                       \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, OPCODE_NAME,        \
    BB)                                                       \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, OPCODE_NAME,        \
    CC)                                                       \
REGISTER(PAIR_T, INDEX_T, RETURN_T, REGISTER_NAME, SIZE,      \
    DATA0_NAME, DATA1_NAME, ADDRESS_NAME, OPCODE_NAME,        \
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
