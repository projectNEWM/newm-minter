import binascii
import hashlib


def token_name(txHash: str, index: int, prefix: str) -> str:
    """
    Generates a token name based on the transaction hash, index, and prefix.
    This function follows the assist library's unique_token_name function.

    Args:
        txHash (str): Transaction hash
        index (int): Transaction Index
        prefix (str): cip68 standard prefix

    Returns:
        str: The token name.

    Examples:
        >>> token_name("1FA3625AC5DABFBEDFD80EEDFB5BEA37D8E8D66362C22300C2E4C00951449B18", 0, "000643b0")
        '000643b000a6bf2d5e45c1b7c91e6f0028c0af7ecedd131367e06d923e7d2819'

        >>> token_name("1FA3625AC5DABFBEDFD80EEDFB5BEA37D8E8D66362C22300C2E4C00951449B18", 24, "001bc280")
        '001bc28018a6bf2d5e45c1b7c91e6f0028c0af7ecedd131367e06d923e7d2819'

        >>> token_name("AB69AAB2EFE96149CA2FC045F8CDFADAA2213E5F71F7F427632AC1216BD6106D", 0, "000643b0")
        '000643b00001f1ca8bb6ed0bd798019448bf8b5b9a539958477b53fd86c6d27e'
    """
    txBytes = binascii.unhexlify(txHash)
    h = hashlib.new('sha3_256')
    h.update(txBytes)
    txHash = h.hexdigest()
    x = hex(index)[-2:]
    if "x" in x:
        x = x.replace("x", "0")
    txHash = prefix + x + txHash
    return txHash[0:64]


if __name__ == "__main__":
    import doctest
    doctest.testmod()
