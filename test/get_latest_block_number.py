import sys
# from eth_abi import encode
# import eth_abi
from web3 import Web3


def get_current_block_number(
    api_url,
):
    provider = Web3.HTTPProvider(api_url)
    w3 = Web3(provider)
    block_number = w3.eth.block_number
    # data = eth_abi.encoding.BaseEncoder(
    #    ["uint256"], [block_number]
    # ).hex()
    data = block_number
    print("0x" + str(data))
    return data


def main():
    args = sys.argv[1:]
    return get_current_block_number(*args)


__name__ == "__main__" and main()
