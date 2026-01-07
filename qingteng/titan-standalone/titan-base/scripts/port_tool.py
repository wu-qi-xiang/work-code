#!/usr/bin/python
# -*- coding: utf-8 -*-

import sys
import socket
import threading
import getopt


def help():
    print "----------------------------------------------------------"
    print "                   Usage information"
    print "----------------------------------------------------------"
    print ""
    print "./port.py [Args] "
    print "  -s          start port listening with -p                "
    print "  -e          stop the port listening with -p             "
    print "  -h --host   ping server with -p                         "
    print "  -p --port   specify port                                "
    print ""
    print "  Start port listening:                                   "
    print "     ./port.py -s -p 80                                   "
    print "  Stop port listening:                                    "
    print "     ./port.py -e -p 80                                   "
    print "  Ping Server:                                            "
    print "     ./port.py -host 127.0.0.1 -p 80                      "
    print "----------------------------------------------------------"
    sys.exit(2)

def socketClient(ip, port):
    try:
        tmp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        result = tmp_sock.connect_ex((ip, port))
        if result == 0:
            return tmp_sock
        else:
            return 0
    except Exception as e:
        print str(e)
        return 0


def pingServer(ip, port):
    client = socketClient(ip, port)
    if client:
        print "Connection established (" + ip + ":" + str(port) + ")"
        client.close()
        sys.exit(0)
    else:
        print "Connect failed :" + ip + ":" + str(port)
        sys.exit(1)


def stopServer(ip, port):
    client = socketClient(ip, port)
    if client:
        client.send("exit")
    else:
        print "Connect failed :" + ip + ":" + str(port)


class TempServer(threading.Thread):
    def __init__(self, port):
        try:
            threading.Thread.__init__(self)
            self.port = port
            self._bufSize = 1024
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sock.bind(("0.0.0.0", port))
            self.sock.listen(0)
            print "Server started"
        except Exception as e:
            print str(e)

    def run(self):
        while True:
            client, cltadd = self.sock.accept()
            print "Accept connection from %s:%s..." % cltadd
            data = client.recv(self._bufSize)
            if data == "exit":
                print "Server exited"
                sys.exit(0)


def main(argv):
    host = ""
    # default port
    port = 80
    # 0: ping, 1: setup, 2:stop
    flag = 0
    try:
        opts, args = getopt.getopt(argv, "seh:p:", ["host=", "port="])
    except getopt.GetoptError:
        help()
    for opt, arg in opts:
        if opt == "-s":
            flag = 1
        elif opt == "-e":
            flag = 2
        elif opt in ("-h", "--host"):
            host = arg
        elif opt in ("-p", "--port"):
            port = arg
    if 1 == flag:
        ## launch server
        srv = TempServer(int(port))
        srv.start()
        sys.exit(0)
    elif 2 == flag:
        ## stop server
        stopServer("127.0.0.1", int(port))
        sys.exit(0)
    elif 0 == flag:
        if host:
            ## ping server
            pingServer(host, int(port))
        else:
            help()


if __name__ == '__main__':
    main(sys.argv[1:])
