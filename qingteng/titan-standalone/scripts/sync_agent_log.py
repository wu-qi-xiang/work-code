#!/usr/bin/env python

"""Sync agent compressed error log and decompress it

"""

import getopt
import os
import os.path
import re
import sys

def usage():
    print """usage: sync_agent_log.py -s <sourcedir> [ -d <destdir> ] [ -t <ndays> -m <nmin> ]
    <sourcedir> is the source directory to sync
    <targetdir> is the target destination
    <ndays> is the last N day of log to sync
    <nmin> is the last N minutes of log to sync

    -s source directory
    -d target location
    -t sets the number of days to sync
    -m sets the number of minutes to sync
    -v sets the sync to verbose

    long options also work:
    --verbose
    --sourcedir=<sourcedir>
    --destdir=<destdir>"""

def main():
    short_args = "vhs:d:t:m:"
    long_args = ["verbose", "help", "sourcedir=", "destdir="]

    try:
        opts, args = getopt.getopt(sys.argv[1:], short_args, long_args)
    except getopt.GetoptError:
        usage()
        sys.exit(2)

    verbose = False
    source_dir = ""
    dest_dir = ""
    ndays = None
    nmin = None

    for opt, arg in opts:
        if opt in ("-v", "--verbose"):
            verbose = True
        if opt in ("-s", "--sourcedir"):
            source_dir = arg
        if opt in ("-d", "--destdir"):
            dest_dir = arg
        if opt in "-t":
            ndays = arg
        if opt in "-m":
            nmin = arg
        if opt in ("-h", "--help"):
            usage()
            sys.exit()

    if source_dir == "" or dest_dir == "" or not os.path.isdir(source_dir):
        usage()
        sys.exit()

    source_dir = os.path.abspath(source_dir)
    dest_dir = os.path.abspath(dest_dir)
    if ndays:
        cmd = "find %s -mtime -%s -type f" % (source_dir, ndays)
    if nmin:
        cmd = "find %s -mmin -%s -type f" % (source_dir, nmin)
    if verbose:
        print cmd
    cmd_file = os.popen(cmd)
    cmd_out = cmd_file.read()

    os.system("date")
    print "Sync following agent logs:"
    for line in cmd_out.splitlines():
        source_file = line
        dest_file = re.sub(source_dir, dest_dir, line)
        dest_path = os.path.dirname(dest_file)
        os.system("mkdir -p " + dest_path)
        if source_file.endswith(".gz"):
            dest_file_flat = re.sub(r"\.gz$", "", dest_file)
            if not os.path.isfile(dest_file_flat) and dest_file.endswith(".gz"):
                os.system("cp " + source_file + " " + dest_file)
                os.system("gzip -d -f " + dest_file)
                print dest_file_flat
        elif source_file.endswith(".log"):
            dest_file_gz = dest_file + ".gz"
            if not os.path.isfile(dest_file):
                os.system("cp " + source_file + " " + dest_file_gz)
                os.system("gzip -d -f " + dest_file_gz)
                print dest_file

if __name__ == "__main__":
    main()
