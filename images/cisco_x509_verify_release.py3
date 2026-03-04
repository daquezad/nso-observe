#!/usr/bin/env python3
# Author: sto-image-signing-dev@cisco.com
#
# Copyright (c) 2015-2024 by cisco Systems, Inc.
# All rights reserved.
#---------------------------------------------------------------------------

# This script is used to verify three tier certificate
# chain and verify file signature using openssl.

import sys
import os
import argparse
import urllib.request, urllib.parse, urllib.error
import hashlib
import shutil
import subprocess
import tempfile
import ssl

# see https://stackoverflow.com/questions/2970608/what-are-named-tuples-in-python
from collections import namedtuple

#constants
PROG_NAME = "cisco_x509_verify_release.py3"

#menu constants
MENU_MAIN_DESC = "Image signing application. This will verify the certificate chain"\
                 " and image signature using openssl commands."
CISCO_X509_VERIFY_REL_VERSION = "PY3.2.1"

#color constants
RED = '\033[31m'
YELLOW = '\033[33m'
OKMAGENTA = '\033[35m'
OKGREEN = '\033[32m'
OKBLUE = '\033[34m'
OKCYAN = '\033[36m'
OKWHITE = '\033[97m'

ENDC = '\033[0m'
BOLD = '\033[1m'
UNDERLINE = '\033[4m'

FAIL    = RED    + ' ' + BOLD       #red
WARNING = YELLOW + ' ' + BOLD       #orange
DEBUGCOLOR = OKMAGENTA + ' ' + BOLD

CiscoCA = namedtuple('CiscoCA', 'caFile, caURL, caSha256')
CAchain = namedtuple('CAchain', 'rootCA, subCA')

CiscoCAdict = {
  "genrsa4k"   : CAchain(
                   CiscoCA("csirca4096.cer",
                           "https://www.cisco.com/security/pki/certs/csirca4096.cer",
                           "6b3d4e1b5e26318c0bb6a22fb1206d287fa3fb0c5fe34eebbf8613954f8a64a7"),
                   CiscoCA("cgsisca4096.cer",
                           "https://www.cisco.com/security/pki/certs/cgsisca4096.cer",
                           "18ab04890d899aed16494b2f8f77b021ef9deb0dc3afa03bfa0fc39935ee6050")
                 ),
  #"genecc384"  : CAchain(
  #                 CiscoCA("csircap384.cer",
  #                         "https://www.cisco.com/security/pki/certs/csircap384.cer",
  #                         "9d29415c51d88909fcf084e5e81c4ec9422d7ae9df490218f8f99fbf9eb1f1c3"),
  #                 CiscoCA("cgsiscap384.cer",
  #                         "https://www.cisco.com/security/pki/certs/cgsiscap384.cer",
  #                         "7af09b1b8417130027ef00e8fff483aa26b0f35dd1e95f84a4a7231955a85383")
  #               ),
  "innerspace" : CAchain(
                   CiscoCA("crcam2.cer",
                           "https://www.cisco.com/security/pki/certs/crcam2.cer",
                           "cd85167b3935e27bcc3b0f5fa24c8457882d0bb994f88269a7f72829d957eae9"),
                   CiscoCA("innerspace.cer",
                           "https://www.cisco.com/security/pki/certs/innerspace.cer",
                           "f31e6b39dae6996fdf2045a61be8bd3688a86dfd06c46ce71af4af239f411c56")
                 ),
  "xrcontainer": CAchain(
                   CiscoCA("crrca.cer",
                           "https://www.cisco.com/security/pki/certs/crrca.cer",
                           "1997ba40d0d6fafb672c67d5200d0c0846b540d1e431634c2a8923508b2974c0"),
                   CiscoCA("xrcrrsca.cer",
                           "https://www.cisco.com/security/pki/certs/xrcrrsca.cer",
                           "c86f7c94650ba37ac0f0a31fe132f375447d90a5319f455298b5620142a1da3e")
                 ),
  "vuefi2"     : CAchain(
                   CiscoCA("vuefirca.cer",
                           "https://www.cisco.com/security/pki/certs/vuefirca.cer",
                           "67501b730fe840f05cba7a84cfd26e0f11311e5f9b16ce60004fd97d3f55de4c"),
                   CiscoCA("vuefiscav2.cer",
                           "https://www.cisco.com/security/pki/certs/vuefiscav2.cer",
                           "4f5d920ed0f53651f68789534dc190fe964dd174ff251381b207a129b82d84c0")
                 ),
  "vuefi3"     : CAchain(
                   CiscoCA("vuefircav2.cer",
                           "https://www.cisco.com/security/pki/certs/vuefircav2.cer",
                           "2ac955a3491310b2b6f12e75ee52fa5d24bc15c3be6d735b8e664f14b21150e4"),
                   CiscoCA("vuefiscav3.cer",
                           "https://www.cisco.com/security/pki/certs/vuefiscav3.cer",
                           "6bb16e4b6dffab3a789ec427250ca313f58d5f16da9c4771c9ab6913e4c18e9e")
                 )
}

failExpiredCerts = False


"""
LOG() function prints string in requested color on terminal
"""
def LOG(color, string):
    if(sys.platform.find("linux") == -1):
        if(color == FAIL):
            print("Error Log: " + string)
        else:
            print(string)
    else:
        if(color == FAIL):
            print((color + "Error log: " + string + ENDC))
        else:
            print((color + string + ENDC))


"""
execute_command(cmd) function executes the shell command and returns
status and output.
"""
def execute_command(cmd):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=False, universal_newlines=True)
    out,_ = p.communicate()
    status = p.returncode
    return status, out


"""
cleanup() function deletes temp directory and its contents.
"""
def cleanup(tempDir):
    if(tempDir != None) and os.path.exists(tempDir):
        shutil.rmtree(tempDir)

"""
verify_cert_sha256() function computes the sha256sum of certificate
and compares with the expected value.
"""
def verify_cert_sha256(cert_name, expected_sha256):
    cert_sha256 = hashlib.sha256(open(cert_name, 'rb').read()).hexdigest()
    if(cert_sha256 == expected_sha256):
        return 0
    else:
        LOG(FAIL, "Computed sha256sum of "+cert_name+" = "+cert_sha256)
        LOG(FAIL, "Expected sha256sum of "+cert_name+" = "+expected_sha256)
        return 1


"""
convert_cert_to_pem() function converts DER formatted cert
to PEM format. This overwrites the passed-in DER cert.
"""
def convert_cert_to_pem(cert_name):
    with open(cert_name, 'r', 1, 'us-ascii', 'ignore') as f:
        first_line = f.readline()
        if(first_line.find("-----BEGIN CERTIFICATE-----") == -1):
            cmd = ['openssl', 'x509', '-inform', 'der', '-in', cert_name, '-out',  cert_name]
            status, out = execute_command(cmd)
            if(out.find("error") != -1):
                LOG(FAIL, "Failed to convert "+cert_name+"from DER to PEM.")
                LOG(FAIL, out)
                return False

    return True


"""
check_cert_expiration() function
 returns True  if a cert expiration is not checked or will not expire in the next second.
 returns False if a cert expiration is checked and WILL     expire in the next second.
 Also logs a warning msg if cert expiration will happen in the next 180 days (6 months).
"""
def check_cert_expiration(cert_name, failExpired):
    printed_name = cert_name.split('/')[-1]
    cmd = ['openssl', 'x509', '-enddate', '-in', cert_name, '-noout']
    status, out = execute_command(cmd)
    end_date = out[9::]
    if (failExpired):
        LOG(OKBLUE,printed_name+" expiration date is "+end_date)

    cmd = ['openssl', 'x509', '-checkend', '1', '-in', cert_name, '-noout']
    status, out = execute_command(cmd)
    if(status != 0):
        LOG(FAIL, printed_name+" expired on "+end_date)
        if (failExpired):
            return False
    else:
        SIX_MONTHS = 15552000
        cmd = ['openssl', 'x509', '-checkend', str(SIX_MONTHS), '-in', cert_name, '-noout']
        status, out = execute_command(cmd)
        if(status != 0):
            LOG(WARNING, "WARNING: "+printed_name+" expires on "+end_date)

    return True

"""
download_cert() function takes in needs_openssl_conf flag as argument.
it creates python script file that attempts to download a file (cert) from given URL
it creates a custom openssl config if needs_openssl_conf is set
"""
def download_cert(cname, needs_openssl_conf, cert_py_name="", openssl_conf_name=""):
    OPENSSL_FILE = '''
    openssl_conf = openssl_init

    [openssl_init]
    ssl_conf = ssl_sect

    [ssl_sect]
    system_default = system_default_sect

    [system_default_sect]
    Options = UnsafeLegacyRenegotiation
    '''

    DOWNLOAD_CERT = '''
import sys

def retrieve_url(cname, cert_url):
    try:
        #print("cname = "+cname)
        import urllib.request
        urllib.request.urlretrieve(cert_url, cname)
        return cname
    except Exception as e:
        print(str(e))
        with open("error_cert_download.txt", "w") as err_file:
            err_file.write("1")
        return ""

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cname = retrieve_url(sys.argv[1], sys.argv[2])
        #if (cname != ""):
        #    print("Success in downloading " + sys.argv[2] + " to " + cname)
        #else:
        #    print("Exception during cert download.")
    else:
        print("use retrieve_url(cname, cert_url)")
    '''

    if needs_openssl_conf:
        LOG(OKGREEN, "Creating custom openssl file.")
        with open(openssl_conf_name, "w") as ssl_file:
            ssl_file.write(OPENSSL_FILE)

    with open(cert_py_name, "w") as file:
        file.write(DOWNLOAD_CERT)

"""
check_download_cert() function takes in cert_url to download cert.
attempts to download cert and if unsuccessful, retries download with custom openssl file
this is to deal with newer servers with an ssl library that considers Cisco's corporate
servers as negotiating with unsafe ciphers.
"""
def check_download_cert(cert_url, tempDirName):
    cert_name = tempDirName+"/"+cert_url.split('/')[-1]
    import random
    import string
    cert_suffix = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(0,6))
    cert_py = "cert_" + cert_suffix + ".py"
    download_cert(cname=cert_name, needs_openssl_conf=False, cert_py_name=cert_py, openssl_conf_name="")

    openssl_suffix = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(0,6))
    openssl_conf_script = "openssl_" + openssl_suffix + ".conf"
    
    try:
        subprocess.check_call([sys.executable, cert_py, cert_name, cert_url])
    except ssl.SSLError as e:
        LOG(RED, str(e))
        LOG(RED, "SSL error in subprocess")
    except subprocess.CalledProcessError:
        LOG(RED, "CalledProcessError")
    except Exception as e1:
        LOG(RED, "Unknown exception")
        print(str(e1))

    if os.path.exists("error_cert_download.txt"):
        LOG(OKGREEN, "Trying download with openssl file.")
        download_cert(cname=cert_name, needs_openssl_conf=True, cert_py_name=cert_py, openssl_conf_name=openssl_conf_script)
        try:
            os.environ["OPENSSL_CONF"] = openssl_conf_script
            subprocess.check_call([sys.executable, cert_py, cert_name, cert_url])
        except ssl.SSLError as e:
            LOG(RED, str(e))
            LOG(FAIL, "SSL error in subprocess... exiting")
        except subprocess.CalledProcessError as e1:
            LOG(RED, str(e1))
            LOG(FAIL, "Failed to download cert from " + cert_url)
            return "N/A"
        except Exception as e1:
            LOG(RED, str(e1))
            LOG(FAIL, "Unknown error in download cert from " + cert_url)
            return "N/A"
    LOG(OKGREEN, "Success in downloading " + cert_url)
    os.remove(cert_py)
    if os.path.exists("error_cert_download.txt"):
        os.remove("error_cert_download.txt")
    if os.path.exists(openssl_conf_script):
        os.remove(openssl_conf_script)
    return cert_name

"""
create_temp_cert() copies srcCert to tempDir
"""
def create_temp_cert(srcCert, tempDir):
    tempCert = tempDir+"/"+os.path.basename(srcCert)
    shutil.copyfile(srcCert, tempCert)
    return tempCert, 0


"""
pemifyAndCheckDates() does the following:
 - converts the provided cert to PEM format if needed
 - validates that the cert has not expired
 - returns -1 if error, otherwise 0
"""
def pemifyAndCheckDates(cert, failExpiredCert):
    status = -1
    if (convert_cert_to_pem(cert) == False):
        LOG(FAIL, "convert_cert_to_pem failed.")
        return -1
    elif (check_cert_expiration(cert, failExpiredCert) == False):
        LOG(FAIL, "check_cert_expiration failed.")
        return -1

    return 0


"""
verify_3tier_cert_chain() function verifies the 3-tier PEM cert chain.
returns 0 if successful
"""
def verify_3tier_cert_chain(rootca, subca, ee_cert):
    status = 0

    #verify root and subca certificate
    cmd = ['openssl', 'verify', '-CAfile', rootca, subca]
    status, out = execute_command(cmd)

    if(out.find("error") != -1 or status != 0):
        LOG(FAIL, "Verification of root and subca certificate failed.")
        LOG(FAIL, out)
        return -1

    #verify end-entity certificate
    cmd = ['openssl', 'verify', '-CAfile', rootca, '-untrusted', subca, ee_cert]
    status, out = execute_command(cmd)

    if(out.find("error") != -1 or status != 0):
        LOG(FAIL, "Failed to verify root, subca and end-entity certificate chain.")
        LOG(FAIL, out)
        return -1
    else:
        LOG(OKGREEN, "Successfully verified root, subca and end-entity certificate chain.")
        return status


"""
fetch_pubkey_from_cert() function retrieves public key from x509
PEM certificate.
"""
def fetch_pubkey_from_cert(printed_cert_name, tempDir, cert_name):
    tempKey = tempDir+"/ee_pubkey.pem"
    cmd = ['openssl', 'x509', '-pubkey', '-noout', '-in', cert_name]
    f = open(tempKey, "w")
    p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.PIPE, shell=False, universal_newlines=True)
    _,err = p.communicate()
    status = p.returncode
    f.close()

    if(status != 0):
        LOG(FAIL, "Failed to fetch a public key from "+printed_cert_name)
        LOG(FAIL, err)
        tempKey = ""
    else:
        LOG(OKGREEN, "Successfully fetched a public key from "+printed_cert_name)
    
    return tempKey


"""
verify_dgst_signature(args, pemKey) function verifies the signature of an image.
ref: https://docs.openssl.org/3.0/man1/openssl-dgst/
"""
def verify_dgst_signature(args, pemKey):
    sha_version = "-" + args.dgst_algo

    cmd = ['openssl', 'dgst', sha_version, '-verify', pemKey, '-signature', args.signature, args.image_name]
    status, out = execute_command(cmd)

    if(status != 0):
        LOG(FAIL, "Failed to verify dgst signature of "+args.image_name+".")
        LOG(FAIL, out)
    
    return status


"""
verify_smime_signature() function verifies the openssl smime signature of an image.
"""
def verify_smime_signature(args, ee_cert):
    cmd = ['openssl', 'smime', '-verify', '-binary', '-in', args.signature, '-inform', args.sig_type, '-content', args.image_name, '-noverify', '-nointern', '-certfile', ee_cert, '-out', '/dev/null']
    status, out = execute_command(cmd)

    if(status != 0):
        LOG(FAIL, "Failed to verify smime signature of "+args.image_name+".")
        LOG(FAIL, out)
    
    return status


"""
verify_signature() function verifies the image signature using either smime or dgst
openssl command.
"""
def verify_signature(args, tempDir, ee_cert):
    if(args.verify_type == "smime"):
        status = verify_smime_signature(args, ee_cert)
    else:
        pemKey = fetch_pubkey_from_cert(args.ee_cert, tempDir, ee_cert)
        if(pemKey == ""):
            return 1
        status = verify_dgst_signature(args, pemKey)
    return status

"""
remove_prefix() returns the string after 'prefix',
or if 'prefix' is not found, then an empty string
Note that the built-in "removeprefix()" is only available in
Python 3.9+.  We shouldn't risk errors when encountering Python 3.8- customers.
"""
def remove_prefix(text, prefix):
    if text.startswith(prefix):
        return text[len(prefix):]
    return ""

"""
identify_chain() function identifies which CA chain in CiscoCAdict
should be used.

It first tries to deduce the chain based on information in the 
PEM-formatted end-entity certifcate.  The chain is identified by matching
against the issuing CA which is assumed to be one of the subCAs in
CiscoCAdict.  An end entity signed by a subCA is assumed to have
an issuing CA URL or a certificate revocation list (CRL) URL.

First the function tries finding the issuing CA URL. Issuing CA URLs
are typically http while our URLs are https, so we strip the prefix
prior to searching.

Failing that search, we search for the subCA filename minus suffix,
since that part of the file name is usually in the CRL URL.

Failing the second search, we set the chain based on CLI parameters.
"""
def identify_chain(args, eecert):
    cmd = ['openssl', 'x509', '-noout', '-text', '-in', eecert]
    status, certDump = execute_command(cmd)
    #LOG(OKBLUE, "PRINTING cert dump")
    #LOG(OKBLUE, "")
    #LOG(OKBLUE, certDump)
    #LOG(OKBLUE, "")
    #LOG(OKBLUE, "DONE printing cert dump")

    for key in CiscoCAdict:
        subcaUrl = CiscoCAdict[key].subCA.caURL
        urlNoPrefix = remove_prefix(subcaUrl, "https:")
        if (certDump.find(urlNoPrefix) != -1):
            LOG(OKGREEN, "CA chain "+key+" chosen based on finding '"+urlNoPrefix+"' string in eecert")
            return key
        else:
            subcaFile = CiscoCAdict[key].subCA.caFile
            fileNoSuffix, blank = subcaFile.split(".cer")
            if (certDump.find(fileNoSuffix) != -1):
                LOG(OKGREEN, "CA chain "+key+" chosen based on finding '"+fileNoSuffix+"' string in eecert")
                return key

    # if we got here, we were unable to identify CA chain by
    # subCA string search, so select based on CLI parameters.
    #
    if (args.virtual):
        LOG(OKGREEN, "CA chain 'vuefi2' chosen based on 'virtual' CLI argument")
        return "vuefi2"
    elif (args.container and (args.container == 'xr')):
        LOG(OKGREEN, "CA chain 'xrcont' chosen based on 'container=xr' CLI argument")
        return "xrcont"

    #default setting
    LOG(OKGREEN, "CA chain 'innerspace' chosen by default")
    return "innerspace"



"""
command_handler() is a handler function 
"""
def command_handler(args):
    rootca_cert = ""
    rootca_hash = ""
    subca_cert = ""
    subca_hash = ""
    ee_cert = ""
    l_rootca_cert = ""
    l_subca_cert = ""
    status = 0

    # create a temp dir
    tempCertDir = tempfile.mkdtemp();

    # create ee_cert which is a copy of args.ee_cert
    ee_cert, status =  create_temp_cert(args.ee_cert, tempCertDir)
    if (status != 0):
        LOG(FAIL, "Failed to create temp ee_cert file")

    if (status == 0):
        # make sure ee_cert is PEM format and any necessary expiration check is handled
        status =  pemifyAndCheckDates(ee_cert, args.failExpiredCerts)
        if (status != 0):
            LOG(FAIL, "Failed to pemifyAndCheckDates "+ee_cert)
        else:
            # identify the CA chain to use
            caDictKey = identify_chain(args, ee_cert)
            rootca_hash = CiscoCAdict[caDictKey].rootCA.caSha256
            subca_hash  = CiscoCAdict[caDictKey].subCA.caSha256
            LOG(OKGREEN, "Using cert chain '"+caDictKey+"' ("+CiscoCAdict[caDictKey].rootCA.caFile+" and "+CiscoCAdict[caDictKey].subCA.caFile+")")

    if (status == 0):
        # Download rootCA certificate or use local cache
        if(args.cert_dir != None):
            l_rootca_cert = args.cert_dir+"/"+CiscoCAdict[caDictKey].rootCA.caFile
            status = verify_cert_sha256(l_rootca_cert, rootca_hash)
            if (status == 0):
                LOG(OKGREEN, "Using locally-provided rootCA certificate "+l_rootca_cert)
                rootca_cert, status =  create_temp_cert(l_rootca_cert, tempCertDir)
                if (status != 0):
                    LOG(FAIL, "Failed to create temp rootca_cert file")

        else:
            LOG(OKGREEN, "Retrieving rootCA certificate from "+CiscoCAdict[caDictKey].rootCA.caURL+" ...")
            rootca_cert = check_download_cert(CiscoCAdict[caDictKey].rootCA.caURL, tempCertDir)
            if(rootca_cert == "N/A"):
                LOG(FAIL, "Failed to retrieve "+CiscoCAdict[caDictKey].rootCA.caURL+".")
                status = 1
            else:
                status = verify_cert_sha256(rootca_cert, rootca_hash)
                if (status == 0):
                    LOG(OKGREEN, "Using downloaded rootCA cert "+rootca_cert)

    if (status == 0):
        # Download subCA certificate or use local cache
        if(args.cert_dir != None):
            l_subca_cert = args.cert_dir+"/"+CiscoCAdict[caDictKey].subCA.caFile
            status = verify_cert_sha256(l_subca_cert, subca_hash)
            if (status == 0):
                LOG(OKGREEN, "Using locally-provided subCA certificate "+l_subca_cert)
                subca_cert, status =  create_temp_cert(l_subca_cert, tempCertDir)
                if (status != 0):
                    LOG(FAIL, "Failed to create temp subca_cert file")

        else:
            LOG(OKGREEN, "Retrieving subCA certificate from "+CiscoCAdict[caDictKey].subCA.caURL+" ...")
            subca_cert = check_download_cert(CiscoCAdict[caDictKey].subCA.caURL, tempCertDir)
            if(subca_cert == "N/A"):
                LOG(FAIL, "Failed to retrieve "+CiscoCAdict[caDictKey].subCA.caURL+".")
                status = 1
            else:
                status = verify_cert_sha256(subca_cert, subca_hash)
                if (status == 0):
                    LOG(OKGREEN, "Using downloaded subCA cert "+subca_cert)

    if (status == 0):
        # make sure rootca_cert is PEM format and any necessary expiration check is handled
        status =  pemifyAndCheckDates(rootca_cert, args.failExpiredCerts)
        if (status != 0):
            LOG(FAIL, "Failed to pemifyAndCheckDates "+rootca_cert)

    if (status == 0):
        # make sure subca_cert is PEM format and any necessary expiration check is handled
        status =  pemifyAndCheckDates(subca_cert, args.failExpiredCerts)
        if (status != 0):
            LOG(FAIL, "Failed to pemifyAndCheckDates "+subca_cert)

    if (status == 0):
        #verify 3 tier certificate signature chain
        status = verify_3tier_cert_chain(rootca_cert, subca_cert, ee_cert)

    if(status == 0):
        #verify signature
        status = verify_signature(args, tempCertDir, ee_cert)
        if(status == 0):
            LOG(OKGREEN, "Successfully verified the signature of "+args.image_name+" using "+args.ee_cert)
        else:
            LOG(FAIL, "FAILED to verify the signature of "+args.image_name+" using "+args.ee_cert)

    cleanup(tempCertDir)
    return status


"""
verify_parser_options() is used to verify input arguments.
It returns error if any required argument is missing.
"""
def verify_parser_options(args):
    if(args.image_name != None):
        if(not os.path.exists(args.image_name)):
            LOG(FAIL, "'"+args.image_name+"' does not exist")
            return 1
    if(args.signature != None):
        if(not os.path.exists(args.signature)):
            LOG(FAIL, "'"+args.signature+"' does not exist")
            return 1
    if(args.ee_cert != None):
        if(not os.path.exists(args.ee_cert)):
            LOG(FAIL, "'"+args.ee_cert+"' does not exist")
            return 1
    if(args.cert_dir != None):
        if(not os.path.exists(args.cert_dir)):
            LOG(FAIL, "'"+args.cert_dir+"' does not exist")
            return 1

    if(args.failExpiredCerts == True):
        global failExpiredCerts
        failExpiredCerts = True
        
    return 0


"""
arg_parser() is used to setup command line options.
"""
def arg_parser():
    #setup main parser
    pmain = argparse.ArgumentParser(prog=PROG_NAME, description=MENU_MAIN_DESC)
    
    #version argument
    pmain.add_argument("-V", "--version", action='version', version=CISCO_X509_VERIFY_REL_VERSION)

    #certificate argument
    pmain.add_argument("-e", "--ee_cert", metavar = "<ee_cert_name>", dest = "ee_cert", required = True, help = "Local path to End-entity certificate in PEM format")

    #signature file argument
    pmain.add_argument("-s", "--signature", metavar = "<signature_file>", dest = "signature", required = True, help = "Filename containing image signature")

    #input image argument
    pmain.add_argument("-i", "--image_name", metavar = "<image_name>", dest = "image_name", required = True, help = "Image name")
    
    #cert_dir argument
    pmain.add_argument("-c", "--cert_dir", metavar = "<cert_dir>", dest = "cert_dir", required = False, help = "directory to find local certs")

    #virtual cert chain
    pmain.add_argument("-root_type", "--virtual", dest = "virtual", required = False, help = "Using virtual cert chain (DEPRECATED: script now auto-detects rel chains)")

    #container cert chain
    pmain.add_argument("--container", choices = ['xr'], dest = "container", required = False, help = "Using container cert chain.  Ignored if virtual set (DEPRECATED: script now auto-detects rel chains)")

    #openssl verify type argument
    pmain.add_argument("-v", "--verify_type", choices = ['dgst', 'smime'], default = 'dgst', dest = "verify_type", required = False, help = "Verify type: dgst|smime")

    #openssl digest algorithm
    pmain.add_argument("--algo", choices = ['sha256', 'sha512'], default = 'sha512', dest = "dgst_algo", required = False, help = "algorithm (optional, used only for dgst, dflt is sha512)")

    #openssl verify type argument for SMIME only
    pmain.add_argument("--sig_type", choices = ['DER', 'PEM'], default = 'PEM', dest = "sig_type", required = False, help = "signature encoding (optional, used only for smime, dflt is PEM)")

    #option to skip cert expiration check
    pmain.add_argument("--failExpiredCerts", action = "store_true", dest = "failExpiredCerts", help = "Check certs for expiration")

    pmain.set_defaults(func=command_handler)

    return pmain


"""
main function for STO image signing script
to verify cert chain and bulk hash signatures.
"""
def main():
    #setup console menu parsers
    pmain = arg_parser()

    #parse args
    args = pmain.parse_args()

    #manually verify the input arguments
    if(verify_parser_options(args) != 0):
        return 1

    #invoke appropriate handler function
    status = args.func(args)

    return status


"""
Starting point
"""
if __name__ == "__main__":
    sys.exit(main())

