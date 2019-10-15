SwitchML for RoCE in P4_16
==========================

This is another implementation of the SwitchML idea, but done in P4_16 and tweaked to support larger packets and RDMA via RoCE.

NOTE: RDMA support is not yet complete.




//* 64 32-bit integers for 256 bytes of payload
//* 8 one-byte exponents


SwitchML packet format
----------------------

NOTE: for now only the SwitchML UDP or Eth approach is supported.
 
There are four ways to send packets to be aggreagted:
* SwitchML/UDP: data is sent with SwitchML header inside UDP/IP/Ethernet
* SwitchML/Ethernet: data is sent with SwitchML header inside Ethernet
* RoCEv2: data is sent in IB_BTH frames in UDP/IP/Ethernet. RoCE data includes SwitchML header.
* RoCEv1: data is sent in IB_BTH frames in IB_GRH/Ethernet. RoCE data includes SwitchML header.


This design uses a slightly different packet format than Amedeo's
implementation. It's set up as follows:
* Ethernet
* IP
* UDP (port 0xbee0)
* SwitchML
* exponents
* significands

The number of exponents is variable, as is the number of significands. Edit configuration.p4 to configure these.

To support large packets, significands are split over two headers. This allows us to con



Design overview
---------------



*Pool*: a collection of aggregator slots

*Slot*: register storage for one packet's worth of data

*Set*: each pool is divided into two sets: odd and even. Pools should
always be allocated in multiples of two, so that we have storage for
both sets.

*Consume*: adding values into registers

*Harvest*: reading aggregated values out of registers

Pools are allocate to jobs in segments in this design. The workers use
0-baesd indices, and the switch uses a per-job base index to
convert that to an offset into its registers.

Ingress processing
------------------

Egress processing
------------------
There are two main tasks that happen in egress.

* Drop simulation. To simulate switch-to-worker packet drops, 
  

* Destination address processing. 

Drop simulation
---------------





* Convert from little- to big-endian

* Convert back from big- to little-endian



Maximum register size
---------------------

What's the maximum register size we can allocate in Tofino 1 and 2?

From a per-stage perspective, here are the limits:
* each stage has 80 128x1024b SRAM blocks
* each stage can support 4 registers (and we want 4 so that we get the
  highest ALU bandwidth)
* each register can be up to 2x32b=64b wide
* each register requires 1 extra SRAM block for simultaneous read/write
* a single register can use up to 35(+1 extra)=36 SRAM blocks
* each stage can support up to 48 blocks for register memories (including the 1 extra)

This is based on the Tofino 1 and 2 Switch Architecture Specifications
and the Stateful Processing in 10K Series documents. I believe Tofino
2 has the same properties per stage; it just has more stages.

If we could use all the SRAM blocks in a stage for registers, that
would be 80 - 1*4 = 76, or 76 / 4 = 19 = 38912 64-bit entries. But
this isn't supported by the architecture.

If we only wanted a single register in a stage, we'd hit the 36-block
limit first. That would use 35 blocks for data and 1 for simultaneous
read/write, or 71680 64-bit entries.

But we want to use all 4 ALU blocks in a stage. That means we will hit
the 48-block limit first. We want each register to be the same size,
so that means each register then can be only 12 total blocks, or 11
for data and 1 for simultaneous read/write. That is 22528 64-bit
entries.

So the total number of slots allocated per pipeline in this design is
22528.

