#! /usr/bin/env python
# -*- coding: utf-8 -*-

import os
# import sys
# reload(sys)
# sys.setdefaultencoding('utf8')
import importlib,sys
importlib.reload(sys)
from ansible import errors
from ansible.module_utils._text import to_native
import random
import string
import os
import hashlib
from base64 import b64decode,b64encode
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

# str_list：字符串列表
def format_list(str_list,format_str):
    try:
        if format_str is None or format_str == '':
            raise Exception("format_str can not be empty")

        new_list = [format_str.format(x) for x in str_list]
        return new_list
    except Exception as e:
        raise errors.AnsibleFilterError("format_list error: %s" % to_native(e))

# str_list：字符串列表
def format_and_join_list(str_list,format_str,separator=','):
    try:
        if format_str is None or format_str == '':
            raise Exception("format_str can not be empty")

        new_list = [format_str.format(str(x)) for x in str_list]
        return separator.join(new_list)
    except Exception as e:
        raise errors.AnsibleFilterError("format_and_join_list error: %s" % to_native(e))

# items： dict组成的list
def format_and_join_items(items,format_str,separator=','):
    try:
        if format_str is None or format_str == '':
            raise Exception("format_str can not be empty")

        new_list = [format_str.format(**item) for item in items]
        return separator.join(new_list)
    except Exception as e:
        raise errors.AnsibleFilterError("format_and_join_items error: %s" % to_native(e))

# 返回sublist
def sublist(items,start,end=None):
    try:
        if end is None:
            return items[int(start):]
        else:
            return items[int(start):int(end)]
    except Exception as e:
        raise errors.AnsibleFilterError("sublist error: %s" % to_native(e))

# create random string at least one LOWER,one UPPER, one DIGITS 
def randomString(length=16):
    """Generate a random String """
    randomSource = string.ascii_letters + string.digits
    randomStr = random.SystemRandom().choice(string.ascii_lowercase)
    randomStr += random.SystemRandom().choice(string.ascii_uppercase)
    randomStr += random.SystemRandom().choice(string.digits)

    for i in range(length-3):
        randomStr += random.SystemRandom().choice(randomSource)

    randomStrList = list(randomStr)
    random.SystemRandom().shuffle(randomStrList)
    randomStr = ''.join(randomStrList)
    return randomStr

def is_encrypted(conf_passwd):
    if conf_passwd.startswith("ENC(") and conf_passwd.endswith(")"):
        return True
    return False

def encrypt_string(plaintext, pbeconfig):
    passwd, salt = pbeconfig[:16],pbeconfig[16:]

    if is_encrypted(plaintext):
        return plaintext

    padder = padding.PKCS7(128).padder()
    padded_bytes = padder.update(plaintext.encode('utf-8')) + padder.finalize()

    finalKey = (passwd + salt).encode('utf-8')
    for i in range(1103):
        finalKey = hashlib.sha256(finalKey).digest()

    key = finalKey
    iv = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0".encode()

    backend = default_backend()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=backend)
    encryptor = cipher.encryptor()
    ciper_bytes = encryptor.update(padded_bytes) + encryptor.finalize()

    ciper_text = "ENC(" + b64encode(ciper_bytes).decode('utf-8') + ")"

    #print(ciper_text)
    return ciper_text

def decrypt_string(base64ciphertext, pbeconfig):
    passwd, salt = pbeconfig[:16],pbeconfig[16:]

    if not is_encrypted(base64ciphertext):
        return base64ciphertext

    # get real password from ENC()
    base64ciphertext = base64ciphertext[4:-1]

    finalKey = (passwd + salt).encode('utf-8')
    for i in range(1103):
        finalKey = hashlib.sha256(finalKey).digest()

    key = finalKey
    iv = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0".encode()
    ciphertext = b64decode(base64ciphertext)

    backend = default_backend()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=backend)
    decryptor = cipher.decryptor()
    plain_bytes = decryptor.update(ciphertext) + decryptor.finalize()

    unpadder = padding.PKCS7(128).unpadder()
    plain_text = (unpadder.update(plain_bytes) + unpadder.finalize()).decode("utf-8")

    #print(plain_text)
    return plain_text

def host_url(host_config):
    ipv4_ip = host_config['publicip']
    ipv6_ip = ipv4_ip if host_config['ipv6'] == '' else host_config['ipv6']
    protocol = 'https' if ('ssl' in host_config and host_config['ssl']) else 'http'
    port = ":" + str(host_config['port']) 
    if protocol == 'https' and host_config['port'] == 443:
        port = ''
    elif protocol == 'http' and host_config['port'] == 80:
        port = ''
    
    _url = '''{protocol}://{host}{port}'''
    if host_config['domain'] != '' and host_config['resolved']:
        host = host_config['domain']
        return _url.format(protocol=protocol,host=host,port=port)
    else:
        if ipv6_ip == ipv4_ip:
            return _url.format(protocol=protocol,host=ipv4_ip,port=port)
        else:
            return _url.format(protocol=protocol,host=ipv4_ip,port=port) + " " + _url.format(protocol=protocol,host=ipv6_ip,port=port)

def get_ssl_change(cur_hosts,new_hosts):
    result = {}
    for item in ['frontend','backend','api','agent','selector']:
        if cur_hosts[item].get('ssl',False) != new_hosts[item].get('ssl',False):
            result[item] = new_hosts[item].get('ssl',False)
    
    return result

def ssl_change_cmd(ssl_change):
    #这里sed语句的意思是修改第order个ssl配置
    _cmd = '''sed -i -r ':a;N;$!ba;s/ssl [^;]+/ssl {stat}/{order}' /data/app/conf/nginx.servers.conf '''
    order_map = {
        'frontend': '1',
        'backend': '2',
        'api': '3',
        'agent': '4'
    }
    cmd_list = []
    for name, stat in ssl_change.items():
        if name == 'selector':
            _selector_ssl_cmd = '''sed -i -r ':a;N;$!ba;s/ssl [^;]+/ssl {stat}/2' /data/app/conf/proxy/nginx.proxy.conf '''
            cmd_list.append(_selector_ssl_cmd.format(stat=('on' if stat else 'off' )))
        else:
            cmd_list.append(_cmd.format(order=order_map[name],stat=('on' if stat else 'off' )))
    
    return cmd_list

def get_port_change(cur_hosts,new_hosts):
    result = {}
    for item in ['frontend','backend','api','agent','selector']:
        if cur_hosts[item].get('port',False) != new_hosts[item].get('port',False):
            result[item] = new_hosts[item].get('port',False)
    
    return result

def port_change_cmd(port_change):
    #这里sed语句的意思是修改第order个port配置
    _cmd = '''sed -i -r ':a;N;$!ba;s/listen [^;]+/listen {port}/{order}' /data/app/conf/nginx.servers.conf '''
    order_map = {
        'frontend': '1',
        'backend': '2',
        'api': '3',
        'agent': '4'
    }
    cmd_list = []
    for name, port in port_change.items():
        if name == 'selector':
            _selector_port_cmd = '''sed -i -r ':a;N;$!ba;s/listen [^;]+/listen {port}/2' /data/app/conf/proxy/nginx.proxy.conf '''
            cmd_list.append(_selector_port_cmd.format(port=str(port)))
        else:
            cmd_list.append(_cmd.format(order=order_map[name],port=str(port)))
    
    return cmd_list

def create_rsa_key(keysize):
    #print(keysize)
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=int(keysize), backend=default_backend())
    private_pem_str = private_key.private_bytes(encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()).decode()
    
    public_key = private_key.public_key()
    public_pem_str = public_key.public_bytes(encoding=serialization.Encoding.PEM,
                format=serialization.PublicFormat.SubjectPublicKeyInfo).decode()

    #print(private_pem_str)
    #print(public_pem_str)
    
    return { "private_key": "".join(private_pem_str.splitlines()[1:-1]),
             "public_key": "".join(public_pem_str.splitlines()[1:-1]) }

def debugString(data):
    print(data)

class FilterModule(object):
    def filters(self):
        return {
          'format_list': format_list,
          'format_and_join_list': format_and_join_list,
          'format_and_join_items': format_and_join_items,
          'sublist': sublist,
          'decrypt_string': decrypt_string,
          'encrypt_string': encrypt_string,
          'randomString': randomString,
          'debugString': debugString,
          'host_url': host_url,
          'get_ssl_change': get_ssl_change,
          'ssl_change_cmd': ssl_change_cmd,
          'get_port_change': get_port_change,
          'port_change_cmd': port_change_cmd,
          'create_rsa_key': create_rsa_key
        }