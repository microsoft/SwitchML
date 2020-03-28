/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _SET_DST_ADDR_
#define _SET_DST_ADDR_

control SetDestinationAddress(
    in egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    inout header_t hdr) {

    action set_dst_addr_for_Ignore(mac_addr_t eth_dst_addr) {
        // do nothing. for Ignored packets, the header should already be fine for broadcast.
    }

    action set_dst_addr_for_SwitchML_Eth(mac_addr_t eth_dst_addr) {
        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        hdr.ethernet.dst_addr = eth_dst_addr;
    }

    action set_dst_addr_for_SwitchML_UDP(
        mac_addr_t eth_dst_addr,
        ipv4_addr_t ip_dst_addr,
        udp_port_t udp_dst_port) {
        
        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        hdr.ethernet.dst_addr = eth_dst_addr;

        hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        hdr.ipv4.dst_addr = ip_dst_addr;

        hdr.udp.src_port = hdr.udp.dst_port; // TODO: pull from table
        hdr.udp.dst_port = udp_dst_port;

        // disable UDP checksum for now
        hdr.udp.checksum = 0;
    }


    // NOTE: not functional yet: needs to set PSN and maybe other stuff
    action set_dst_addr_for_RoCEv1(
        mac_addr_t eth_dst_addr,
        ipv4_addr_t ip_dst_addr,
        ib_gid_t dst_gid,
        bit<24> qp) {

        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        hdr.ethernet.dst_addr = eth_dst_addr;
        
        hdr.ib_grh.sgid = hdr.ib_grh.dgid;
        hdr.ib_grh.dgid = dst_gid;
        
        hdr.ib_bth.dst_qp = qp;
    }

    // action set_dst_addr_for_RoCEv1_mac_based_guid(
    //     mac_addr_t eth_dst_addr,
    //     ipv4_addr_t ip_dst_addr,
    //     bit<24> qp) {
    //     set_dst_addr_for_RoCEv1(eth_dst_addr, ip_dst_addr, qp);
    //     // For mac-based GIDs, b8:83:03:74:01:8c is turned into fe80:0000:0000:0000:ba83:03ff:fe74:018c
    //     hdr.ib_grh.dgid = 64w0xfe80000000000000 ++ eth_dst_addr[47:32] ++ 16w0x03ff ++ eth_dst_addr[31:0];
    // }

    // action set_dst_addr_for_RoCEv1_ip_based_guid(
    //     mac_addr_t eth_dst_addr,
    //     ipv4_addr_t ip_dst_addr,
    //     bit<24> qp) {
    //     set_dst_addr_for_RoCEv1(eth_dst_addr, ip_dst_addr, qp);
    //     // for IP-based GIDs, 198.19.200.50 is turned into  0000:0000:0000:0000:0000:ffff:c613:c832
    //     hdr.ib_grh.dgid = 96w0x00000000000000000000ffff ++ ip_dst_addr;
    // }

    // NOTE: not functional yet: needs to set PSN and maybe other stuff
    action set_dst_addr_for_RoCEv2(
        mac_addr_t eth_dst_addr,
        ipv4_addr_t ip_dst_addr,
        bit<24> qp) {

        hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        hdr.ethernet.dst_addr = eth_dst_addr;

        hdr.ipv4.src_addr = hdr.ipv4.dst_addr;
        hdr.ipv4.dst_addr = ip_dst_addr;

        hdr.ib_bth.dst_qp = qp;
    }
    
    table set_dst_addr {
        key = {
            eg_md.switchml_md.packet_type : ternary;
            eg_intr_md.egress_rid  : ternary; // replication ID: indicates which worker we're sending to
        }
        actions = {
            set_dst_addr_for_RoCEv1;
            set_dst_addr_for_RoCEv2;
            set_dst_addr_for_SwitchML_UDP;
            set_dst_addr_for_SwitchML_Eth;
            set_dst_addr_for_Ignore;
            NoAction;
        }
        size = max_num_workers * 2;
        const default_action = NoAction;
    }

    apply {
        set_dst_addr.apply();
    }
}


#endif /* _SET_DST_ADDR_ */
