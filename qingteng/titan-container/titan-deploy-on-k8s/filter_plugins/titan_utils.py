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
import time
import uuid
from base64 import b64decode,b64encode
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
from ansible.plugins.filter.core import combine

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


def debugString(data):
    print(data)

# 用于保证 titan_env的 value 全是string
def ensureMapString(data):
    result={}

    for key,value in data.items():
        if type(value) is bool:
            value = str(value).lower()
        else:
            value = str(value)
        result[key] = value
    return result

def from_properties(data):
    result = {}
    for line in data.splitlines():
        if line.strip().startswith("#"):
            continue
        if "=" not in line.strip():
            continue
        key,value = line.strip().split("=",1)
        result[key] = value

    return result


# 针对lookup k8s的返回结果获取一个pod， lookup k8s 返回的可能是个list，也可能是单个Pod对象
def get_one_pod(data):
    if isinstance(data,list):
        return random.sample(data,1)[0]["metadata"]["name"]
    else:
        return data["metadata"]["name"]

# 获取APP服务的 deployment或者 statefulset的 信息，用于升级
def get_deploy_info(data):
    if isinstance(data,list):
        if len(data) == 0:
            return {}
        else:
            k8s_data = data[0]
    else:
        k8s_data = data

    deploy_info = {}
    if k8s_data["kind"] == "Deployment":
        deploy_info["replicas"] = k8s_data["spec"]["replicas"]

    nodeSelector = k8s_data["spec"]["template"]["spec"]["nodeSelector"]
    for key,value in nodeSelector.items():
        if value == "true":
            deploy_info["nodelabel"] = key
            break

    return deploy_info

def signApiAuth(pbeconfig, reqPath):
    ts = str(int(time.time() * 1000))
    nonce = str(uuid.uuid4())

    appid = "java"
    appKey = hashlib.md5((appid+pbeconfig).encode('utf-8')).hexdigest()

    toSign = appKey + ts + nonce + reqPath
    sign = hashlib.sha1(toSign.encode('utf-8')).hexdigest()

    return "{appid}:{ts}:{nonce}:{sign}".format(appid=appid,ts=ts,nonce=nonce,sign=sign)


def sortRoles(install_roles, sortedRoles):
    results = []
    for role in sortedRoles:
        if role in install_roles:
            results.append(role)

    return results

# 对ansible自带的combine包装一下，避免playbook里太长
def titan_combine(*terms):
    return combine(terms, recursive=True, list_merge='append_rp')

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
          'ensureMapString': ensureMapString,
          'from_properties': from_properties,
          'get_one_pod': get_one_pod,
          'signApiAuth': signApiAuth,
          'get_deploy_info': get_deploy_info,
          'sortRoles': sortRoles,
          'titan_combine': titan_combine
        }