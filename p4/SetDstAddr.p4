// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _SET_DST_ADDR_
#define _SET_DST_ADDR_

control SetDestinationAddress(
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    inout header_t hdr) {

    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) send_counter;

    Hash<exponent16_t>(HashAlgorithm_t.IDENTITY) exponent_hash;

    //
    // read switch MAC and IP from table to form output packets
    //
    action set_switch_mac_and_ip(mac_addr_t switch_mac, ipv4_addr_t switch_ip) {

        // set switch addresses
        hdr.ethernet.src_addr = switch_mac;
        hdr.ipv4.src_addr = switch_ip;

        // swap source and destination ports (dst assigned later)
        hdr.udp.src_port = eg_md.switchml_udp_md.dst_port;



        hdr.ethernet.ether_type = ETHERTYPE_IPV4;

#define UDP_LENGTH (hdr.udp.minSizeInBytes() + hdr.switchml.minSizeInBytes() + hdr.exponents.minSizeInBytes() + hdr.d0.minSizeInBytes() + hdr.d1.minSizeInBytes())
#define IPV4_LENGTH (hdr.ipv4.minSizeInBytes() + UDP_LENGTH);

        hdr.ipv4.version = 4;
        hdr.ipv4.ihl = 5;
        hdr.ipv4.diffserv = 0x00;
        hdr.ipv4.total_len = IPV4_LENGTH;
        hdr.ipv4.identification = 0x0000;
        hdr.ipv4.flags = 0b000;
        hdr.ipv4.frag_offset = 0;
        hdr.ipv4.ttl = 64;
        hdr.ipv4.protocol = ip_protocol_t.UDP;
        hdr.ipv4.hdr_checksum = 0; // To be filled in by deparser
        hdr.ipv4.src_addr = switch_ip;
        eg_md.update_ipv4_checksum = true;

        hdr.udp.length = UDP_LENGTH;

        hdr.switchml.setValid();
        hdr.switchml.msgType = eg_md.switchml_udp_md.msg_type;
        hdr.switchml.opcode = eg_md.switchml_udp_md.opcode;
        hdr.switchml.tsi = eg_md.switchml_udp_md.tsi;

        // rearrange or in set bit later
        hdr.switchml.pool_index[13:0] = eg_md.switchml_md.pool_index[14:1];
    }


    table switch_mac_and_ip {
        actions = { @defaultonly set_switch_mac_and_ip; }
        size = 1;
    }


    
    action set_dst_addr_for_SwitchML_UDP(
        mac_addr_t eth_dst_addr,
        ipv4_addr_t ip_dst_addr) {

        // set to destination node
        hdr.ethernet.dst_addr = eth_dst_addr;
        hdr.ipv4.dst_addr = ip_dst_addr;

        // send back to source port for software PS implementation
        hdr.udp.dst_port = eg_md.switchml_udp_md.src_port;

        // disable UDP checksum for now
        hdr.udp.checksum = 0;

        // update IPv4 checksum
        eg_md.update_ipv4_checksum = true;

        // or in set bit
        hdr.switchml.pool_index[15:15] = eg_md.switchml_md.pool_index[0:0];
        //hdr.switchml.pool_index[13:0] = eg_md.switchml_md.pool_index[14:1];
        //hdr.switchml.pool_index[14:14] = 1w0;
        //hdr.switchml.pool_index = hdr.switchml.pool_index | (eg_md.switchml_md.pool_index[0:0] ++ 15w0);
        //hdr.switchml.pool_index[15:15] = hdr.switchml.pool_index | (eg_md.switchml_md.pool_index[0:0] ++ 15w0);

        // set exponent header
        hdr.exponents.setValid();
        hdr.exponents.e0 = exponent_hash.get({
                eg_md.switchml_exponents_md.e1,
                eg_md.switchml_exponents_md.e0});
        
        // count send
        send_counter.count();
    }
    
    table set_dst_addr {
        key = {
            eg_md.switchml_md.worker_id : exact; // who are we sending to?
        }
        actions = {
            set_dst_addr_for_SwitchML_UDP;
        }
        size = max_num_workers;

        counters = send_counter;
    }

    apply {
        // TODO: currently these are already active, so this is a no-op
        hdr.ethernet.setValid();
        hdr.ipv4.setValid();
        hdr.udp.setValid();
        hdr.switchml.setValid();
        hdr.switchml.pool_index = 16w0;

        
        switch_mac_and_ip.apply();
        set_dst_addr.apply();
    }
}


#endif /* _SET_DST_ADDR_ */
