// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _RDMARECEIVER_
#define _RDMARECEIVER_

/*

new design:

register: 1 entry per QP for PSN and pool index

register: 64-bit address
   cache on first message
   read on rest

(register: message length? or store in PSN or address?)

on first or only: 
   write to 

on last or only:
   read from register
   if PSN matches, generate multicast 

*/

//typedef pool_index_t index_t;
//typedef bit<17> index_t;
//typedef bit<(max_num_workers_log2 + max_num_queue_pairs_per_worker_log2)> index_t;

// // 256-byte slots
// #define INDEX (hdr.ib_bth.dst_qp[14:0] ++ hdr.ib_bth.dst_qp[15:15])

// // 512-byte slots
// #define INDEX (hdr.ib_bth.dst_qp[12:0] ++ 2w0 ++ hdr.ib_bth.dst_qp[15:15])

// 256-byte slots and 1024-byte messages
////#define INDEX (hdr.ib_bth.dst_qp[11:0] ++ 2w0 ++ hdr.ib_bth.dst_qp[15:15])
//#define INDEX (hdr.ib_bth.dst_qp[11:0] ++ 2w0 ++ hdr.ib_reth.r_key[0:0])

//#define INDEX (hdr.ib_bth.dst_qp[13:0] ++ hdr.ib_reth.r_key[0:0])

// broken queue pair indexing; everyone uses same slot number
//#define INDEX (hdr.ib_bth.dst_qp[14:0])

// // queue pair indexing with worker ID, max 17 workers (5 bits worker id, 12 bits QPN)
// #define QP_INDEX (hdr.ib_bth.dst_qp[20:16] ++ hdr.ib_bth.dst_qp[11:0])

// Switch QPN format:
// - bit 23 is always 1. Ignore.
// - bits 22 downto 16 are the worker ID. Since we only support 32
//   workers right now, only bits 20 downto 16 should ever be used.

// - bits 15 downto 0 are the queue pair index for this worker. Since each RDMA message in flight requires its own queue pair, and the minimum message size is the size of a slot, the most queue pairs we could ever needs is the number of slots. The max number of slots we can have is 11264 (22528/2), so 

//numberfor this worker
//
// for use
// worker ID is in low-order bits. Max worker ID is 32.
// QPN is 
//#define QP_INDEX (hdr.ib_bth.dst_qp[11:0] ++ hdr.ib_bth.dst_qp[20:16])

// compute queue pair index
#define QP_INDEX (hdr.ib_bth.dst_qp[16+max_num_workers_log2-1:16] ++ hdr.ib_bth.dst_qp[max_num_queue_pairs_per_worker_log2-1:0])



//#define POOL_INDEX (hdr.ib_bth.dst_qp[23:0] ++ 2w0 ++ hdr.ib_reth.r_key[0:0])
//#define POOL_INDEX (hdr.ib_bth.dst_qp)

// We take the pool index directly from the rkey.
#define POOL_INDEX (hdr.ib_reth.r_key)

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
    
control RDMAReceiver(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    //Random<drop_random_value_t>() rng;
    //drop_random_value_t drop_random_value;
    //drop_random_value_t worker_drop_probability;
    //typedef bit
    //bit<12>  worker_drop_probability;
    //Random<drop_random_value_t>() rng;
    //Random<drop_probability_t>() rng;
    //Hash<drop_probability_t>(HashAlgorithm_t.RANDOM) rng;

    // CRCPolynomial<bit<32>>(32w0x04C11DB7, // polynomial
    //     true,          // reversed
    //     false,         // use msb?
    //     false,         // extended?
    //     32w0xFFFFFFFF, // initial shift register value
    //     32w0xFFFFFFFF  // result xor
    // ) poly1;
    // Hash<bit<32>>(HashAlgorithm_t.CUSTOM, poly1) hash1;

    
    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) rdma_receive_counter;

    Register<receiver_data_t, queue_pair_index_t>(max_num_queue_pairs) receiver_data_register;
    Counter<counter_t, queue_pair_index_t>(max_num_queue_pairs, CounterType_t.PACKETS) rdma_packet_counter;
    Counter<counter_t, queue_pair_index_t>(max_num_queue_pairs, CounterType_t.PACKETS) rdma_message_counter;
    Counter<counter_t, queue_pair_index_t>(max_num_queue_pairs, CounterType_t.PACKETS) rdma_sequence_violation_counter;

    bool message_possibly_received;
    bool sequence_violation;
    
    // use with _FIRST and _ONLY packets
    RegisterAction<receiver_data_t, queue_pair_index_t, return_t>(receiver_data_register) receiver_reset_action = {
        void apply(inout receiver_data_t value, out return_t read_value) {
            // Store next sequence number.
            if ((bit<32>) hdr.ib_bth.psn == 0x00ffffff) { // PSNs are 24 bits. Do we need to wrap around?
                value.next_sequence_number = 0;
            } else {
                value.next_sequence_number = (bit<32>) hdr.ib_bth.psn + 1; // Increment and store next sequence number.
            }

            // Reset pool index register using pool index in packet.
            value.pool_index = (bit<32>) POOL_INDEX;

            // Return pool index field. MSB is error bit, LSBs are the actual pool index.
            read_value = value.pool_index;
        }
    };

    // use with _MIDDLE and _LAST packets
    RegisterAction<receiver_data_t, queue_pair_index_t, return_t>(receiver_data_register) receiver_increment_action = {
        void apply(inout receiver_data_t value, out return_t read_value) {
            // is this packet the next one in the PSN sequence?
            if ((bit<32>) hdr.ib_bth.psn == value.next_sequence_number) {
                // Yes. Increment PSN and pool index.

                // Increment pool index, leaving slot bit (bit 0) unchanged.
                // Use saturating addition to ensure error bit stays set if it gets set.
                value.pool_index = value.pool_index |+| 2;

                // Increment expected sequence number.
                if (value.next_sequence_number == 0x00ffffff) { // PSNs are 24 bits. Do we need to wrap around?
                    value.next_sequence_number = 0; // Wrap around!
                } else {
                    value.next_sequence_number = value.next_sequence_number + 1; // Increment PSN!
                }
            } else {
                // No! Leave next PSN unchanged and signal error using MSB of pool index

                // Set error bit in pool index register. Once this bit
                // is set, it stays set until a new message arrives
                // and overwrites the register state. 
                value.pool_index = 0x80000000;

                // Ideally I would move the next_sequence_number to an
                // error state that would never match an incoming
                // packet, but I can't find a way to do this with the
                // ALU block while still doing the wraparound for the
                // PSN above. Fortunately, this isn't necessary, since
                // the error bit will cause packets to be dropped even
                // if the next packet in the sequence eventually
                // arrives.
                value.next_sequence_number = value.next_sequence_number;
            }

            // Return pool index field. MSB is error bit, LSBs are the actual pool index.
            read_value = value.pool_index;
        }
    };


    action set_bitmap(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap,
        packet_size_t packet_size,
        drop_probability_t drop_probability) {

        // bitmap representation for this worker
        ig_md.worker_bitmap   = worker_bitmap;
        ig_md.num_workers     = num_workers;

        //ig_md.switchml_md.setValid(); // should already be set in parser to get here

        // group ID for this job
        ig_md.switchml_md.mgid = mgid;

        ig_md.switchml_md.worker_type = worker_type;
        ig_md.switchml_md.worker_id = worker_id;     // Same as rid for worker; used when retransmitting RDMA packets
        ig_md.switchml_md.dst_port = hdr.udp.src_port;


        //ig_md.switchml_rdma_md.setValid(); // should already be set in parser to get there
        ig_md.switchml_rdma_md.rdma_addr = hdr.ib_reth.addr; // TODO: make this an index rather than an address
        ig_md.switchml_md.tsi = hdr.ib_reth.len; // TODO: put this in a better place

        //ig_md.switchml_md.ingress_port = ig_intr_md.ingress_port;
        // compute port used for recirculation
        //ig_md.switchml_md.recirc_port_selector = (bit<8>) ig_intr_md.ingress_port;
        //ig_md.switchml_md.recirc_port_selector = (bit<8>) ig_md.switchml_md.pool_index[8:1];

        //ig_tm_md.ucast_egress_port = (PortId_t) ig_md.switchml_md.pool_index[4:1];

        //ig_md.switchml_md.recirc_port_selector = (bit<16>) ig_md.switchml_md.pool_index[4:1];

        // TODO: copy immediate to exponents
        // TODO: copy address
        
        // get rid of headers we don't want to recirculate
        hdr.ethernet.setInvalid();
        hdr.ipv4.setInvalid();
        hdr.udp.setInvalid();
        hdr.ib_bth.setInvalid(); // TODO: copy qpn to a better place and re-eenable here
        hdr.ib_reth.setInvalid();
        hdr.ib_immediate.setInvalid();
        //hdr.ib_icrc.setInvalid(); // this won't be set, since we leave it in the packet memory

        // record packet size for use in recirculation
        ig_md.switchml_md.packet_size = packet_size;
        ig_md.switchml_md.recirc_port_selector = (queue_pair_index_t) QP_INDEX;
        
        //drop_random_value = rng.get();
        //ig_md.drop_calculation = drop_probability - (1w0 ++ rng.get());
        //ig_md.drop_calculation = drop_probability - rng.get();
        //ig_md.drop_calculation = rng.get({ig_prsr_md.global_tstamp, ig_intr_md.ingress_mac_tstamp});
        //ig_md.drop_calculation = hash1.get({ig_intr_md.ingress_mac_tstamp})[15:0];
        //ig_md.drop_calculation = drop_probability;
        
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

    action assign_pool_index(bit<32> result) {
        //ig_md.switchml_md.pool_index = result[13:0] ++ hdr.ib_reth.r_key[0:0];
        //ig_md.switchml_md.pool_index = result[14:0] + hdr.ib_reth.r_key[14:0];
        //ig_md.switchml_md.pool_index = result[13:0] ++ 1w0;
        //ig_md.switchml_md.pool_index = result[14:0] << 1;

        ig_md.switchml_md.pool_index = result[14:0];
    }

    action assign_pool_index_subtracted(bit<32> result) {
        //ig_md.switchml_md.pool_index = result[13:0] ++ hdr.ib_reth.r_key[0:0];
        //ig_md.switchml_md.pool_index = result[14:0] + hdr.ib_reth.r_key[14:0];
        //ig_md.switchml_md.pool_index = result[13:0] ++ 1w0;
        //ig_md.switchml_md.pool_index = result[14:0] << 1;

        ig_md.switchml_md.pool_index = result[14:0];
    }
    
    action middle_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap,
        packet_size_t packet_size,
        drop_probability_t drop_probability) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap, packet_size, drop_probability);
        ig_md.switchml_rdma_md.first_packet = false;
        ig_md.switchml_rdma_md.last_packet  = false;

        // process sequence number
        return_t result = receiver_increment_action.execute(QP_INDEX);
        
        // if sign bit of result is set, there was a sequence violation, so ignore this packet.
        //ig_dprsr_md.drop_ctl[0:0] = ig_dprsr_md.drop_ctl[0:0] | result[31:31];
        ig_dprsr_md.drop_ctl[0:0] = result[31:31];

        assign_pool_index(result);
        
        // A message has not yet arrived, since this is a middle packet.
        message_possibly_received = false;
        sequence_violation = (bool) result[31:31];
    }

    action last_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap,
        packet_size_t packet_size,
        drop_probability_t drop_probability) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap, packet_size, drop_probability);
        ig_md.switchml_rdma_md.first_packet = false;
        ig_md.switchml_rdma_md.last_packet  = true;

        // process sequence number
        return_t result = receiver_increment_action.execute(QP_INDEX);
        //received_message = result;

        // if sign bit of result is set, there was a sequence violation, so ignore this packet.
        //ig_dprsr_md.drop_ctl[0:0] = ig_dprsr_md.drop_ctl[0:0] | result[31:31];
        ig_dprsr_md.drop_ctl[0:0] = result[31:31];

        assign_pool_index(result);

        // A message has arrived if the sequence number matched (sign bit == 0).
        message_possibly_received = true;
        sequence_violation = (bool) result[31:31];
    }

    action first_packet(
        MulticastGroupId_t mgid,
        worker_type_t worker_type,
        worker_id_t worker_id, 
        num_workers_t num_workers,
        worker_bitmap_t worker_bitmap,
        packet_size_t packet_size,
        drop_probability_t drop_probability) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap, packet_size, drop_probability);
        ig_md.switchml_rdma_md.first_packet = true;
        ig_md.switchml_rdma_md.last_packet  = false;

        // reset sequence number
        return_t result = receiver_reset_action.execute(QP_INDEX);

        assign_pool_index(result);
        
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
        worker_bitmap_t worker_bitmap,
        packet_size_t packet_size,
        drop_probability_t drop_probability) {

        // set common fields
        set_bitmap(mgid, worker_type, worker_id,  num_workers, worker_bitmap, packet_size, drop_probability);
        ig_md.switchml_rdma_md.first_packet = true;
        ig_md.switchml_rdma_md.last_packet  = true;
        
        // reset sequence number
        return_t result = receiver_reset_action.execute(QP_INDEX);

        assign_pool_index(result);
        
        // This is an only packet, so there can be no sequence number violation.
        // Don't drop the packet.

        // A message has arrived, since this is an only packet.
        message_possibly_received = true;
        sequence_violation = (bool) result[31:31];
        
        //ig_md.switchml_md.packet_type = ((bool) result[31:31]) ? packet_type_t.IGNORE : ig_md.switchml_md.packet_type;
    }

    // packet is not a SwitchML packet; just foward
    action forward() {
        // forward this packet
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
        rdma_receive_counter.count();
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
            @defaultonly forward;
        }
        const default_action = forward;
        size = max_num_workers * 6; // each worker needs 6 entries: first, middle, last, only, last immediate, and only immediate
        counters = rdma_receive_counter;
    }

    apply {
        // sequence_violation = false;
        // message_possibly_received = false;
        //ig_md.drop_calculation = rng.get({ig_prsr_md.global_tstamp, ig_intr_md.ingress_mac_tstamp});
        //ig_md.drop_calculation = rng.get({ig_intr_md.ingress_mac_tstamp});
        
        if (receive_roce.apply().hit) {
            
            // // use the SwitchML set bit in the MSB of the 16-bit pool index to switch between sets
            // //ig_md.pool_set = hdr.ib_bth.dst_qp[15:15];
            // if (hdr.ib_bth.dst_qp[15:15] == 1w1) {
                //     ig_md.pool_set = 1;
                // } else {
                //     ig_md.pool_set = 0;
                // }
            rdma_packet_counter.count(ig_md.switchml_md.recirc_port_selector);
            // if (drop_random_value < worker_drop_probability) {
            //     ig_dprsr_md.drop_ctl[0:0] = 1;
            // }
            // if (worker_drop_probability[11:11] == 1) {
            //     ig_dprsr_md.drop_ctl[0:0] = 1;
            // }
        
            
            if (sequence_violation) {
                // count violation
                rdma_sequence_violation_counter.count(ig_md.switchml_md.recirc_port_selector);
                
                // drop bit is already set; copy/mirror to CPU too
                ig_tm_md.copy_to_cpu = 1;
                
                // //ig_dprsr_md.digest_type
                // ig_md.mirror_session = 1;
                // ig_dprsr_md.mirror_type = MIRROR_TYPE_I2E;
                // //hdr.ethernet.setValid(); // re-enable ethernet header for mirror header
                // ig_md.mirror_ether_type = 0x88b6; // local experimental ethertype


                // if (sequence_violation) {
                    //ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
                    //     ig_tm_md.ucast_egress_port = 4;
                    //     ig_tm_md.bypass_egress = 1w1;
                    //     ig_dprsr_md.drop_ctl[0:0] = 0;
                    
                    // }    
                
            } else if (message_possibly_received) {
                // count correctly received message
                rdma_message_counter.count(ig_md.switchml_md.recirc_port_selector);
            }

            //hdr.ib_bth.setInvalid(); // TODO: copy qpn to better place and move back to set action
        }
    }
}


#endif /* _RDMARECEIVER_ */
