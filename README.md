SwitchML in P4_16
=================

This is an implementation of SwitchML in P4_16, with support for large packets and RDMA via RoCE.

Status
------

This is a work in progress.

Features:
* 256 byte (64 entry) or 1024 byte (256 entry) packets
* Up to 4 8-bit exponents per message
* Up to 32 workers in a job

Limitations:
* Only the first pipeline's front-panel ports (dev_ports 0 through 63) are currently supported, in order to support 1024 byte packets
* When used with RDMA, ICRC checking on the NIC must be disabled. See README.md in RDMAExampleClient for more info.
* The tests are not fully functional right now.

Requirements
------------

The p4 code requires SDE 9.1.0 or above.

For the control plane, Python 2.7 with Scapy and other SDE dependences
is required. This should be installed on any machine/switch with the SDE
installed. 

For use with RDMA, additional dependencies are required. See RDMAExampleClient/README.md for more details.

Instructions
------------

* Clone the switchml repo.
* Build the P4 code with a command like ```p4_build.sh p4/switchml.p4``` or the equivalent.
* Run the control plane with a command like ```python py/switchml.py```.
  * Set the switch MAC and IP with the ```--switch_mac``` and ```--switch_ip``` arguments.
  * To specify ports and MAC addresses, either edit ```py/switchml.py``` or make a version ```py/prometheus-fib.yml``` and load using the ```--ports``` argument.
* For RDMA, job configuration is done via GRPC.
* For SwitchML-UDP, job configuration can be done by loading a file like ```py/prometheus-fib.yml``` with the ```--job``` argument or the ```worker_file``` command in the CLI.

For use with Daiet, ensure Daiet is configured with ```num_updates = 64``` or ```num_updates = 256```.

For use with the RDMA example client, follow the directions in README.md in RDMAExampleClient.

Testing
-------

* Build with SWITCHML_TEST set to minimize register size for speedier
  model initialization:
  ```p4_build.sh p4/switchml.p4 -DSWITCHML_TEST=1```
* After starting model and switchd, run tests with ```bash run_tests.sh```

Glossary
--------

*Pool*: a collection of aggregator slots

*Slot*: register storage for one packet's worth of data

*Set*: each pool element is divided into two sets: odd and even. Pool sizes should always be multiples of two, so that we have storage for both sets.

*Consume*: adding values into registers

*Harvest*: reading aggregated values out of registers


SwitchML packet formats
-----------------------

This code supports two packet formats: the original UDP format, and RoCE v2.

For SwitchML-UDP, the packet is laid out like this:
* Ethernet
* IP
* UDP (base port 0xbee0)
* SwitchML header
* SwitchML exponent header
* SwitchML significands (either 256 bytes or 1024 bytes
* Ethernet FCS

For SwitchML-RDMA, the packet layout is slightly different depending on which part of a message a packet contains. A message with a single packet looks like this:
* Ethernet
* IP
* UDP (dest port: RoCEv2 (4791))
* IB BTH
* IB RETH, with the following components:
  * Address: virtual address response should be directed to
  * rkey: 
    * bits 31:16: currently unused
    * bits 15:1: pool index
    * bit 0: set bit
* IB IMM: contains 4 8-bit exponents
* Payload: significands, either 256 bytes or 1024 bytes
* IB ICRC: ignored
* Ethernet FCS


Design overview
---------------

TBD

