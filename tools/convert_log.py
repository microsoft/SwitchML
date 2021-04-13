#!/usr/bin/env python3

#
# This code takes data from the SwitchML debug log modules in the
# switch and converts it to an Excel file for analysis.
#
# To use it, first run a reduction on the switch.
#
# Then, on the switch, do:
#   -> log_save debug_log.yaml
# Copy debug_log.yaml to your local machine.
# Then convert to an Excel file:
#   $ python3 convert_log.py debug_log.yaml
# This will generate debug_log.xlsx.
# You may then open the file in Excel for analysis.
#

from enum import IntEnum
from pprint import pprint, pformat
import yaml
import os
import sys
import xlsxwriter

class PacketType(IntEnum):
    NONE       = 0x0
    BROADCAST  = 0x1
    RETRANSMIT = 0x2
    IGNORE     = 0x3
    CONSUME0   = 0x4
    CONSUME1   = 0x5
    CONSUME2   = 0x6
    CONSUME3   = 0x7
    HARVEST0   = 0x8
    HARVEST1   = 0x9
    HARVEST2   = 0xa
    HARVEST3   = 0xb
    HARVEST4   = 0xc
    HARVEST5   = 0xd
    HARVEST6   = 0xe
    HARVEST7   = 0xf

class MessageSeq(IntEnum):
    MIDDLE = 0x0
    LAST   = 0x1
    FIRST  = 0x2
    ONLY   = 0x3

class WorkerSeq(IntEnum):
    MIDDLE = 0x0
    LAST   = 0x1
    FIRST  = 0x2
    ONLY   = 0x3
    EGRESS = 0x4

class MapResult(IntEnum):
    NOVEL      = 0x0
    RETRANSMIT = 0x1
    EGRESS     = 0x2
    
class BitmapBefore(IntEnum):
    EMPTY    = 0x0
    NONEMPTY = 0x1
    EGRESS   = 0x2

class Packet():
    
    def __init__(self,
                 capture_index,
                 capture_pipe,
                 address_bits,
                 packet_id,
                 ingress_pipe,
                 worker_id,
                 message_sequence,
                 bitmap_before,
                 map_result,
                 worker_sequence,
                 packet_type,
                 pool_index,
                 pool_set):
        # set values from initialization
        self.capture_index = capture_index
        self.capture_pipe = capture_pipe
        self.address_bits = address_bits
        self.packet_id = packet_id
        self.ingress_pipe = ingress_pipe
        self.worker_id = worker_id
        self.message_sequence = message_sequence
        self.bitmap_before = bitmap_before
        self.map_result = map_result
        self.worker_sequence = worker_sequence
        self.packet_type = packet_type
        self.pool_index = pool_index
        self.pool_set = pool_set

    @classmethod
    def parse(cls, capture_index, capture_pipe, entry):
        address_bits            = (entry >> (32+11))     # upper 8 bits of 19-bit packet_id
        packet_id               = 0x7ff & (entry >> 32)  # lower 11 bits of 19-bit packet_id
        ingress_pipe            = 0x3 & (entry >> 30)
        worker_id               = 0x1f & (entry >> 25)
        first_packet_of_message = 1 == (1 & (entry >> 24))
        last_packet_of_message  = 1 == (1 & (entry >> 23))
        nonzero_bitmap_before   = 1 == (1 & (entry >> 22))
        nonzero_map_result      = 1 == (1 & (entry >> 21))
        first_worker_for_slot   = 1 == (1 & (entry >> 20))
        last_worker_for_slot    = 1 == (1 & (entry >> 19))
        packet_type             = PacketType(0xf & (entry >> 15))
        pool_index              = 0x3fff & (entry >> 1)
        pool_set                = 1 & entry

        message_seq   = MessageSeq(first_packet_of_message * 2 + last_packet_of_message)

        # handle egress
        if packet_type is PacketType.BROADCAST or packet_type is PacketType.RETRANSMIT:
            first_worker_for_slot = False
            last_worker_for_slot  = False
            nonzero_bitmap_before = False
            nonzero_map_result    = False

        if packet_type is PacketType.BROADCAST:
            worker_seq    = WorkerSeq.EGRESS
            map_result    = MapResult.NOVEL
            bitmap_before = BitmapBefore.EGRESS
        elif packet_type is PacketType.RETRANSMIT:
            worker_seq    = WorkerSeq.EGRESS
            map_result    = MapResult.RETRANSMIT
            bitmap_before = BitmapBefore.EGRESS
        else:
            worker_seq    = WorkerSeq(first_worker_for_slot * 2 + last_worker_for_slot)
            map_result    = MapResult(nonzero_map_result)
            bitmap_before = BitmapBefore(nonzero_bitmap_before)

        
        
        return cls(capture_index,
                   capture_pipe,
                   address_bits,
                   packet_id,
                   ingress_pipe,
                   worker_id,
                   message_seq,
                   bitmap_before,
                   map_result,
                   worker_seq,
                   packet_type,
                   pool_index,
                   pool_set)

    def __repr__(self):
        return ("<Packet" +
                " capture_index:" + str(self.capture_index) +
                " capture_pipe:" + str(self.capture_pipe) +
                " address_bits:" + str(self.address_bits) +
                " packet_id:" + str(self.packet_id) +
                " ingress_pipe:" + str(self.ingress_pipe) +
                " worker_id:" + str(self.worker_id) +
                " message_sequence:" + str(self.message_sequence.name) +
                " bitmap_before:" + str(self.bitmap_before.name) +
                " map_result:" + str(self.map_result.name) +
                " worker_sequence:" + str(self.worker_sequence.name) +
                " packet_type:" + str(self.packet_type.name) +
                " pool_index:" + str(self.pool_index) +
                " pool_set:" + str(self.pool_set) +
                ">")

def rotate_packet_list(pkts):
    # if there's a discontinuity in the indices that's probably where to look
    first_index_guess = None
    possible_indices = []
    last_index = 0
    for i, p in enumerate(pkts):
        if p.capture_index != last_index + 1:
            possible_indices.append(i)
        last_index = p.capture_index

    if len(possible_indices) > 2:
        print("Warning: Found more than two possible indices for a list: {}".format(possible_indices))
    elif len(possible_indices) == 0:
        print("Warning: Found no possible indices for a pipeline.")
        return pkts

    first_index = possible_indices[-1]
    if first_index == 0:
        return pkts
    else:
        return pkts[first_index:] + pkts[:first_index]

    
def convert_file(yaml_filename, excel_filename = None):
    print('Loading file {}...'.format(yaml_filename))
      
    with open(yaml_filename, 'r') as f:
        log = yaml.load(f, Loader=yaml.Loader)

    print('File {} loaded.'.format(yaml_filename))
    #pprint(log)

    parsed = []
    parsed1 = []
    parsed2 = []
    parsed3 = []
    for i, (p0, p1, p2, p3) in log['Ingress'].items():
        if p0 != 0:
            parsed.append(Packet.parse(i, 0, p0)) # first pipe
        if p1 != 0:
            parsed1.append(Packet.parse(i, 1, p1)) # second pipe
        if p2 != 0:
            parsed2.append(Packet.parse(i, 2, p2)) # third pipe
        if p3 != 0:
            parsed3.append(Packet.parse(i, 3, p3)) # fourth pipe

    parsed = rotate_packet_list(parsed)
    parsed1 = rotate_packet_list(parsed1)
    parsed2 = rotate_packet_list(parsed2)
    parsed3 = rotate_packet_list(parsed3)

    parsed.extend(parsed1)
    parsed.extend(parsed2)
    parsed.extend(parsed3)

    egress_parsed = []
    egress_parsed1 = []
    egress_parsed2 = []
    egress_parsed3 = []
    for i, (p0, p1, p2, p3) in log['Egress'].items():
        if p0 != 0:
            egress_parsed.append(Packet.parse(i, 0, p0)) # first pipe
        if p1 != 0:
            egress_parsed1.append(Packet.parse(i, 1, p1)) # second pipe
        if p2 != 0:
            egress_parsed2.append(Packet.parse(i, 2, p2)) # third pipe
        if p3 != 0:
            egress_parsed3.append(Packet.parse(i, 3, p3)) # fourth pipe

    egress_parsed = rotate_packet_list(egress_parsed)
    egress_parsed1 = rotate_packet_list(egress_parsed1)
    egress_parsed2 = rotate_packet_list(egress_parsed2)
    egress_parsed3 = rotate_packet_list(egress_parsed3)

    parsed.extend(egress_parsed)    
    parsed.extend(egress_parsed1)
    parsed.extend(egress_parsed2)
    parsed.extend(egress_parsed3)

    # for p in parsed:
    #     pprint(p)
    # return
    print("Parsed {} records.".format(len(parsed)))

    if excel_filename is None:
        excel_filename = os.path.splitext(yaml_filename)[0] + '.xlsx'
        
    print("Writing Excel file {}....".format(excel_filename))
    with xlsxwriter.Workbook(excel_filename) as workbook:
        worksheet = workbook.add_worksheet()

        #worksheet.write("A1", "Type")

        fields = [('Capture Pipe',     lambda p: p.capture_pipe),
                  ('Packet ID',        lambda p: p.packet_id),
                  ('Worker ID',        lambda p: p.worker_id),
                  ('Packet Type',      lambda p: p.packet_type),
                  ('Address Bits',     lambda p: p.address_bits),
                  ('Pool Index',       lambda p: p.pool_index),
                  ('Pool Set',         lambda p: p.pool_set),
                  ('Worker Sequence',  lambda p: p.worker_sequence),
                  ('Bitmap Before',    lambda p: p.bitmap_before),
                  ('Map Result',       lambda p: p.map_result),
                  ('Message Sequence', lambda p: p.message_sequence),
                  ('Ingress Pipe',     lambda p: p.ingress_pipe),
                  ('Capture Index',    lambda p: p.capture_index)]

        row = 0
        column_width = 12
        for i, f in enumerate([first for first, second in fields]):
            worksheet.write_string(row, i, f)
            worksheet.set_column(i, i, column_width)
            
        for p in parsed:
            row += 1
            for i, f in enumerate([second for first, second in fields]):
                val = f(p)
                if isinstance(val, IntEnum):
                    worksheet.write_string(row, i, val.name)
                elif isinstance(val, int):
                    worksheet.write_number(row, i, val)
                else:
                    print("Not sure how to handle value {} of type {}.".format(val, type(val)))

        # add filter
        worksheet.autofilter(0, 0, row, len(fields)-1)
        
        # freeze top line
        worksheet.freeze_panes(1, 0)

        # add conditional format for out-of-sequence values
        red_format = workbook.add_format({'bg_color':   '#FFC7CE',
                                          'font_color': '#9C0006'})
        yellow_format = workbook.add_format({'bg_color':   '#FFEB9C',
                                             'font_color': '#9C6500'})
        green_format = workbook.add_format({'bg_color':   '#C6EFCE',
                                            'font_color': '#006100'})
        blue_format = workbook.add_format({'bg_color':   '#94ABD7',
                                            'font_color': '#0000FF'})
        orange_format = workbook.add_format({'bg_color':   '#F2F2F2',
                                            'font_color': '#EA8532'})

        # highlight retransmissions
        worksheet.conditional_format(1, 9, row, len(fields)-4,
                                     {'type': 'formula',
                                      'criteria': '$J2="RETRANSMIT"',
                                      'format': orange_format})
        
        # highlight acceptable sequence violations due to harvest operations, within a single pipe
        worksheet.conditional_format(1, 1, row, len(fields)-2,
                                     {'type': 'formula',
                                      'criteria': 'AND($B2=$B1,$A2=$A1)',
                                      'format': green_format})

        # highlight sequence violations that are not from harvest operations, within a single pipe
        worksheet.conditional_format(1, 1, row, len(fields)-2,        
                                     {'type': 'formula',
                                      'criteria': 'AND(OR($B2<$B1, $B2>$B1+1), $A2=$A1)',
                                      'format': red_format})
        # highlight set 1 operations
        worksheet.conditional_format(1, 0, row, len(fields)-1,
        #worksheet.conditional_format(1, 5, row, 5,
                                     {'type': 'formula',
                                      'criteria': '$G2=1',
                                      'format': yellow_format})
        
        # highlight set 0 operations
        worksheet.conditional_format(1, 0, row, len(fields)-1,
        #worksheet.conditional_format(1, 5, row, 5,
                                     {'type': 'formula',
                                      'criteria': '$G2=0',
                                      'format': blue_format})
        
        
    print("Done writing Excel file {}.".format(excel_filename))
    
if __name__ == '__main__':
    if len(sys.argv) == 2:
        convert_file(sys.argv[1])
    elif len(sys.argv) == 3:
        convert_file(sys.argv[1], sys.argv[2])
    else:
        print("Converts a packet log to an Excel file for analysis.")
        print("Usage: {} <source .yaml file> [<destination Excel (.xlsx) file>]")
        sys.exit(1)
        
