import requests
import sys
import codecs
import time
from eth_abi import encode

API_URL = "https://partner-archimedes.li.quest/v1/quote"
MAX_RETRIES = 5


def get_quote(
    srcToken,
    dstToken,
    amount,
    fromAddress,
    returnToAmountMin=False,
):
    queryParams = {
        "integrator": "archimedes",
        "fromChain": 1,
        "toChain": 1,
        "fromToken": srcToken,
        "toToken": dstToken,
        "fromAmount": amount,
        "fromAddress": fromAddress,
        "slippage": 0.99
    }

    for retry in range(MAX_RETRIES):
        resp = requests.get(API_URL, params=queryParams)

        # Check if the status code is 200 (OK)
        if resp.status_code == 200:
            # Request was successful, break the loop
            break
        elif resp.status_code == 429:
            # Status code 429 (Too Many Requests), retry after a delay
            time.sleep(int(resp.headers.get('Retry-After', '5')))
        else:
            # Handle other status codes as needed
            time.sleep(5)  # Wait for a few seconds before retrying

        if retry == MAX_RETRIES - 1:
            raise Exception(
                format(f"Max retries reached. {resp.text}, code: {resp.status_code}"))

    resp = resp.json()

    encodeTypes = ["uint256"]
    encodeData = [int(resp["estimate"]["toAmount"])]

    if returnToAmountMin != False:
        encodeTypes.append("uint256")
        encodeData.append(int(resp["estimate"]["toAmountMin"]))

    encodeTypes.append("bytes")
    encodeData.append(codecs.decode(
        resp['transactionRequest']['data'][2:], 'hex_codec'))


def main():
    args = sys.argv[1:]
    return get_quote(*args)


__name__ == "__main__" and main()
