#ifndef _REGISTERS_
#define _REGISTERS_

#include "types.p4"

//
// Define a register, actions, and table.
// Each register holds a pair of values.
// Each ALU supports up to 4 register actions. 
//
// Parameters:
// * PAIR_T: data pair type for storage in register
// * INDEX_T: register index type
// * RETURN_T: data type for returning values from register action
// * PREFIX: text used to construct names of reigsters, register actions, etc.
// * SIZE: number of elements in each register
// * DATA_NAME: name of data element in header, followed by numeric suffix
// * NN: numeric suffix for data elements in header
//
#define REGISTER(PAIR_T, INDEX_T, RETURN_T, PREFIX, SIZE, DATA_NAME, NN)             \
                                                                                     \
Register<PAIR_T, INDEX_T>(SIZE) PREFIX##_##NN;                                       \
                                                                                     \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(PREFIX##_##NN) PREFIX##_##NN##_write = {     \
    void apply(inout PAIR_T value) {                                                 \
        value.first  = hdr.d0.##DATA_NAME##NN;                                       \
        value.second = hdr.d1.##DATA_NAME##NN;                                       \
    }                                                                                \
};                                                                                   \
                                                                                     \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(PREFIX##_##NN) PREFIX##_##NN##_add_read0 = { \
    void apply(inout PAIR_T value, out RETURN_T read_value) {                                                 \
        value.first  = value.first  + hdr.d0.##DATA_NAME##NN;                        \
        value.second = value.second + hdr.d1.##DATA_NAME##NN;                        \
        read_value = value.first;                                                         \
    }                                                                                \
};                                                                                   \
                                                                                     \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(PREFIX##_##NN) PREFIX##_##NN##_max_read0 = { \
    void apply(inout PAIR_T value, out RETURN_T read_value) {                                                 \
        value.first  = max(value.first, hdr.d0.##DATA_NAME##NN);                     \
        value.second = max(value.second, hdr.d1.##DATA_NAME##NN);                    \
        read_value = value.first;                                                         \
    }                                                                                \
};                                                                                   \
                                                                                     \
RegisterAction<PAIR_T, INDEX_T, RETURN_T>(PREFIX##_##NN) PREFIX##_##NN##_read1 = {     \
    void apply(inout PAIR_T value, out RETURN_T read_value) {                          \
        read_value = value.second;                                                   \
    }                                                                                \
};                                                                                   \
                                                                                     \
action write_##NN##() {                                                              \
    PREFIX##_##NN##_write.execute(ig_md.address);                                     \
}                                                                                    \
action add_read0_##NN##() {                                                          \
    hdr.d0.##DATA_NAME##NN = PREFIX##_##NN##_add_read0.execute(ig_md.address);              \
}                                                                                    \
action max_read0_##NN##() {                                                          \
    hdr.d0.##DATA_NAME##NN = PREFIX##_##NN##_max_read0.execute(ig_md.address);              \
}                                                                                    \
action read1_##NN##() {                                                              \
    hdr.d1.##DATA_NAME##NN = PREFIX##_##NN##_read1.execute(ig_md.address);            \
}                                                                                    \
                                                                                     \
table PREFIX##_##NN##_tbl {                                                               \
    key = {                                                                          \
        ig_md.opcode : exact;                                                        \
    }                                                                                \
    actions = {                                                                      \
        NoAction;                                                                    \
        write_##NN;                                                                  \
        add_read0_##NN;                                                              \
        max_read0_##NN;                                                              \
        read1_##NN;                                                                  \
    }                                                                                \
                                                                                     \
    const default_action = NoAction;                                                 \
    size = 4;                                                                        \
}

// instantiate four registers for a particular pipeline stage
#define STAGE(PAIR_T, INDEX_T, RETURN_T, PREFIX, SIZE, DATA_NAME, AA, BB, CC, DD) \
REGISTER(PAIR_T, INDEX_T, RETURN_T, PREFIX, SIZE, DATA_NAME, AA)                  \
REGISTER(PAIR_T, INDEX_T, RETURN_T, PREFIX, SIZE, DATA_NAME, BB)                  \
REGISTER(PAIR_T, INDEX_T, RETURN_T, PREFIX, SIZE, DATA_NAME, CC)                  \
REGISTER(PAIR_T, INDEX_T, RETURN_T, PREFIX, SIZE, DATA_NAME, DD)

// apply tables for a single register
#define APPLY_REGISTER(PREFIX, NN) \
PREFIX##_##NN##_tbl.apply()

// apply tables for a particular pipeline stage
#define APPLY_STAGE(PREFIX, AA, BB, CC, DD) \
APPLY_REGISTER(PREFIX, AA);                 \
APPLY_REGISTER(PREFIX, BB);                 \
APPLY_REGISTER(PREFIX, CC);                 \
APPLY_REGISTER(PREFIX, DD)

#endif /* _REGISTERS_ */
