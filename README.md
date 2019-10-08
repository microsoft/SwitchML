SwitchML for RoCE in P4_16
==========================

This is another implementation of the SwitchML idea, but done in P4_16 and tweaked to support RDMA.

* 64 32-bit integers for 256 bytes of payload
* 8 one-byte exponents

There are four ways to send packets to be aggreagted:
* SwitchML/UDP: data is sent in SwitchML header in UDP/IP/Ethernet
* SwitchML/Ethernet: data is sent in SwitchML header in /Ethernet
* RoCEv2: data is sent in IB_BTH frames in UDP/IP/Ethernet
* RoCEv1: data is sent in IB_BTH frames in IB_GRH/Ethernet

NOTE: for now only the SwitchML/UDP approach is supported.

SwitchML packet format
----------------------

This design uses a slightly different packet format than Amedeo's implementation. It's set up as follows:
* Ethernet
* IP
* UDP (port 0xbee0)
* SwitchML
* 4 bytes of exponents
* 128 bytes of data
* 4 bytes of exponents
* 128 bytes of data


