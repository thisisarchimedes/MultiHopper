import requests
import sys
import codecs
from eth_abi import encode
from web3 import Web3


def get_quote(
    api_url,
):
    provider = Web3.HTTPProvider(api_url)
    w3 = Web3(provider)
    block_number = w3.eth.block_number
    data = encode(
        ["uint256"], [block_number]
    ).hex()
    print("0x" + str(data))


def main():
    args = sys.argv[1:]
    return get_quote(*args)


__name__ == "__main__" and main()