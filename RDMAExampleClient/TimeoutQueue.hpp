// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef __TIMEOUTQUEUE__
#define __TIMEOUTQUEUE__

#include <vector>
#include <iostream>

class TimeoutQueue {
private:

  struct Entry {
    uint64_t timestamp;
    int next;
    int previous;
    Entry() : timestamp(0), next(-1), previous(-1) { }
  };

  std::vector<Entry> entries;
  int head;

  const int DEBUG = false;
  //const int DEBUG = true;
  
public:
  TimeoutQueue(const int num_entries)
    : entries(num_entries+1) // add an extra for the tail
    , head(num_entries) // point at last, tail entry
  {
    // nothing to do here
  }

  // insert entry into queue. it is assumed that entry will not be
  // older than any previous entry.
  void push(int index, uint64_t timestamp) {
    if (DEBUG) std::cout << "TimeoutQueue: adding " << index << " with timestamp " << timestamp << std::endl;
    if (DEBUG) print();
      
    if (index < (entries.size() - 1)) { // don't change tail entry
      // warn if new insertion is older than current head
      if (timestamp < entries[head].timestamp) {
        std::cerr << "Warning: inserting  entry for " << index
                  << " at timestamp " << timestamp
                  << " when latest entry was for " << head
                  << " with timestamp " << entries[head].timestamp
                  << "; insert will be out of order."
                  << std::endl;
      }
      
      // remove current entry for this index
      remove(index);
      
      // set up new entry at head of list
      entries[index].timestamp = timestamp;
      entries[index].previous = -1; // no previous link since this is newest
      entries[index].next = head;
      
      // add back link to new entry
      entries[head].previous = index;
      
      // change head
      head = index;
    }

    if (DEBUG) std::cout << "TimeoutQueue: added " << index << " with timestamp " << timestamp << std::endl;
    if (DEBUG) print();
  }

  // remove particular entry
  void remove(int index) {
    if (DEBUG) std::cout << "TimeoutQueue: removing " << index << " with timestamp " << entries[index].timestamp << std::endl;
    if (DEBUG) print();
    
    if (index < (entries.size() - 1)) { // don't remove tail entry
      // if the entry has a previous link
      if (entries[index].previous != -1) {
        // copy this entry's next link to its previous link
        entries[entries[index].previous].next = entries[index].next;
      }
      
      // if the entry has a next link
      if (entries[index].next != -1) {
        // copy this entry's next link to its previous link
        entries[entries[index].next].previous = entries[index].previous;
      }

      // if this entry is at the head
      if (head == index) {
        head = entries[index].next;
      }

      // zero out entry
      entries[index].timestamp = 0;
      entries[index].next = -1;
      entries[index].previous = -1;
    }

    if (DEBUG) std::cout << "TimeoutQueue: removed " << index << " with timestamp " << entries[index].timestamp << std::endl;
    if (DEBUG) print();
  }

  // pop entry at head of queue
  void pop() {
    remove(head);
  }

  // peek at entry at head of queue
  std::pair<int, uint64_t> top() const {
    if (DEBUG) std::cout << "TimeoutQueue: head is " << head << " with timestamp " << entries[head].timestamp << std::endl;
    return std::make_pair(head, entries[head].timestamp);
  }

  // peek at entry at tail of queue
  std::pair<int, uint64_t> bottom() const {
    int tail = entries.back().previous;
    uint64_t timestamp = 0;
    if (tail != -1) {
      timestamp = entries[tail].timestamp;
    }

    if (DEBUG) std::cout << "TimeoutQueue: tail is " << tail << " with timestamp " << timestamp << std::endl;
    if (DEBUG) print();

    return std::make_pair(tail, timestamp);
  }

  void print() const {
    for (int i; i < entries.size(); ++i) {
      std::cout << "(" << i
                << ": " << entries[i].previous
                << " " << entries[i].timestamp
                << " " << entries[i].next
                << ")";
    }
    std::cout << "(head: " << head
              << ")" << std::endl;
  }
};
  

#endif //  __TIMEOUTQUEUE__
