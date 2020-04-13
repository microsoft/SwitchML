/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _SET_DST_ADDR_
#define _SET_DST_ADDR_

control SetDestinationAddress(
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    inout header_t hdr) {

    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) send_counter;

    //
    // read switch MAC and IP from table to form output packets
    //
    action set_switch_mac_and_ip(mac_addr_t switch_mac, ipv4_addr_t switch_ip) {

        // TODO: currently these are already active, so this is a no-op
        hdr.ethernet.setValid();
        hdr.ipv4.setValid();
        hdr.udp.setValid();

        // set switch addresses
        hdr.ethernet.src_addr = switch_mac;
        hdr.ipv4.src_addr = switch_ip;

        // TODO: should we do this swap here or elsewhere?
        hdr.udp.src_port = hdr.udp.dst_port;
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
        hdr.udp.dst_port = eg_md.switchml_md.dst_port;

        // disable UDP checksum for now
        hdr.udp.checksum = 0;

        // update IPv4 checksum
        eg_md.update_ipv4_checksum = true;

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
        switch_mac_and_ip.apply();
        set_dst_addr.apply();
    }
}


#endif /* _SET_DST_ADDR_ */
