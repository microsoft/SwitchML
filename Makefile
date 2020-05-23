#############################################################################
# MICROSOFT CONFIDENTIAL & PROPRIETARY
# 
# Copyright (c) 2019 Microsoft Corp.
# All Rights Reserved.
#############################################################################

TARGET=client
OBJECTS=main.o Endpoint.o Connections.o Reducer.o ClientThread.o
LIBRARIES=-libverbs -lgflags -lhugetlbfs

$(TARGET): $(OBJECTS)
main.o: Reducer.hpp Connections.hpp Endpoint.hpp common.hpp
Connections.o: Connections.hpp Endpoint.hpp common.hpp
Reducer.o: Reducer.hpp Endpoint.hpp Connections.hpp common.hpp Barrier.hpp ClientThread.hpp
ClientThread.o: Endpoint.hpp Reducer.hpp ClientThread.hpp Connections.hpp

$(TARGET): 
	mpicxx --std=c++17 -g -o $@ $^ $(LIBRARIES)

%.o: %.cpp Makefile
	mpicxx --std=c++17 -g -c -o $@ $<

clean::
	rm -f $(TARGET) $(OBJECTS)

#run:: umr-sender
#run:: mpiuc
# run:: mpitest
# 	mpirun --host prometheus42,prometheus50 -np 2 --tag-output ./$< $(COUNT) $(SIZE)

HOSTS=prometheus50,prometheus50
NUM_PROCS=2
ARGS=
# $(COUNT) $(SIZE)
run:: $(TARGET)
	mpirun --host $(HOSTS) -np 2 --tag-output ./$< $(ARGS)
	#./$<


debug:: $(TARGET)
	mpirun -mca mpi_abort_delay 10 --host $(HOSTS) -np 2 --tag-output ./$< $(ARGS)
#	mpirun --host $(HOSTS) -np 2 --tag-output ./$< $(ARGS)
