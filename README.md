SwitchML in P4_16
=================

This is an implementation of the SwitchML concept, but done in P4_16
and tweaked to support larger packets and RDMA via RoCE. It's very
much a work in progress.


Status
------

This is a preliminary version of the P4_16 code; it works as described
in the paper, but I have lots of plans to improve it.

Things to do:
* This code is impacted by a number of compiler bugs, all of which
  have been reported. When fixed, the workarounds will need to be
  undone. Search for "BUG" in the code to find these places.
* The control plane and tests use the BF Runtime GRPC API, which was
  still under development when this code was written against SDE
  9.1.0. The API may change in future releases of the SDE, and this
  code will benefit from being updated (in particular, faster register
  clearing will be handy)
* The code has the beginnings of isolation support for multiple jobs,
  but this is currently not implemented.
* The code has the beginnings of support for hierarchical and
  multi-pipeline reductions, but this is currently not implemented.
* The code has the beginnings of support for non-SwitchML-UDP packets,
  including RDMA/RoCE and SwitchML-Ethernet, but these are not yet
  implemented.
* Right now all payloads must be padded to the full payload size set
  in configuration.p4
* The current design uses only one recirculation port per pipeline, so
  the minimum supported job size at full line rate may be limited by
  recirculation bandwidth to about 7 or 8 workers. We can cut that in
  half by modifying the code to use two recirculation ports.
* Drop simulation is not currently supported.

Requirements
------------

For the SwitchML p4 code, the main requirement is SDE 9.1.0.

For the control plane, Python 2.7 with Scapy and other SDE dependences
is required. This should be installed on any machine with the SDE
installed. 


Instructions
------------

* Clone the switchml repo.
* Build the P4 code with a command like ```p4_build.sh p4/switchml.p4``` or the equivalent.
* Either  edit ```py/switchml.py``` for your job configuration, or make your own version of ```py/prometheus-fib.yml``` and ```py/prometheus-switchML.yml``` files, to be used with the ```--ports``` and ```--job``` arguments, respectively.
* Run your modified control plane in a shell with the $SDE environment variable set: ```python py/switchml.py```
  * If you are using YAML files, run like ```python py/switchml.py --ports <FIB file> --job <job file>```
* Ensure Daiet is configured with ```num_updates = 64```.
* Run your job using the SwitchML server-side code.

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

*Set*: each pool element is divided into two sets: odd and even. Pools should
always be allocated in multiples of two, so that we have storage for
both sets.

*Consume*: adding values into registers

*Harvest*: reading aggregated values out of registers


SwitchML packet format
----------------------

NOTE: for now only the SwitchML UDP packet format is supported.
 
Eventually, there are four ways to send packets to be aggreagted:
* SwitchML/UDP: data is sent with SwitchML header inside UDP/IP/Ethernet
* SwitchML/Ethernet: data is sent with SwitchML header inside Ethernet
* RoCEv2: data is sent in IB_BTH frames in UDP/IP/Ethernet. RoCE data includes SwitchML header.
* RoCEv1: data is sent in IB_BTH frames in IB_GRH/Ethernet. RoCE data includes SwitchML header.


This design expects the packet to be laid out like this:
* Ethernet
* IP
* UDP (port 0xbee0)
* SwitchML header
* SwitchML exponents
* SwitchML significands

The current code is set up for one exponent and 64 significands per
packet. The code should be easily modifiable to change this.

To deal with the Tofino 1 imbalance between register write and read
bandwidth, each packet is divided into two halves. Both halves are
consumed in the packet's first trip through the pipeline, but only the
first half is harvested. When it is time to send an aggregated packet,
the packet is recirculated and the second half is harvested before the
packet is replicated and sent out.


Design overview
---------------

TBD

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
this isn't supported.

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

Endianness conversion
---------------------

TBD. Currently we don't do endianness conversion in the switch.

There are two natural ways to do endianness conversion in
Tofino 1. The first is in the parser, using 8-bit extractors. This is
only practical at small scales, since we can only extract 4 8-bit
values per cycle.

The second is using the hash calculation units. There are 8 per pipe
stage, and each can output 52 bits, so in theory we could do 8*52=416,
or 13 32-bit conversions per stage. However, I believe that we have to
use a hash distribution unit to get the output of a hash calculation
unit into the PHV, and there are only 6 16-bit hash distribution units
per pipe stage. That limits us to 3 32-bit conversions per
stage. However, some of these are already being used for the register
address calculation, so we might be even more limited in using this
technique.

There may be a better way to do this in the Tofino, but these are my
preliminary thoughts. I did some implementation that suggested the
compiler was doing something smarter than either of what I described,
but I couldn't get it to work for all 64 parameters.

