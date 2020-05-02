#############################################################################
# MICROSOFT CONFIDENTIAL & PROPRIETARY
# 
# Copyright (c) 2019 Microsoft Corp.
# All Rights Reserved.
#############################################################################

TARGET=client
OBJECTS=main.o Endpoint.o #Reducer.o
LIBRARIES=-libverbs -lgflags

$(TARGET): $(OBJECTS)
main.o: Reducer.hpp Endpoint.hpp
#Reducer.o: Endpoint.hpp

$(TARGET):
	mpicxx --std=c++17 -g -o $@ $^ $(LIBRARIES)

%.o: %.cpp
	mpicxx --std=c++17 -g -c -o $@ $<

clean::
	rm -f $(TARGET) $(OBJECTS)

#run:: umr-sender
#run:: mpiuc
# run:: mpitest
# 	mpirun --host prometheus42,prometheus50 -np 2 --tag-output ./$< $(COUNT) $(SIZE)

HOSTS=prometheus50,prometheus50
NUM_PROCS=2
# $(COUNT) $(SIZE)
run:: $(TARGET)
	mpirun --host $(HOSTS) -np 2 ./$<
	#./$<

