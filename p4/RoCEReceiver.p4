/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _ROCERECEIVER_
#define _ROCERECEIVER_

/*


*/

typedef pool_index_t index_t;

// // 256-byte slots
// #define INDEX (hdr.ib_bth.dst_qp[14:1] ++ hdr.ib_bth.dst_qp[15:15])

// 512-byte slots
#define INDEX (hdr.ib_bth.dst_qp[13:1] ++ 1w0 ++ hdr.ib_bth.dst_qp[15:15])

//#define INDEX (hdr.ib_bth.dst_qp[14:1] ++ hdr.ib_bth.dst_qp[15:15])

//typedef bit<10> index_t;
//typedef bit<24> index_t;

//typedef bool    return_t;
//typedef bit<16> return_t;
typedef bit<32> return_t;

struct receiver_data_t {
    bit<32> next_sequence_number;
    bit<32> pool_index;
}
    
control RoCEReceiver(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {
    
    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) rdma_receive_counter;

    Register<receiver_data_t, index_t>(num_slots) receiver_data_register;
    Counter<counter_t, index_t>(num_slots, CounterType_t.PACKETS) rdma_message_counter;
    Counter<counter_t, index_t>(num_slots, CounterType_t.PACKETS) rdma_sequence_violation_counter;

    bool message_possibly_received;
    bool sequence_violation;
    
    return_t received_message;
    const return_t true_value  = 0x1;
    const return_t false_value = 0xffffffff;
    //const return_t false_value = false;
    
    const pool_index_t base_pool_index      = 0;
    const pool_index_t pool_index_increment = 2;
    
    // use with _FIRST and _ONLY packets
    RegisterAction<receiver_data_t, index_t, return_t>(receiver_data_register) receiver_reset_action = {
        void apply(inout receiver_data_t value, out return_t read_value) {
            value.next_sequence_number = (bit<32>) hdr.ib_bth.psn + 1; // reset sequence number
            value.pool_index = (bit<32>) hdr.ib_bth.dst_qp;   // reset pool index from QP number
            read_value = (return_t) value.pool_index;
        }
    };

    
    // use with _MIDDLE and _LAST packets
    RegisterAction<receiver_data_t, index_t, return_t>(receiver_data_register) receiver_increment_action = {
        void apply(inout receiver_data_t value, out return_t read_value) {
            if ((bit<32>) hdr.ib_bth.psn == value.next_sequence_number) {  // is this the next packet?
                value.next_sequence_number = (bit<32>) hdr.ib_bth.psn + 1; // yes, so store next psn
                value.pool_index           = value.pool_index + 2;         // and compute pool index
                read_value = value.pool_index;                             // return pool index
            } else {
                value.next_sequence_number = value.next_sequence_number;  // no, so leave psn unchanged
                value.pool_index           = 0xffffffff;                  // and return error value
                read_value = value.pool_index;
            }
        }
    };



    action set_bitmap(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap) {

        // bitmap representation for this worker
        ig_md.worker_bitmap   = worker_bitmap;
        ig_md.num_workers     = num_workers;

        // group ID for this job
        ig_md.switchml_md.mgid = mgid;

        ig_md.switchml_md.worker_type = worker_type;
        ig_md.switchml_md.worker_id = worker_id;     // Same as rid for worker; used when retransmitting RDMA packets
        ig_md.switchml_md.dst_port = hdr.udp.src_port;

        // TODO: copy immediate to exponents
        // TODO: copy address
        
        // get rid of headers we don't want to recirculate
        hdr.ethernet.setInvalid();
        hdr.ipv4.setInvalid();
        hdr.udp.setInvalid();
        hdr.ib_bth.setInvalid();
        hdr.ib_reth.setInvalid();
        hdr.ib_immediate.setInvalid();
        hdr.ib_icrc.setInvalid();

        //
        // Pool parameters
        //
        

        // move the SwitchML set bit in the MSB to the LSB to match existing software
        //ig_md.switchml_md.pool_index = receiver_increment_action.execute(hdr.switchml.pool_index[13:0] ++ hdr.switchml.pool_index[15:15])[14:0];
        //ig_md.switchml_md.pool_index = receiver_increment_action.execute(hdr.ib_bth.dst_qp)[14:0];
        //////ig_md.switchml_md.pool_index = (pool_index_t) receiver_increment_action.execute(INDEX);
        
        // // use LSB of pool index to determine which set this packet is targeting.
        // //ig_md.pool_set = hdr.switchml.pool_index[0:0];

        rdma_receive_counter.count();
    }

    action middle_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap);

        // process sequence number
        return_t result = receiver_increment_action.execute(INDEX);
        
        // if sign bit of result is set, there was a sequence violation, so ignore this packet.
        //ig_dprsr_md.drop_ctl[0:0] = ig_dprsr_md.drop_ctl[0:0] | result[31:31];
        ig_dprsr_md.drop_ctl[0:0] = result[31:31];

        // A message has not yet arrived, since this is a middle packet.
        message_possibly_received = false;
        sequence_violation = (bool) result[31:31];
    }

    action last_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap);

        // process sequence number
        return_t result = receiver_increment_action.execute(INDEX);
        //received_message = result;

        // if sign bit of result is set, there was a sequence violation, so ignore this packet.
        //ig_dprsr_md.drop_ctl[0:0] = ig_dprsr_md.drop_ctl[0:0] | result[31:31];
        ig_dprsr_md.drop_ctl[0:0] = result[31:31];

        // A message has arrived if the sequence number matched (sign bit == 0).
        message_possibly_received = true;
        sequence_violation = (bool) result[31:31];
    }

    action first_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap);

        // reset sequence number
        return_t result = receiver_reset_action.execute(INDEX);

        // This is a first packet, so there can be no sequence number violation.
        // Don't drop the packet.

        // A message has not yet arrived, since this is a first packet.
        message_possibly_received = false;
        sequence_violation = (bool) result[31:31];
    }
    
    action only_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap);

        // reset sequence number
        return_t result = receiver_reset_action.execute(INDEX);
        
        // This is an only packet, so there can be no sequence number violation.
        // Don't drop the packet.

        // A message has arrived, since this is an only packet.
        message_possibly_received = true;
        sequence_violation = (bool) result[31:31];
    }


    // The goal for this component is to receive a RoCE RDMA UC packet
    // stream, and to compute the correct slot ID for each packet.
    //
    // Since we can only provide the slot ID in the first packet of
    // the message (in the RDMA address header), we have to cache it
    // in the switch, and compute it based on the cached value in each
    // subsequent packet.
    //
    // It's important to avoid screwing up this computation if packets
    // are lost or reordered. The safest way to do this is to require
    // packets to be processed in order, and discarded if they
    // aren't. Since we have bitmaps protecting us from adding a
    // particular packet's contribution multiple times, if a
    // particular message has some packets received and added and some
    // not and the message is retransmitted, the packets that have
    // already been received will be ignored.
    //
    // How does this interact with our slot retransmission stuff? I
    // think as long as we don't try to reuse one of a messages'
    // packets' slots before all the packets for that message have
    // been received at the workers, life should be good.
    //
    // if a FIRST or ONLY message arrives, accept and reset sequence number and slot id
    // if a a MIDDLE or LAST message arrives,
    // * check if sequence number is 1+ previous value
    // * if so, compute slot ID
    table receive_roce {
        key = {
            hdr.ipv4.src_addr        : exact;
            hdr.ipv4.dst_addr        : exact;
            hdr.ib_bth.partition_key : exact;
            hdr.ib_bth.opcode        : exact;
            //hdr.ib_bth.dst_qp[23:16] : ternary; // match on top bits if you want.
            hdr.ib_bth.dst_qp        : ternary; // match on top 8 bits if you want.
        }
        actions = {
            only_packet;
            first_packet;
            middle_packet;
            last_packet;
        }
        size = max_num_workers * 6; // each worker needs 6 entries: first, middle, last, only, last immediate, and only immediate
        counters = rdma_receive_counter;
    }

    apply {
        message_possibly_received = false;
        receive_roce.apply();

        // use the SwitchML set bit in the MSB of the 16-bit pool index to switch between sets
        //ig_md.pool_set = hdr.ib_bth.dst_qp[15:15];
        if (hdr.ib_bth.dst_qp[15:15] == 1w1) {
            ig_md.pool_set = 1;
        } else {
            ig_md.pool_set = 0;
        }

        if (sequence_violation) {
            // count violation
            rdma_sequence_violation_counter.count(hdr.ib_bth.dst_qp[14:0]);
        } else if (message_possibly_received) {
            // count correctly received message
            rdma_message_counter.count(hdr.ib_bth.dst_qp[14:0]);
        }
    }
}


#endif /* _ROCERECEIVER_ */