import base64
from Crypto.Cipher import AES
from Crypto.Util.py3compat import *
from hashlib import md5

class AESCipher:
    """
    Usage:
        c = AESCipher('password').encrypt('message')
        m = AESCipher('password').decrypt(c)
    """

    def __init__(self, key='ZStack open source'):
        self.key = md5(key).hexdigest()
        self.cipher = AES.new(self.key, AES.MODE_ECB)
        self.prefix = "crypt_key_for_v1::"
        self.BLOCK_SIZE = 16

    # PKCS#7
    def _pad(self, data_to_pad, block_size):
        padding_len = block_size - len(data_to_pad) % block_size
        padding = bchr(padding_len) * padding_len
        return data_to_pad + padding

    # PKCS#7
    def _unpad(self, padded_data, block_size):
        pdata_len = len(padded_data)
        if pdata_len % block_size:
            raise ValueError("Input data is not padded")
        padding_len = bord(padded_data[-1])
        if padding_len < 1 or padding_len > min(block_size, pdata_len):
            raise ValueError("Padding is incorrect.")
        if padded_data[-padding_len:] != bchr(padding_len) * padding_len:
            raise ValueError("PKCS#7 padding is incorrect.")
        return padded_data[:-padding_len]

    def encrypt(self, raw):
        raw = self._pad(self.prefix + raw, self.BLOCK_SIZE)
        return base64.b64encode(self.cipher.encrypt(raw))

    def decrypt(self, enc):
        denc = base64.b64decode(enc)
        ret = self._unpad(self.cipher.decrypt(denc), self.BLOCK_SIZE).decode('utf8')
        return ret[len(self.prefix):] if ret.startswith(self.prefix) else enc

    def is_encrypted(self, enc):
        try:
            raw = self.decrypt(enc)
            return raw != enc
        except:
            return False

c = str(sys.argv[1])
print AESCipher().decrypt(c)
