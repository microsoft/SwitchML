// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _NEXT_STEP_
#define _NEXT_STEP_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

// enable this for testing in the model. This avoids using port 64 for loopback.
// start the model with the flag --int-port-loop 0xe to enable loopback in pipes 1-3.
#ifdef SWITCHML_TEST
#define LOOPBACK_DEBUG
#endif

#define LOOPBACK_DEBUG

control NextStep(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    // hack to allow switching on and off the alternate recirc port in pipes 1 and 3
    PortId_t alternate_recirc_port;
    bool use_alternate_recirc_port;
    
    action set_alternate_recirc_port(PortId_t port) {
        alternate_recirc_port = port;
        use_alternate_recirc_port = true;
    }
    
    table recirc_port {
        actions = {
            @defaultonly set_alternate_recirc_port;
            @defaultonly NoAction;
        }
        //default_action = set_alternate_recirc_port(68); // default is oversubscribed port
        default_action = NoAction;
    }
    

    bool count_consume;
    bool count_harvest;

    bool count_broadcast;
    bool count_retransmit;
    bool count_recirculate;
    bool count_drop;

    DirectCounter<counter_t>(CounterType_t.PACKETS_AND_BYTES) next_step_counter;
        
    //Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) consume_counter;
    //Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) harvest_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) broadcast_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) retransmit_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) recirculate_counter;
    Counter<counter_t, pool_index_t>(register_size, CounterType_t.PACKETS) drop_counter;

    action drop() {
        // mark for drop
        ig_dprsr_md.drop_ctl[0:0] = 1;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE;
        count_drop = true;
        
        //next_step_counter.count();
    }

    // drop packet but mark it as a consume
    action finish_consume() {
        // mark for drop but don't change the packet type
        ig_dprsr_md.drop_ctl[0:0] = 1;
        count_consume = true;
        count_drop = true;
        //next_step_counter.count();
    }

    action recirculate_for_consume(packet_type_t packet_type, PortId_t recirc_port) {
        // drop both data headers now that they've been consumed
        hdr.d0.setInvalid();
        hdr.d1.setInvalid();

        // recirculate to port on next pipe
        ig_tm_md.ucast_egress_port = recirc_port;
        ig_tm_md.bypass_egress = 1w1;
        ig_dprsr_md.drop_ctl[0:0] = 0;
        ig_md.switchml_md.packet_type = packet_type;

        count_consume = true;
        count_recirculate = true;
        
        //next_step_counter.count();
    }

    action recirculate_for_CONSUME3_same_port_next_pipe() {
        recirculate_for_consume(packet_type_t.CONSUME3, 2w3 ++ ig_intr_md.ingress_port[6:0]);
    }
    
    action recirculate_for_CONSUME2_same_port_next_pipe() {
        recirculate_for_consume(packet_type_t.CONSUME2, 2w2 ++ ig_intr_md.ingress_port[6:0]);
    }
    
    action recirculate_for_CONSUME1(PortId_t recirc_port) {
        recirculate_for_consume(packet_type_t.CONSUME1, recirc_port);
    }

    action recirculate_for_harvest(packet_type_t packet_type, PortId_t recirc_port) {
        // recirculate for harvest on next pipe
        ig_tm_md.ucast_egress_port = recirc_port;
        ig_tm_md.bypass_egress = 1w1;
        ig_dprsr_md.drop_ctl[0:0] = 0;
        ig_md.switchml_md.packet_type = packet_type;

        count_harvest = true;
        count_recirculate = true;

        //next_step_counter.count();
    }

    action recirculate_for_HARVEST7_same_port() {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST7, ig_intr_md.ingress_port);
    }

    action recirculate_for_HARVEST7(PortId_t recirc_port) {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST7, recirc_port);
    }

    action recirculate_for_HARVEST7_256B(PortId_t recirc_port) {
        // this is called on the last consume pass for 1024B packets,
        // so the first 128B of updates is in hdr.d1.

        // get rid of input data in hdr.d0
        hdr.d0.setInvalid();

        // Just use existing ICRC we left in packet buffer!
        // // add empty ICRC header since this is the deepest we'll be in the packet
        // // TODO: right now there's a bug aliasing this and ig_md.first_last_flag, so don't set it
        // hdr.ib_icrc.setValid();
        // //hdr.ib_icrc.icrc = 0xffffffff;

        // // for now, make debug copy of packet!
        // ig_tm_md.copy_to_cpu = 1;

        
        // go collect the next 128B
        recirculate_for_harvest(packet_type_t.HARVEST7,recirc_port);
    }

    action recirculate_for_HARVEST6(PortId_t recirc_port) {
        hdr.d1.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST6, recirc_port);
    }

    action recirculate_for_HARVEST5(PortId_t recirc_port) {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST5, recirc_port);
    }

    action recirculate_for_HARVEST5_same_port() {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST5, ig_intr_md.ingress_port);
    }

    action recirculate_for_HARVEST4(PortId_t recirc_port) {
        hdr.d1.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST4, recirc_port);
    }

    action recirculate_for_HARVEST4_alternate_port() {
        recirculate_for_HARVEST4(alternate_recirc_port);
    }

    action recirculate_for_HARVEST3_same_port() {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST3, ig_intr_md.ingress_port);
    }

    action recirculate_for_HARVEST2(PortId_t recirc_port) {
        hdr.d1.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST2, recirc_port);
    }

    action recirculate_for_HARVEST1_1024B(PortId_t recirc_port) {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST1, recirc_port);
    }

    action recirculate_for_HARVEST1_same_port_1024B() {
        hdr.d0.setInvalid();
        recirculate_for_harvest(packet_type_t.HARVEST1, ig_intr_md.ingress_port);
    }
    
    
    action recirculate_for_HARVEST0(PortId_t recirc_port) {
        // clear out both headers, since the curent data will be replaced with the harvested data
        hdr.d0.setInvalid();
        hdr.d1.setInvalid();

        // go collect the first 128B
        recirculate_for_harvest(packet_type_t.HARVEST0, recirc_port);
    }

    action broadcast_eth() {
        hdr.d1.setInvalid();

        // // set the switch as the source MAC address
        // hdr.ethernet.src_addr = hdr.ethernet.dst_addr;
        // // destination address will be filled in egress pipe

        // send to multicast group; egress will fill in destination IP and MAC address
        ig_tm_md.mcast_grp_a = ig_md.switchml_md.mgid;
        ig_tm_md.level1_exclusion_id = null_level1_exclusion_id; // don't exclude any nodes
        ig_md.switchml_md.packet_type = packet_type_t.BROADCAST;
        ig_tm_md.bypass_egress = 1w0;
        ig_dprsr_md.drop_ctl[0:0] = 0;

        count_broadcast = true;

        //next_step_counter.count();
    }
    
    action broadcast_udp() {
        broadcast_eth();
    }
    
    action broadcast_roce() {
        broadcast_eth();
    }

    action retransmit_eth() {
        hdr.d1.setInvalid();
        
        // send back out ingress port
        ig_tm_md.ucast_egress_port = ig_md.switchml_md.ingress_port;
        ig_md.switchml_md.packet_type = packet_type_t.RETRANSMIT;
        ig_tm_md.bypass_egress = 1w0;
        ig_dprsr_md.drop_ctl[0:0] = 0;

        count_retransmit = true;
        
        //next_step_counter.count();
    }
    
    action retransmit_udp() {
        retransmit_eth();
    }

    action retransmit_roce() {
        // Just use existing ICRC we left in packet buffer!
        // // add empty ICRC header
        // hdr.ib_icrc.setValid();
        retransmit_eth();
    }

    table next_step {
        key = {
            ig_md.switchml_md.packet_size : ternary;

            // decide how to spread recirculation load across the ports in each pipe
            //ig_md.switchml_md.recirc_port_selector : ternary;
            //ig_md.switchml_md.pool_index : ternary; // leads to retransmissions
            ig_md.switchml_md.worker_id : ternary; // leads to retransmissions
            
            ig_md.switchml_md.packet_type : ternary;
            ig_md.first_last_flag : ternary; // 1: last 0: first
            ig_md.map_result : ternary;
            ig_md.switchml_md.worker_type : ternary;
            //hdr.d1.d00 : ternary; // TODO: not used. dummy input to monitor this value in the model.
            use_alternate_recirc_port : ternary;
        }
        actions = {
            recirculate_for_HARVEST7_256B;
            recirculate_for_HARVEST6;
            recirculate_for_HARVEST4;
            recirculate_for_HARVEST4_alternate_port;
            recirculate_for_HARVEST2;
            recirculate_for_CONSUME1;
            recirculate_for_CONSUME2_same_port_next_pipe;
            recirculate_for_CONSUME3_same_port_next_pipe;
            recirculate_for_HARVEST7;
            recirculate_for_HARVEST7_same_port;
            recirculate_for_HARVEST5;
            recirculate_for_HARVEST5_same_port;
            recirculate_for_HARVEST3_same_port;
            recirculate_for_HARVEST1_1024B;
            recirculate_for_HARVEST1_same_port_1024B;
            recirculate_for_HARVEST0;
            drop;
            finish_consume;
            broadcast_udp;
            retransmit_udp;
            broadcast_roce;
            retransmit_roce;
        }
        const entries = {
            //        packet type | last |map result|worker_type

            //
            // Due to challenges with forming the egress port number,
            // we dispatch on the lower bits of the queue pair number
            // and set the recirculation port to ensure ordering of
            // requests to the same memory locations.
            //

            //
            // 128B packets: Not supported, but should be easy if we
            // wanted for some reason? (TODO?)
            //
            (packet_size_t.IBV_MTU_128, _, _, _, _, _, _) :drop();
            
            //
            // 256B packets: Pipe 0 only
            //
            
            // For CONSUME packets that are the last packet, recirculate for harvest.
            // Choose between the two recirculation ports in pipe 0.
// #ifdef LOOPBACK_DEBUG
//             (packet_size_t.IBV_MTU_256, 0 &&& 1, packet_type_t.CONSUME0, 1, _, _, _) :recirculate_for_HARVEST7_256B(452);
// #else
//             (packet_size_t.IBV_MTU_256, 0 &&& 1, packet_type_t.CONSUME0, 1, _, _, _) :recirculate_for_HARVEST7_256B(448);            
// #endif
            //(packet_size_t.IBV_MTU_256, 1 &&& 1, packet_type_t.CONSUME0, 1, _, _, _) :recirculate_for_HARVEST7_256B(452);
            //(packet_size_t.IBV_MTU_256,       _, packet_type_t.CONSUME0, 1, _, _, _) :recirculate_for_HARVEST7_256B(452);
            (packet_size_t.IBV_MTU_256,       _, packet_type_t.CONSUME0, 1, _, _, _) :recirculate_for_HARVEST7_256B(68);
            
            // just consume any CONSUME packets if they're not last and we haven't seen them before
            (packet_size_t.IBV_MTU_256,       _, packet_type_t.CONSUME0, _, 0, _, _) :finish_consume();
            
            // for CONSUME packets that are retransmitted packets to a full slot, recirculate for harvest
// #ifdef LOOPBACK_DEBUG
//             (packet_size_t.IBV_MTU_256, 0 &&& 1, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST7_256B(452);
// #else
//             (packet_size_t.IBV_MTU_256, 0 &&& 1, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST7_256B(448);
// #endif
//            (packet_size_t.IBV_MTU_256, 1 &&& 1, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST7_256B(452);
            //(packet_size_t.IBV_MTU_256,       _, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST7_256B(452);
            (packet_size_t.IBV_MTU_256,       _, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST7_256B(68);
            
            // drop others
            (packet_size_t.IBV_MTU_256,       _, packet_type_t.CONSUME0, _, _, _, _) :drop();


            //
            // 512B packets: Not yet supported. Should be mostly the
            //  same as 1024B packets. (TODO?)
            //
            (packet_size_t.IBV_MTU_512, _, _, _, _, _, _) :drop();


            //
            // 1024B packets
            //

            //
            // current recirculation pattern:
            // consume: pipe 3 -> pipe 1 -> pipe 2 -> pipe 0
            // harvest: pipe0 -> pipe 2 -> pipe 2 -> pipe 1  -> pipe 1 -> pipe 3 -> pipe 3 -> egress
            //

            // Pipe 3: first pipe
            //
            // If pipe 3 receives a CONSUME packet we haven't seen before, recirculate it to finish consuming.
            // Choose between the 16 front-panel loopback ports based on slot ID.
            // Break this out this way because of issues assigning bitfields to the egress port metadata field.
            (packet_size_t.IBV_MTU_1024, 0x0 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(128); // pipe 1
            (packet_size_t.IBV_MTU_1024, 0x1 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(132);
            (packet_size_t.IBV_MTU_1024, 0x2 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(136);
            (packet_size_t.IBV_MTU_1024, 0x3 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(140);
            (packet_size_t.IBV_MTU_1024, 0x4 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(144);
            (packet_size_t.IBV_MTU_1024, 0x5 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(148);
            (packet_size_t.IBV_MTU_1024, 0x6 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(152);
            (packet_size_t.IBV_MTU_1024, 0x7 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(156);
            (packet_size_t.IBV_MTU_1024, 0x8 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(160);
            (packet_size_t.IBV_MTU_1024, 0x9 &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(164);
            (packet_size_t.IBV_MTU_1024, 0xa &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(168);
            (packet_size_t.IBV_MTU_1024, 0xb &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(172);
            (packet_size_t.IBV_MTU_1024, 0xc &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(176);
            (packet_size_t.IBV_MTU_1024, 0xd &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(180);
            (packet_size_t.IBV_MTU_1024, 0xe &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(184);
            (packet_size_t.IBV_MTU_1024, 0xf &&& 0xf, packet_type_t.CONSUME0, _, 0, _, _) :recirculate_for_CONSUME1(188);

            // For retransmitted packets to a full slot, recirculate for harvest.
            // Run through the same path as novel packets to ensure ordering.
            (packet_size_t.IBV_MTU_1024, 0x0 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(128); // pipe 1
            (packet_size_t.IBV_MTU_1024, 0x1 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(132);
            (packet_size_t.IBV_MTU_1024, 0x2 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(136);
            (packet_size_t.IBV_MTU_1024, 0x3 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(140);
            (packet_size_t.IBV_MTU_1024, 0x4 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(144);
            (packet_size_t.IBV_MTU_1024, 0x5 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(148);
            (packet_size_t.IBV_MTU_1024, 0x6 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(152);
            (packet_size_t.IBV_MTU_1024, 0x7 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(156);
            (packet_size_t.IBV_MTU_1024, 0x8 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(160);
            (packet_size_t.IBV_MTU_1024, 0x9 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(164);
            (packet_size_t.IBV_MTU_1024, 0xa &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(168);
            (packet_size_t.IBV_MTU_1024, 0xb &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(172);
            (packet_size_t.IBV_MTU_1024, 0xc &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(176);
            (packet_size_t.IBV_MTU_1024, 0xd &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(180);
            (packet_size_t.IBV_MTU_1024, 0xe &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(184);
            (packet_size_t.IBV_MTU_1024, 0xf &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_CONSUME1(188);

            // // For retransmitted packets to a full slot, recirculate for harvest.
            // // Skip to last pipe and start the harvest directly to leave bandwidth for the recirculation in middle pipes
            // //(packet_size_t.IBV_MTU_1024,           _, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(68);  // serialize harvest
            // (packet_size_t.IBV_MTU_1024, 0x0 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(0);
            // (packet_size_t.IBV_MTU_1024, 0x1 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(4);
            // (packet_size_t.IBV_MTU_1024, 0x2 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(8);
            // (packet_size_t.IBV_MTU_1024, 0x3 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(12);
            // (packet_size_t.IBV_MTU_1024, 0x4 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(16);
            // (packet_size_t.IBV_MTU_1024, 0x5 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(20);
            // (packet_size_t.IBV_MTU_1024, 0x6 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(24);
            // (packet_size_t.IBV_MTU_1024, 0x7 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(28);
            // (packet_size_t.IBV_MTU_1024, 0x8 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(32);
            // (packet_size_t.IBV_MTU_1024, 0x9 &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(36);
            // (packet_size_t.IBV_MTU_1024, 0xa &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(40);
            // (packet_size_t.IBV_MTU_1024, 0xb &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(44);
            // (packet_size_t.IBV_MTU_1024, 0xc &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(48);
            // (packet_size_t.IBV_MTU_1024, 0xd &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(52);
            // (packet_size_t.IBV_MTU_1024, 0xe &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(56);
            // (packet_size_t.IBV_MTU_1024, 0xf &&& 0xf, packet_type_t.CONSUME0, 0, _, _, _) :recirculate_for_HARVEST0(60);

            // drop others
            // TODO: I reach here when workers have gotten out of sync.
            // DEBUG: reached here
            // ig_md_switchml_md_first_last_flag          0x1
            // ig_md_switchml_md_map_result               0x1
            (packet_size_t.IBV_MTU_1024,           _, packet_type_t.CONSUME0, _, _, _, _) :drop();
            // // recirculate to see if we need to retransmit
            // (packet_size_t.IBV_MTU_1024, 0x0 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(128); // pipe 1
            // (packet_size_t.IBV_MTU_1024, 0x1 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(132);
            // (packet_size_t.IBV_MTU_1024, 0x2 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(136);
            // (packet_size_t.IBV_MTU_1024, 0x3 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(140);
            // (packet_size_t.IBV_MTU_1024, 0x4 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(144);
            // (packet_size_t.IBV_MTU_1024, 0x5 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(148);
            // (packet_size_t.IBV_MTU_1024, 0x6 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(152);
            // (packet_size_t.IBV_MTU_1024, 0x7 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(156);
            // (packet_size_t.IBV_MTU_1024, 0x8 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(160);
            // (packet_size_t.IBV_MTU_1024, 0x9 &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(164);
            // (packet_size_t.IBV_MTU_1024, 0xa &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(168);
            // (packet_size_t.IBV_MTU_1024, 0xb &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(172);
            // (packet_size_t.IBV_MTU_1024, 0xc &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(176);
            // (packet_size_t.IBV_MTU_1024, 0xd &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(180);
            // (packet_size_t.IBV_MTU_1024, 0xe &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(184);
            // (packet_size_t.IBV_MTU_1024, 0xf &&& 0xf, packet_type_t.CONSUME0, _, _, _, _) :recirculate_for_CONSUME1(188);

            // Pipe 1: second pipe
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME1, _, _, _, _) :recirculate_for_CONSUME2_same_port_next_pipe();

            // Pipe 2: third pipe
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME2, _, _, _, _) :recirculate_for_CONSUME3_same_port_next_pipe();

            // Pipe 0: fourth and last pipe
            // For CONSUME packets that are the last packet, recirculate for harvest.
            // The last pass is a combined consume/harvest pass, so skip directly to HARVEST1
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, 1, _, _, _) :recirculate_for_HARVEST1_1024B(68); // serialize harvest
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, 1, _, _, _) :recirculate_for_HARVEST1_1024B(452); // serialize harvest
            // // BUG: this causes some sort of weird CRC errors when using front-panel ports in loopback
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, 1, _, _, _) :recirculate_for_HARVEST1_same_port_1024B();
            
            // just consume any CONSUME packets if they're not last and we haven't seen them before
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, _, 0, _, _) :finish_consume();
            
            // for CONSUME packets that are retransmitted packets to a full slot, recirculate for harvest
            // The last pass is a combined consume/harvest pass, so skip directly to HARVEST1
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, 0, _, _, _) :recirculate_for_HARVEST1_1024B(68); // serialize harvest
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, 0, _, _, _) :recirculate_for_HARVEST1_1024B(452); // serialize harvest
            // // BUG: this causes some sort of weird CRC errors when using front-panel ports in loopback
            // (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, 0, _, _, _) :recirculate_for_HARVEST1_same_port_1024B();
            
            // drop others
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.CONSUME3, _, _, _, _) :drop();

            // start harvesting first 128B in last pipe
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST0, _, _, _, _) :recirculate_for_HARVEST1_1024B(68);  // serialize harvest
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST0, _, _, _, _) :recirculate_for_HARVEST1_1024B(452);  // serialize harvest
            // // BUG: this causes some sort of weird CRC errors when using front-panel ports in loopback
            // (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST0, _, _, _, _) :recirculate_for_HARVEST1_same_port_1024B();
            
            // finish recirculation for 1024B in last pipe and continue in third pipe
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(324);  // serialize harvest

            // // BUG: this causes some sort of weird CRC errors when using front-panel ports in loopback
            // (packet_size_t.IBV_MTU_1024, 0x0 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(256);
            // (packet_size_t.IBV_MTU_1024, 0x1 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(260);
            // (packet_size_t.IBV_MTU_1024, 0x2 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(264);
            // (packet_size_t.IBV_MTU_1024, 0x3 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(268);
            // (packet_size_t.IBV_MTU_1024, 0x4 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(272);
            // (packet_size_t.IBV_MTU_1024, 0x5 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(276);
            // (packet_size_t.IBV_MTU_1024, 0x6 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(280);
            // (packet_size_t.IBV_MTU_1024, 0x7 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(284);
            // (packet_size_t.IBV_MTU_1024, 0x8 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(288);
            // (packet_size_t.IBV_MTU_1024, 0x9 &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(292);
            // (packet_size_t.IBV_MTU_1024, 0xa &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(296);
            // (packet_size_t.IBV_MTU_1024, 0xb &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(300);
            // (packet_size_t.IBV_MTU_1024, 0xc &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(304);
            // (packet_size_t.IBV_MTU_1024, 0xd &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(308);
            // (packet_size_t.IBV_MTU_1024, 0xe &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(312);
            // (packet_size_t.IBV_MTU_1024, 0xf &&& 0xf, packet_type_t.HARVEST1, _, _, _, _) :recirculate_for_HARVEST2(316);

            // recirculate one more time in third pipe
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST2, _, _, _, _) :recirculate_for_HARVEST3_same_port();

            // finish recirculation for 1024B in third pipe and continue in second pipe
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST3, _, _, _, true) :recirculate_for_HARVEST4(192);  // alternate port
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST3, _, _, _, true) :recirculate_for_HARVEST4_alternate_port();  // alternate port
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST3, _, _, _,    _) :recirculate_for_HARVEST4(196);  // serialize harvest
            
            // // BUG: this causes some sort of weird CRC errors when using front-panel ports in loopback
            // (packet_size_t.IBV_MTU_1024, 0x0 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(128);
            // (packet_size_t.IBV_MTU_1024, 0x1 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(132);
            // (packet_size_t.IBV_MTU_1024, 0x2 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(136);
            // (packet_size_t.IBV_MTU_1024, 0x3 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(140);
            // (packet_size_t.IBV_MTU_1024, 0x4 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(144);
            // (packet_size_t.IBV_MTU_1024, 0x5 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(148);
            // (packet_size_t.IBV_MTU_1024, 0x6 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(152);
            // (packet_size_t.IBV_MTU_1024, 0x7 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(156);
            // (packet_size_t.IBV_MTU_1024, 0x8 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(160);
            // (packet_size_t.IBV_MTU_1024, 0x9 &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(164);
            // (packet_size_t.IBV_MTU_1024, 0xa &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(168);
            // (packet_size_t.IBV_MTU_1024, 0xb &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(172);
            // (packet_size_t.IBV_MTU_1024, 0xc &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(176);
            // (packet_size_t.IBV_MTU_1024, 0xd &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(180);
            // (packet_size_t.IBV_MTU_1024, 0xe &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(184);
            // (packet_size_t.IBV_MTU_1024, 0xf &&& 0xf, packet_type_t.HARVEST3, _, _, _, _) :recirculate_for_HARVEST4(188);

            // recirculate one more time in second pipe
            // put on second recirc port to provide sufficent bandwidth for line rate
            // TODO: currently this requires manual intervention to enable the second port; if not enabled, we don't have enough bandwidth for line rate.
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST4, _, _, _, _) :recirculate_for_HARVEST5_alternate_port(); // serialize harvest
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST4, _, _, _, _) :recirculate_for_HARVEST5_same_port();
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST4, _, _, _, _) :recirculate_for_HARVEST5(196);

            // finish recirculation for 1024B in second pipe and continue in first pipe
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _, _) :recirculate_for_HARVEST6(452); // serialize harvest
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _, _) :recirculate_for_HARVEST6_alternate_port(); // serialize harvest
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _, true) :recirculate_for_HARVEST6(448); // alternate port
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _, true) :recirculate_for_HARVEST6(444); // alternate port
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _,    _) :recirculate_for_HARVEST6(452); // serialize harvest
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _, true) :recirculate_for_HARVEST6(64); // alternate port
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _,    _) :recirculate_for_HARVEST6(68); // serialize harvest

            // Assume this port works for recirculation.
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST5, _, _, _,    _) :recirculate_for_HARVEST6(64); // serialize harvest.
// #ifdef LOOPBACK_DEBUG
//             (packet_size_t.IBV_MTU_1024, 0 &&& 1, packet_type_t.HARVEST5, _, _, _, _) :recirculate_for_HARVEST6(452);
// #else
//             (packet_size_t.IBV_MTU_1024, 0 &&& 1, packet_type_t.HARVEST5, _, _, _, _) :recirculate_for_HARVEST6(448);
// #endif
//             (packet_size_t.IBV_MTU_1024, 1 &&& 1, packet_type_t.HARVEST5, _, _, _, _) :recirculate_for_HARVEST6(452);
            
            // recirculate once in pipe 0 before finishing
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST6, _, _, _, _) :recirculate_for_HARVEST7(448);  // serialize harvest
            //(packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST6, _, _, _, _) :recirculate_for_HARVEST7(452);
            (packet_size_t.IBV_MTU_1024, _, packet_type_t.HARVEST6, _, _, _, _) :recirculate_for_HARVEST7(68);
            
            //
            // Harvest pass 7: final pass
            //
            // Read final 128B and send to PRE with correct setting
            // for packet type.
            //
            
            // broadcast any HARVEST packets that are not retransmitted, are the last packet, and the protocol is implemented
            (_, _, packet_type_t.HARVEST7, 1, 0, worker_type_t.SWITCHML_UDP, _) :broadcast_udp();
            (_, _, packet_type_t.HARVEST7, 1, 0, worker_type_t.ROCEv2, _) :broadcast_roce();
            // drop any HARVEST packets that are not retransmitted, are the last packet, and we don't have a protocol implementation
            (_, _, packet_type_t.HARVEST7, 1, 0, _, _) :drop(); // TODO: support other formats
            // shouldn't ever get here, because the packet would be dropped in CONSUME
            (_, _, packet_type_t.HARVEST7, 0, 0, _, _) :drop(); // shouldn't ever get here
            // retransmit any other HARVEST packets for which we have an implementation
            (_, _, packet_type_t.HARVEST7, 0, _, worker_type_t.SWITCHML_UDP, _) :retransmit_udp();
            (_, _, packet_type_t.HARVEST7, 0, _, worker_type_t.ROCEv2, _) :retransmit_roce();
            // drop any other HARVEST packets
            (_, _, packet_type_t.HARVEST7, _, _, _, _) :drop(); // TODO: support other formats
            // ignore other packet types
        }
        const default_action = drop();
        //counters = next_step_counter;
    }
    
    //Random<drop_probability_t>() rng;

    // Actions to count packets. Do this in actions instead
    // of inline to make debugging output more readable. 
    action count_drop_action()        { drop_counter.count(ig_md.switchml_md.pool_index); }
    action count_recirculate_action() { recirculate_counter.count(ig_md.switchml_md.pool_index); }
    action count_broadcast_action()   { broadcast_counter.count(ig_md.switchml_md.pool_index); }
    action count_retransmit_action()  { retransmit_counter.count(ig_md.switchml_md.pool_index); }

    // Actions to set slot status flags for bitmaps to be used in harvest. Do
    // this in actions instead of inline to make debugging output more
    // readable. These depend on being initialized to false in the parser.
    action set_map_result_nonzero()    { ig_md.switchml_md.map_result_nonzero = true; }    
    action set_bitmap_before_nonzero() { ig_md.switchml_md.bitmap_before_nonzero = true; }
    action set_first_flag()            { ig_md.switchml_md.first_flag = true; }
    action set_last_flag()             { ig_md.switchml_md.last_flag = true;  }
    
    apply {
        count_consume = false;
        count_harvest = false;

        count_broadcast = false;
        count_retransmit = false;
        count_recirculate = false;
        count_drop = false;

        use_alternate_recirc_port = false;
        recirc_port.apply();
        
        next_step.apply();


        if (count_consume || count_drop) {
            count_drop_action();
        }
        
        if (count_recirculate) {
            count_recirculate_action();
        }

        if (count_broadcast) {
            count_broadcast_action();
        }

        if (count_retransmit) {
            count_retransmit_action();
        }


        // set/overwrite slot status flags for harvest passes
        if (ig_md.map_result           != 0) { set_map_result_nonzero(); }
        if (ig_md.worker_bitmap_before != 0) { set_bitmap_before_nonzero(); }
        if (ig_md.first_last_flag      == 0) { set_first_flag(); }
        if (ig_md.first_last_flag      == 1) { set_last_flag(); }
    }
}

#endif /* _NEXT_STEP_ */
