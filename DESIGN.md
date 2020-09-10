
# SwitchML-RDMA protocol description

This file describes how we use RDMA to communicate with the SwitchML program running in a switch. 

Our goal in using RDMA with SwitchML is threefold:
1) Reduce PCIe overhead by offloading packetization to NIC
2) Send/receive more coarse-grained messages to amortize message processing software overhead
3) Read/write GPU memory directly

We need to communicate a bunch of information between workers and the switch:
- Significands
- Exponent(s): at least 8 bits
- Pool index: 16ish bits
- Location in vector represented by this message: 32 to 64 bits

This is challenging with RDMA messages, because we have a number of restrictions and limitations on what we can send.
- RDMA packet data payload MTUs are fixed at one of 256, 512, 1024, 2048, or 4096 bytes. 
- RDMA supports a single 32-bit immediate value per message (not per packet).
- RDMA writes also include a 64-bit address and a 32-bit rkey per message.


Worker/Switch communication
==============================

The SwitchML-UDP protocol has the following properties:
* The pool_index is a 16-bit field.
* The lower 15 bits (or less) of the pool_index point at a set of two slots.
* The MSB of the pool_index indicates which slot of a set is to be used. 
* Each slot is the size of one packet.
* Retransmission of a slot involves resending a single packet.

The RDMA protocol is a little different, for the following reasons:
* The worker sends at message granularity, but the switch processes packets.
* Thus, each message is processed in multiple, sequential, packet-sized slots on the switch.
* Packets in a message must arrive in order. On a single queue pair, Packets from multiple messages can't be interleaved.

So, we make some simplifying assumptions:
* We have a separate queue pair for each outstanding message. Each queue pair is used for both sets of a slot, since only one set can be outstanding for a worker at a time.
* The first packet of a message specifies the base pool index and set for that message. Each subsequent packet in that message will use the next pool index and same set.
* Retransmission of a slot involves resending an entire message, with all its packets. The switch must avoid re-applying an update from a packet it has already received, as it does today.
* Currently the packets of a message are sent as that slot completes. (This may need to change, to wait until the message completes.)
* When a job starts, each worker must communicate with the switch to set up its queue pairs. 
* Packet sizes are configured when the job is set up.
* Message sizes may vary over the course of a job, but they must be the same from all workers for a particular pool index. The size of the incoming message determines the size of the reply message.
* On the worker-to-switch path:
  * We use the lower 16 bits of the rkey to hold the packet-sized pool index. The low-order bit determines which set the packet is for.
  * The address field is the address the response should be written to. This must be the same on all workers. (Optionally, we can make this an index.)
  * Each message has an immediate value, which contains 4 8-bit exponents.
* On the switch-to-worker path:
  * The rkey is the rkey of the memory region used by the NIC to complete the write
  * The address is the destination address used by the NIC to complete the write
  * The immediate value is the max of each of the 4 exponents sent by workers
  
