import requests
import sys
import codecs
from eth_abi import encode

API_URL = "https://li.quest/v1/quote"


def get_quote(
    srcToken,
    dstToken,
    amount,
    fromAddress
):
    queryParams = {
        "fromChain": 1,
        "toChain": 1,
        "fromToken": srcToken,
        "toToken": dstToken,
        "fromAmount": amount,
        "fromAddress": fromAddress
    }

    resp = requests.get(API_URL, params=queryParams)
    if resp.status_code != 200:
        raise Exception(format(f"{resp.text}, code: {resp.status_code}"))
    
    resp = resp.json()

    data = encode(
        ["uint256", "bytes"], [int(resp["estimate"]["toAmount"]), codecs.decode(
            resp['transactionRequest']['data'][2:], 'hex_codec')]
    ).hex()
    
    print("0x" + str(data))


def main():
    args = sys.argv[1:]
    return get_quote(*args)


__name__ == "__main__" and main()
