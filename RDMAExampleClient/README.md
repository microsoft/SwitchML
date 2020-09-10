
SwitchML RDMA example client
============================

This is example code for doing SwitchML reductions using RDMA. It performs a sequence of allreduces in a loop, and then verifies the result.

MPI is used to coordinate between client processes, but not to move data, so it should be set to ignore the RDMA interface to avoid interference.

# Required libraries

* libibverbs-dev (Tested with MLNX_OFED_LINUX-5.0-2.1.8.0)
* libgflags-dev (Tested with 2.2.1-1, installed from apt)
* libhugetlbfs-dev (Tested with 2.19-0ubuntu1, installed from apt)
* MPI (Tested with OpenMPI 4.0.3rc4, installed from apt)
* protobuf (see below)
* grpc (see below)

# Usage

I built and ran this on Ubuntu 18.04, with the libraries described above.

Run ```make``` to build the client code.

To run the client code, use a command like:
```
mpirun --host prometheus35,prometheus36 -np 2 --mca pml ucx -x UCX_TLS=tcp -x UCX_NET_DEVICES=eno5 --map-by core --bind-to none --tag-output ./client --server 7170c --gid_index=3 --packet_size=256 --message_size=4096 --length=268435456 --slots_per_core=1 --cores=1 --iters=100 --timeout=0.001
```

* Make s

# Design and repo structure

* ```client.cpp```: toplevel client code
* ```Endpoint.{hc}pp```: Code to set up RoCE NIC
* ```Connections.{hc}pp```: Code to set up queue pairs between NIC and switch

# GRPC and Protobufs

We use GRPC to coordinate with the switch. The default Ubuntu 18.04 packages for GRPC and Protobufs didn't work for us so I built my own and installed them in ```/usr/local``` as described at https://grpc.io/docs/languages/cpp/quickstart and below. You may be able to use the libraries installed the Barefoot toolchain instead if it's installed on all your worker nodes.

```
cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DgRPC_SSL_PROVIDER=package ../..
make -j
sudo make install
sudo ldconfig
```

# Disabling ICRC checking on NIC

RoCE packets have a additional CRC (the ICRC) on the end of the packet after the payload and before the Ethernet FCS. This is difficult for us to generate for large packets in Tofino 1, so we disable it on the NIC using register info provided by Mellanox.

To disable ICRC checking, use ```mstmcra``` to set the following registers:
* ConnectX-3: set 0x45084.10:1 to 0x1; set 0x4506c.10:1 to 0x0
* ConnectX-4: set all to 0: 0x5363c.12:1 0x5367c.12:1 0x53634.29:1 0x53674.29:1
* ConnectX-5: set all to 0: 0x5361c.12:1 0x5363c.12:1 0x53614.29:1 0x53634.29:1
* ConnectX-6: (will have to ask Mellanox)

To re-enable ICRC checking, restore those registers to their previous values.

Some NICs have the firmware "locked" to avoid malicious changes to the registers. This was the case for our HP 842QSFP28 NICs. If the ICRC disable script reports no change in the registers, you'll need to obtain an unlock token from your vendor (or possibly Mellanox) and apply it like this:
```
sudo mlxconfig -d mlx5_0 apply ~/firmware/HPE0000000014-16.26.1040-2020-04-16T20_56_10.596387.support.token.bin
```

