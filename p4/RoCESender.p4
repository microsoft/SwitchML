/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _ROCESENDER_
#define _ROCESENDER_

control RoCESender(
    inout header_t hdr,
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {

    //
    // read switch MAC and IP from table to form output packets
    //
    action set_switch_mac_and_ip(
        mac_addr_t switch_mac, ipv4_addr_t switch_ip,
        bit<31> message_length,       
        pool_index_t first_last_mask) {

        // record switch addresses
        eg_md.switch_mac = switch_mac;
        eg_md.switch_ip = switch_ip;
        
        // record RDMA message length in case we need it for RDMA WRITEs
        eg_md.message_length  = message_length; // length must be a power of two
        
        // use masked pool index to choose RDMA opcode: if masked
        // value is 0, first; equal to mask, last; otherwise middle.
        eg_md.pool_index_mask   = first_last_mask;
        eg_md.masked_pool_index = eg_md.switchml_md.pool_index & first_last_mask;
    }

    // action set_switch_mac_and_ip_with_immediate() {
    // }

    // action set_switch_mac_and_ip_for_rdma_write() {
    // }

    // action set_switch_mac_and_ip_for_rdma_write_with_immediate() {
    // }

    table switch_mac_and_ip {
        actions = { @defaultonly set_switch_mac_and_ip; }
        size = 1;
    }


    //
    // Get destination MAC and IP and form RoCE output packets
    // (Sequence number and queue pair will be filled in later)
    //
    action fill_in_roce_fields(mac_addr_t dest_mac, ipv4_addr_t dest_ip) {
        // TODO: make work with immediate values and/or RDMA headers
        const bit<16> udp_length = hdr.udp.minSizeInBytes() + hdr.ib_bth.minSizeInBytes() + hdr.d0.minSizeInBytes() + hdr.d1.minSizeInBytes() + hdr.ib_icrc.minSizeInBytes();
        const bit<16> ipv4_length = hdr.ipv4.minSizeInBytes() + hdr.udp.minSizeInBytes() + hdr.ib_bth.minSizeInBytes() + hdr.d0.minSizeInBytes() + hdr.d1.minSizeInBytes() + hdr.ib_icrc.minSizeInBytes();

        // ensure we don't have a switchml header
        hdr.switchml.setInvalid();
        hdr.exponents.setInvalid();

        hdr.ethernet.setValid();
        hdr.ethernet.dst_addr = dest_mac;
        hdr.ethernet.src_addr = eg_md.switch_mac;
        hdr.ethernet.ether_type = ETHERTYPE_IPV4;
        
        hdr.ipv4.setValid();
        hdr.ipv4.version = 4;
        hdr.ipv4.ihl = 5;
        hdr.ipv4.diffserv = 0x02;
        hdr.ipv4.total_len = ipv4_length;
        hdr.ipv4.identification = 0x0001;
        hdr.ipv4.flags = 0b010;
        hdr.ipv4.frag_offset = 0;
        hdr.ipv4.ttl = 64;
        hdr.ipv4.protocol = ip_protocol_t.UDP;
        hdr.ipv4.hdr_checksum = 0; // To be filled in by deparser
        hdr.ipv4.src_addr = eg_md.switch_ip;
        hdr.ipv4.dst_addr = dest_ip;
        eg_md.update_ipv4_checksum = true;

        hdr.udp.setValid();
        hdr.udp.src_port = 0x2345;
        hdr.udp.dst_port = UDP_PORT_ROCEV2;
        hdr.udp.length = udp_length;
        hdr.udp.checksum = 0; // disabled for RoCEv2
        
        hdr.ib_bth.setValid();
        hdr.ib_bth.opcode = ib_opcode_t.UC_SEND_FIRST; // to be filled in later
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
        hdr.ib_bth.psn = 0; // to be filled in later

        // TODO: can't do this here because we haven't parsed data. Add a header with 0's in ingress for now.
        // hdr.ib_icrc.setValid();
        // hdr.ib_icrc.icrc = 0; // to be filled in later (or ignored with the right NIC settings)
    }

    // action fill_in_roce_write_fields(mac_addr_t dest_mac, ipv4_addr_t dest_ip) {
    //     fill_in_roce_fields(dest_mac, dest_ip);
    // }

    table create_roce_packet {
        key = {
            eg_md.switchml_md.worker_id : exact;
        }
        actions = {
            fill_in_roce_fields;
            //fill_in_roce_send_fields;
            //fill_in_roce_write_fields;
        }
        size = max_num_workers;
    }

    //
    // fill in destination queue pair number and sequence number
    //
    
    DirectRegister<bit<32>>() psn_register;

    // will be initialized through control plane
    DirectRegisterAction<bit<32>, bit<32>>(psn_register) psn_action = {
        // TODO: BUG: ???
        // // fails with /tmp/switchml/pipe/switchml.bfa:9985: error: No phv record mem_lo
        // // switchml.bfa:
        // //   stateful roce_sender_fill_in_qpn_and_psn$st0$salu.SwitchMLEgress.roce_sender.psn_register:
        // //     p4: { name: SwitchMLEgress.roce_sender.psn_register }
        // //     row: 15
        // //     column: [ 0, 1, 2, 3 ]
        // //     maprams: [ 0, 1, 2, 3 ]
        // //     format: { lo: 32 }
        // //     actions:
        // //       roce_sender_psn_action:
        // //       - and hi, 16777215, mem_lo
        // //       - add lo, lo, 1
        // //       - output alu_hi
        // void apply(inout bit<32> value, out bit<32> read_value) {
        //     read_value = 0x00ffffff & value;
        //     value = value + 1;
            // }

        // This one works for now
        void apply(inout bit<32> value, out bit<32> read_value) {
            // emit 24-bit sequence number
            bit<32> masked_sequence_number = value & 0x00ffffff;
            read_value = masked_sequence_number;;

            // increment sequence number
            value = value + 1;
        }
    };

    action add_qpn_and_psn(queue_pair_t qpn) {
        hdr.ib_bth.dst_qp = qpn;
        hdr.ib_bth.psn = (sequence_number_t) psn_action.execute();
    }
    
    // action add_qpn_and_psn_and_rdma(queue_pair_t qpn, bit<32> rkey, bit<64> address) {
    //     hdr.ib_bth.dst_qp = qpn;
    //     hdr.ib_bth.psn = (sequence_number_t) psn_action.execute();

    //     hdr.ib_reth.setValid();
    //     hdr.ib_reth.addr = address; // TODO: index by tsi or slot or source packet address or something?
    //     hdr.ib_reth.r_key = rkey;
    //     hdr.ib_reth.len = hdr.d0.minSizeInBytes() + hdr.d1.minSizeInBytes();
    // }
    
    table fill_in_qpn_and_psn {
        key = {
            eg_md.switchml_md.worker_id  : exact; // replication ID: indicates which worker we're sending to
            eg_md.switchml_md.pool_index : ternary;
        }
        actions = {
            add_qpn_and_psn;
            //add_qpn_and_psn_and_rdma; // TODO: rethink this before using
        }
        size = max_num_queue_pairs;
        registers = psn_register;
    }

    //
    // set opcodes as appropriate
    //
    // the python code can add UC_SEND or UC_RDMA_WRITE opcodes here as appropriate.
    //
    
    action set_opcode(ib_opcode_t opcode) {
        hdr.ib_bth.opcode = opcode;
    }
    
    table set_opcodes {
        key = {
            eg_md.switchml_md.pool_index : ternary;
        }
        actions = {
            set_opcode;
        }
        size = 2;
    }
    
    //
    // do it!
    //
    
    apply {
        // get switch IP and switch MAC
        switch_mac_and_ip.apply();

        // fill in headers for ROCE packet
        create_roce_packet.apply();

        // fill in queue pair number of sequence number
        fill_in_qpn_and_psn.apply();
        
        // fill in opcode based on pool index
        set_opcodes.apply();
    }
    
}


#endif /* _ROCESENDER_ */
