// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _RDMASENDER_
#define _RDMASENDER_


// Ingress control to assign sequence numbers when starting a harvest
// phase. Since we do this before broadcast, the same sequence numbers
// will be used for all clients for the non-retransmit case. Since
// we're using UC and there is no requirement that sequence numbers
// are contiguous between messages, we will use the same sequence
// number register for retransmissions as well.
control RDMASequenceNumberAssignment(
    inout header_t hdr,
    inout ingress_metadata_t ig_md) {

    // single PSN register for all queue pairs
    Register<bit<32>, queue_pair_index_t>(max_num_queue_pairs) psn_register;

    // will be initialized through control plane
    RegisterAction<bit<32>, queue_pair_index_t, bit<32>>(psn_register) psn_action = {
        void apply(inout bit<32> value, out bit<32> read_value) {
            // emit 24-bit sequence number
            bit<32> masked_sequence_number = value & 0x00ffffff;
            read_value = masked_sequence_number;
            
            // increment sequence number
            bit<32> incremented_value = value + 1;
            value = incremented_value;
        }
    };
    
    action set_sequence_number() {
        ig_md.switchml_rdma_md.setValid(); // may already be valid for a first packet
        ig_md.switchml_rdma_md.psn = psn_action.execute(ig_md.switchml_md.recirc_port_selector)[23:0];
    }
    
    apply {
        set_sequence_number();
    }
}

// Egress control to fill in rest of RDMA packet.
control RDMASender(
    inout header_t hdr,
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {

    
    Hash<bit<32>>(HashAlgorithm_t.IDENTITY) immediate_hash;
    Hash<bit<24>>(HashAlgorithm_t.IDENTITY) psn_hash;

    // temporary variables
    addr_t rdma_base_addr;
    rkey_t rdma_rkey;
    bit<31> rdma_message_length;

    mac_addr_t rdma_switch_mac;
    ipv4_addr_t rdma_switch_ip;

    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) rdma_send_counter;
    
    //
    // read switch MAC and IP from table to form output packets
    //
    action set_switch_mac_and_ip(
        mac_addr_t switch_mac, ipv4_addr_t switch_ip,
        bit<31> message_length,       
        pool_index_t first_last_mask) {

        // record switch addresses
        rdma_switch_mac = switch_mac;
        rdma_switch_ip = switch_ip;
        
        // record RDMA message length in case we need it for RDMA WRITEs
        rdma_message_length = message_length; // length must be a power of two
        
        // // use masked pool index to choose RDMA opcode: if masked
        // // value is 0, first; equal to mask, last; otherwise middle.
        // // TODO: not currently used
        // eg_md.pool_index_mask   = first_last_mask;
        // eg_md.masked_pool_index = eg_md.switchml_md.pool_index & first_last_mask;
    }

    table switch_mac_and_ip {
        actions = { @defaultonly set_switch_mac_and_ip; }
        size = 1;
    }


    //
    // Get destination MAC and IP and form RoCE output packets
    // (Sequence number and queue pair will be filled in later)
    //
    action fill_in_roce_fields(mac_addr_t dest_mac, ipv4_addr_t dest_ip) {
        // ensure we don't have a switchml header
        hdr.switchml.setInvalid();
        hdr.exponents.setInvalid();

        hdr.ethernet.setValid();
        hdr.ethernet.dst_addr = dest_mac;
        hdr.ethernet.src_addr = rdma_switch_mac;
        hdr.ethernet.ether_type = ETHERTYPE_IPV4;
        
        hdr.ipv4.setValid();
        hdr.ipv4.version = 4;
        hdr.ipv4.ihl = 5;
        hdr.ipv4.diffserv = 0x02;
        hdr.ipv4.identification = 0x0001;
        hdr.ipv4.flags = 0b010;
        hdr.ipv4.frag_offset = 0;
        hdr.ipv4.ttl = 64;
        hdr.ipv4.protocol = ip_protocol_t.UDP;
        hdr.ipv4.hdr_checksum = 0; // To be filled in by deparser
        hdr.ipv4.src_addr = rdma_switch_ip;
        hdr.ipv4.dst_addr = dest_ip;

        // set base IPv4 packet length; will be updated later based on
        // payload size and headers
        hdr.ipv4.total_len = ( \
            hdr.ib_icrc.minSizeInBytes() + \
            hdr.ib_bth.minSizeInBytes() + \
            hdr.udp.minSizeInBytes() + \
            hdr.ipv4.minSizeInBytes());

        // update IPv4 checksum
        eg_md.update_ipv4_checksum = true;

        hdr.udp.setValid();
        // TODO: BUG: this line being uncommented 
        //hdr.udp.src_port = 0x8000 | eg_md.switchml_md.worker_id; // form a consistent source port for this worker
        // This works okay! 
        hdr.udp.src_port = 1w1 ++ eg_md.switchml_md.worker_id[14:0]; // form a consistent source port for this worker
        //hdr.udp.src_port = 0x2345;
        hdr.udp.dst_port = UDP_PORT_ROCEV2;
        hdr.udp.checksum = 0; // disabled for RoCEv2

        // set base IPv4 packet length; will be updated later based on
        // payload size and headers
        hdr.udp.length = ( \
            hdr.ib_icrc.minSizeInBytes() + \
            hdr.ib_bth.minSizeInBytes() + \
            hdr.udp.minSizeInBytes());

        
        hdr.ib_bth.setValid();
        hdr.ib_bth.opcode = ib_opcode_t.UC_RDMA_WRITE_ONLY; // to be filled in later
        hdr.ib_bth.se = 0;
        hdr.ib_bth.migration_req = 1;
        hdr.ib_bth.pad_count = 0;
        hdr.ib_bth.transport_version = 0;
        hdr.ib_bth.partition_key = 0xffff;
        hdr.ib_bth.f_res1 = 0;
        hdr.ib_bth.b_res1 = 0;
        hdr.ib_bth.reserved = 0;
        hdr.ib_bth.dst_qp = 0; // to be filled in later
        hdr.ib_bth.ack_req = 0;
        hdr.ib_bth.reserved2 = 0;
        //hdr.ib_bth.psn = 0; // to be filled in later

        // NOTE: we don't add an ICRC header here for two reasons:
        // 1. we haven't parsed the payload in egress, so we can't place it at the right point
        // 2. the payload may be too big for us to parse (1024B packets)
        // Thus, we just leave the existing ICRC in the packet buffer
        // during ingress processing, and leave it at the right point
        // in the egress packet. This works because we're having the NICs ignore it.

        // count
        rdma_send_counter.count();
    }

    action fill_in_roce_write_fields(mac_addr_t dest_mac, ipv4_addr_t dest_ip, bit<64> base_addr, rkey_t rkey) {
        fill_in_roce_fields(dest_mac, dest_ip);

        // store base address and rkey now, but don't add them until we know if this is the first packet
        rdma_base_addr = base_addr;
        rdma_rkey = rkey;
    }

    table create_roce_packet {
        key = {
            eg_md.switchml_md.worker_id : exact;
        }
        actions = {
            fill_in_roce_fields;
            fill_in_roce_write_fields;
        }
        size = max_num_workers;
        counters = rdma_send_counter;
    }

    //
    // fill in destination queue pair number and sequence number
    //
    
    // DirectRegister<bit<32>>() psn_register;

    // // will be initialized through control plane
    // DirectRegisterAction<bit<32>, bit<32>>(psn_register) psn_action = {
    //     // TODO: BUG: ???
    //     // // fails with /tmp/switchml/pipe/switchml.bfa:9985: error: No phv record mem_lo
    //     // // switchml.bfa:
    //     // //   stateful roce_sender_fill_in_qpn_and_psn$st0$salu.SwitchMLEgress.roce_sender.psn_register:
    //     // //     p4: { name: SwitchMLEgress.roce_sender.psn_register }
    //     // //     row: 15
    //     // //     column: [ 0, 1, 2, 3 ]
    //     // //     maprams: [ 0, 1, 2, 3 ]
    //     // //     format: { lo: 32 }
    //     // //     actions:
    //     // //       roce_sender_psn_action:
    //     // //       - and hi, 16777215, mem_lo
    //     // //       - add lo, lo, 1
    //     // //       - output alu_hi
    //     // void apply(inout bit<32> value, out bit<32> read_value) {
    //     //     read_value = 0x00ffffff & value;
    //     //     value = value + 1;
    //         // }

    //     // This one works for now
    //     void apply(inout bit<32> value, out bit<32> read_value) {
    //         // emit 24-bit sequence number
    //         bit<32> masked_sequence_number = value & 0x00ffffff;
    //         read_value = masked_sequence_number;

    //         // increment sequence number
    //         bit<32> incremented_value = value + 1;
    //         value = incremented_value;
    //     }
    // };

    action add_qpn_and_psn(queue_pair_t qpn) {
        hdr.ib_bth.dst_qp = qpn;
        //hdr.ib_bth.psn = (sequence_number_t) psn_action.execute();
        //hdr.ib_bth.psn = psn_action.execute()[23:0];
        //bit<32> temp_psn = psn_action.execute();
        //hdr.ib_bth.psn = temp_psn[23:0];
        //hdr.ib_bth.psn = (bit<24>) eg_md.switchml_md.pool_index[14:1];
        
        // hdr.ib_bth.psn = psn_hash.get({
                //         10w0,
                //         eg_md.switchml_md.pool_index[14:1]});
        
        hdr.ib_bth.psn = eg_md.switchml_rdma_md.psn;
    }
    
    table fill_in_qpn_and_psn {
        key = {
            eg_md.switchml_md.worker_id  : exact; // replication ID: indicates which worker we're sending to
            eg_md.switchml_md.pool_index : ternary;
        }
        actions = {
            add_qpn_and_psn;
        }
        size = max_num_queue_pairs;
        //registers = psn_register;
    }

    //
    // set opcodes as appropriate, and fill in packet-dependent fields
    //

    action set_opcode_common(ib_opcode_t opcode) {
        hdr.ib_bth.opcode = opcode;
    }

    action set_immediate() {
        hdr.ib_immediate.setValid();
        // TODO: put something here

        // this fails to compile.
        //hdr.ib_immediate.immediate = 17w0 ++ eg_md.switchml_md.pool_index;

        // this fails to compile.        
        //hdr.ib_immediate.immediate = 24w0 ++ eg_md.switchml_md.pool_index[7:0];

        // this fails to compile.
        //hdr.ib_immediate.immediate = (bit<32>) eg_md.switchml_md.pool_index[7:0];

        // this works, but is not useful.
        //hdr.ib_immediate.immediate = 0x12345678;

        // this works.
        // Use lower 16 bits to hold pool index. Use lower 16 bits for exponents.
        hdr.ib_immediate.immediate = immediate_hash.get({
                1w0,
                eg_md.switchml_md.pool_index,
                eg_md.switchml_exponents_md.e1,
                eg_md.switchml_exponents_md.e0});
        eg_md.switchml_exponents_md.setInvalid();
        
        // hdr.ib_immediate.immediate = immediate_hash.get({
        //         12w0,
        //         eg_md.switchml_md.packet_type,
        //         1w0,
        //         eg_md.switchml_md.pool_index});
        
                // imm_constant});
                
                // //17w0,
                // 12w0,
                // eg_md.switchml_md.packet_type,
                // 1w0,
                // //eg_md.switchml_md.packet_type == packet_type_t.RETRANSMIT,
                // eg_md.switchml_md.pool_index});
    }

    action set_rdma() {
        hdr.ib_reth.setValid();
        hdr.ib_reth.r_key = rdma_rkey;
        //hdr.ib_reth.len = 1w0 ++ rdma_message_length;
        //hdr.ib_reth.len = 10w0 ++ eg_md.switchml_rdma_md.message_len_by256 ++ 8w0;
        hdr.ib_reth.len = (bit<32>) eg_md.switchml_rdma_md.len;

        // this is what compiles today
        hdr.ib_reth.addr = eg_md.switchml_rdma_md.addr; // TODO: ???

        // // this is what we really want to be able to do offset-based addressing
        // hdr.ib_reth.addr = rdma_base_addr + eg_md.switchml_rdma_md.addr; // TODO: ???
    }
    
    action set_opcode() {
        set_opcode_common(ib_opcode_t.UC_RDMA_WRITE_MIDDLE);
        // use default adjusted length for UDP and IPv4 headers
    }
    
    action set_immediate_opcode() {        
        set_opcode_common(ib_opcode_t.UC_RDMA_WRITE_LAST_IMMEDIATE);
        set_immediate();

        hdr.udp.length = hdr.udp.length + (bit<16>) hdr.ib_immediate.minSizeInBytes();
        hdr.ipv4.total_len = hdr.ipv4.total_len + (bit<16>) hdr.ib_immediate.minSizeInBytes();
    }
    
    action set_rdma_opcode() {
        set_opcode_common(ib_opcode_t.UC_RDMA_WRITE_FIRST);
        set_rdma();

        hdr.udp.length = hdr.udp.length + (bit<16>) hdr.ib_reth.minSizeInBytes();
        hdr.ipv4.total_len = hdr.ipv4.total_len + (bit<16>) hdr.ib_reth.minSizeInBytes();
    }
    
    action set_rdma_immediate_opcode() {        
        set_opcode_common(ib_opcode_t.UC_RDMA_WRITE_ONLY_IMMEDIATE);
        set_rdma();
        set_immediate();

        hdr.udp.length = hdr.udp.length + (bit<16>) (hdr.ib_immediate.minSizeInBytes() + hdr.ib_reth.minSizeInBytes());
        hdr.ipv4.total_len = hdr.ipv4.total_len + (bit<16>) (hdr.ib_immediate.minSizeInBytes() + hdr.ib_reth.minSizeInBytes());
    }

    table set_opcodes {
        key = {
            //eg_md.switchml_md.pool_index : ternary;
            eg_md.switchml_md.first_packet_of_message : exact;
            eg_md.switchml_md.last_packet_of_message : exact;
        }
        actions = {
            set_opcode;
            set_immediate_opcode;
            set_rdma_opcode;
            set_rdma_immediate_opcode;
        }
        //size = 3 * max_num_workers; // either one for _ONLY or three for _FIRST, _MIDDLE, and _LAST
        const entries = {
            ( true, false) :           set_rdma_opcode();//ib_opcode_t.UC_RDMA_WRITE_FIRST;
            (false, false) :                set_opcode();//ib_opcode_t.UC_RDMA_WRITE_MIDDLE;
            (false,  true) :      set_immediate_opcode();//ib_opcode_t.UC_RDMA_WRITE_LAST_IMMEDIATE;
            ( true,  true) : set_rdma_immediate_opcode();//ib_opcode_t.UC_RDMA_WRITE_ONLY_IMMEDIATE;
        }
    }
    
    //
    // do it!
    //
    
    apply {
        // get switch IP and switch MAC
        switch_mac_and_ip.apply();

        // fill in headers for ROCE packet
        create_roce_packet.apply();

        // add payload size
        if (eg_md.switchml_md.packet_size == packet_size_t.IBV_MTU_256) {
            hdr.ipv4.total_len = hdr.ipv4.total_len + 256;
            hdr.udp.length = hdr.udp.length + 256;
        }
        else if (eg_md.switchml_md.packet_size == packet_size_t.IBV_MTU_1024) {
            hdr.ipv4.total_len = hdr.ipv4.total_len + 1024;
            hdr.udp.length = hdr.udp.length + 1024;
        }
            
        // fill in queue pair number of sequence number
        fill_in_qpn_and_psn.apply();
        // if (fill_in_qpn_and_psn.apply().hit) {
        //     hdr.ib_bth.psn = temp_psn[23:0];
        // }
        
        // fill in opcode based on pool index
        set_opcodes.apply();

        // if (hdr.ib_immediate.isValid()) {
        //     //hdr.ib_immediate.immediate = (bit<32>) eg_md.switchml_md.pool_index;
        //     hdr.ib_immediate.immediate = immediate_hash.get({
        //             17w0,
        //             eg_md.switchml_md.pool_index});
        // }
    }
    
}


#endif /* _RDMASENDER_ */
