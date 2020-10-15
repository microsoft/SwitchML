// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _DEBUG_LOG_
#define _DEBUG_LOG_

typedef bit<32> packet_id_counter_data_t;
typedef bit<1> packet_id_counter_index_t;

control DebugPacketId(
    in header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md) {

    // Single-entry counter
    Register<packet_id_counter_data_t, packet_id_counter_index_t>(1) counter;


    // increment counter, returning previous value
    RegisterAction<packet_id_counter_data_t, packet_id_counter_index_t, packet_id_counter_data_t>(counter) count_action = {
        void apply(inout packet_id_counter_data_t data, out packet_id_counter_data_t result) {
            result = data;
            data = data + 1;
        }
    };
    
    action do_count() {
        ig_md.switchml_md.debug_packet_id = (debug_packet_id_t) count_action.execute(0);
    }

    table packet_id_gen {
        actions = {
            @defaultonly do_count;
        }
        const default_action = do_count();
    }

    apply {
        packet_id_gen.apply();
    }
}



typedef bit<32> log_data_t;
typedef bit<32> timestamp_t;
struct log_pair_t {
    timestamp_t addr;
    log_data_t data;
}

typedef bit<32> log_index_t;

control DebugLog(
    in header_t hdr,
    in ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md) {

    // temporary variables for constructing the log
    bool bitmap_before_nonzero = false;
    bool map_result_nonzero = false;
    bool first_flag = false;
    bool last_flag = false;
    bool simulate_ingress_drop = false;
    bool first_packet_of_message = false; // rdma first_packet or udp any packet
    bool last_packet_of_message = false; // rdma first_packet or udp any packet
    bit<8> address_bits;
    
    // // BUG: Doesn't work. See below.
    // Hash<bit<51>>(HashAlgorithm_t.IDENTITY) data_hash;
    // bit<51> data_hash_result;

    // log seems limited to 2048 entries
    //const log_index_t log_size = 2048;
    //const log_index_t log_size = 4096;
    const log_index_t log_size = 22528;
    
    Register<log_pair_t, log_index_t>(log_size) log;

    RegisterAction<log_pair_t, log_index_t, log_data_t>(log) log_action = {
        void apply(inout log_pair_t value) {
            // This uses all 51 bits in the hash. More (with larger packet id) seems to be problematic.
            //value.addr = (bit<32>) ig_md.switchml_md.debug_packet_id;
            value.addr = (bit<32>) (address_bits ++ ig_md.switchml_md.debug_packet_id[10:0]);
            value.data = (
                ig_md.switchml_md.ingress_port[8:7] ++ // capture pipeline ID packet came in on
                ig_md.switchml_md.worker_id[4:0] ++ // limit to 32 workers for now.
                (bit<1>) first_packet_of_message ++
                (bit<1>) last_packet_of_message ++
                (bit<1>) bitmap_before_nonzero ++
                (bit<1>) map_result_nonzero ++
                (bit<1>) first_flag ++
                (bit<1>) last_flag ++
                (packet_type_underlying_t) ig_md.switchml_md.packet_type ++
                ig_md.switchml_md.pool_index[14:0]);

            // Alternative implementation that doesn't work
            //value.addr = (bit<32>) data_hash_result[50:32];
            //value.data = data_hash_result[31:0];
        }
    };

    apply {
        // Convert various things to single bits for logging
        if (ig_md.switchml_md.map_result           != 0) { map_result_nonzero = true; }
        if (ig_md.switchml_md.worker_bitmap_before != 0) { bitmap_before_nonzero = true; }
        if (ig_md.switchml_md.first_last_flag      == 0) { first_flag = true; }
        if (ig_md.switchml_md.first_last_flag      == 1) { last_flag  = true; }
        if (!ig_md.switchml_rdma_md.isValid() || ig_md.switchml_rdma_md.first_packet) { first_packet_of_message  = true; }
        if (!ig_md.switchml_rdma_md.isValid() || ig_md.switchml_rdma_md.last_packet) { last_packet_of_message  = true; }

        // copy lower 8 address/index bits 
        if (ig_md.switchml_rdma_md.isValid() && ig_md.switchml_md.packet_size == packet_size_t.IBV_MTU_1024) {
            address_bits = ig_md.switchml_rdma_md.rdma_addr[17:10];
        } else if (ig_md.switchml_rdma_md.isValid() && ig_md.switchml_md.packet_size == packet_size_t.IBV_MTU_256) {
            address_bits = ig_md.switchml_rdma_md.rdma_addr[15:8];
        }
        // // TODO: add support for SwitchML UDP
        // else { address_bits = ig_md.switchml_md.tsi[7:0]; }
            
        // // Alternative implementatation
        // // BUG:
        // // In file: /bf-sde/submodules/bf-p4c-compilers/p4c/extensions/bf-p4c/mau/instruction_adjustment.cpp:989
        // // Compiler Bug: /u/jacob/SwitchML/p4/DebugLog.p4(59): The input ingress::debug_log_data_hash_result[31:0]; to the stateful alu Ingress.debug_log.log cannot be found on the hash input
        // //             data.data = data_hash_result[31:0];
        // data_hash_result = data_hash.get({
        //         ig_md.switchml_md.debug_packet_id,
        //         ig_md.switchml_md.ingress_port[8:7],
        //         ig_md.switchml_md.worker_id[4:0],
        //         (bit<1>) first_packet_of_message,
        //         (bit<1>) last_packet_of_message,
        //         (bit<1>) bitmap_before_nonzero,
        //         (bit<1>) map_result_nonzero,
        //         (bit<1>) first_flag,
        //         (bit<1>) last_flag,
        //         (packet_type_underlying_t) ig_md.switchml_md.packet_type,
        //         ig_md.switchml_md.pool_index[14:0]});
        
        // Log this packet unconditionally
        log_action.execute_log();        
    }
}

#endif /* _DEBUG_LOG_ */
