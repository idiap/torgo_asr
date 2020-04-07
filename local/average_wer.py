#!/usr/bin/env python3

# Copyright 2019  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

import sys

count = 0
wers = 0
for line in sys.stdin:
    line = line.strip()
    if line == '':
        if count > 0:
            print("%.2f %s" % (wers / count, exp))
        count = 0
        wers = 0
        continue
    fields = line.split()
    exp = fields[-1]
    wer = float(fields[1])
    count += 1
    wers += wer

if count > 0:
    print("%.2f %s" % (wers / count, exp))
