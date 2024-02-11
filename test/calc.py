import math
import sys
from eth_abi import encode


def tick_to_price(tick):
    return 1.0001**tick


def price_to_tick(p):
    return math.floor(math.log(p, 1.0001))


def price_in_token1(tick, token0_decimals, token1_decimals):
    return tick_to_price(tick) * (10**-token1_decimals) / (10**-token0_decimals)


def price_in_token0(tick, token0_decimals, token1_decimals):
    return 1 / price_in_token1(tick, token0_decimals, token1_decimals)


def get_liquidity_0(x, sa, sb):
    if sa > sb:
        sa, sb = sb, sa
    return x * sa * sb / (sb - sa)


def get_liquidity_1(y, sa, sb):
    if sa > sb:
        sa, sb = sb, sa
    return y / (sb - sa)


def calc_amount0(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return liq * (pb - pa) / pb / pa


def calc_amount1(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return liq * (pb - pa)


def get_liquidity(x, y, sp, sa, sb):
    if sa > sb:
        sa, sb = sb, sa
    if sp <= sa:
        liquidity = get_liquidity_0(x, sa, sb)
    elif sp < sb:
        liquidity0 = get_liquidity_0(x, sp, sb)
        liquidity1 = get_liquidity_1(y, sa, sp)
        liquidity = min(liquidity0, liquidity1)
    else:
        liquidity = get_liquidity_1(y, sa, sb)
    return liquidity


# def find_amount_to_sell(
#     amount, lower_tick, higher_tick, current_tick, isToken0, search_step=0.0001
# ):
#     amount = amount * price_in_token1(current_tick) if isToken0 else amount
#     amount_underlying = 0
#     sp = price_in_token1(current_tick) ** 0.5
#     sa = price_in_token1(lower_tick) ** 0.5
#     sb = price_in_token1(higher_tick) ** 0.5

#     print("price_in_token0", price_in_token0(current_tick))
#     print("price_in_token1", price_in_token1(current_tick))
#     liqs = []
#     amounts_underlying = []
#     amounts_value = []
#     while True:
#         amount_underlying += search_step
#         liq = get_liquidity_1(amount_underlying, sa, sp)
#         amount0 = calc_amount0(liq, sb, sp)
#         if amount_underlying + (price_in_token1(current_tick) * amount0) < amount:
#             liqs.append(liq)
#             amounts_underlying.append(amount_underlying)
#             amounts_value.append(amount0)
#         if amount_underlying >= amount:
#             break
#     m, i = max((v, i) for i, v in enumerate(liqs))
#     return (
#         amounts_underlying[i] * price_in_token0(current_tick)
#         if isToken0
#         else amounts_value[i] * price_in_token1(current_tick)
#     )


# amount_to_sell = find_amount_to_sell(50, 256800, 261960, 259661, True)
# print("amount to sell",amount_to_sell)
# print("amount to sell in token0",price_in_token0(259661) * amount_to_sell)
# inBTC = 50 - amount_to_sell
# print("inBTC",inBTC)


### 50 wbtc with usdc
upper_band = price_to_tick(50054.085)
lower_band = price_to_tick(40089.531)
current_tick = price_to_tick(47093.30)

# amount_to_sell = find_amount_to_sell(50, lower_band, upper_band, current_tick, True,1)
# print("amount to sell",amount_to_sell)
# amount_to_provide = 50 - amount_to_sell
# print("amount to provide",amount_to_provide)


def find_amount_to_sell_with_formula(
    amount,
    lower_tick,
    upper_tick,
    current_tick,
    isToken0,
    token0_decimals,
    token1_decimals,
):
    ## be sure that all the variables are int except isToken0
    (amount, lower_tick, upper_tick, current_tick, token0_decimals, token1_decimals) = (
        int(amount),
        int(lower_tick),
        int(upper_tick),
        int(current_tick),
        int(token0_decimals),
        int(token1_decimals),
    )

    amount = (
        amount / (10**token0_decimals) if isToken0 else amount / (10**token1_decimals)
    )
    amount = (
        amount * price_in_token1(current_tick, token0_decimals, token1_decimals)
        if isToken0
        else amount
    )
    liq = get_liquidity_1(
        1,
        price_in_token1(lower_tick, token0_decimals, token1_decimals) ** 0.5,
        price_in_token1(current_tick, token0_decimals, token1_decimals) ** 0.5,
    )
    amount0 = calc_amount0(
        liq,
        price_in_token1(upper_tick, token0_decimals, token1_decimals) ** 0.5,
        price_in_token1(current_tick, token0_decimals, token1_decimals) ** 0.5,
    )
    ratio = price_in_token1(current_tick, token0_decimals, token1_decimals) * amount0

    result = (
        int(
            (
                (amount / (1 + ratio))
                * price_in_token0(current_tick, token0_decimals, token1_decimals)
            )
            * 10**token0_decimals
        )
        if isToken0
        else int((amount - (amount / (1 + ratio))) * 10**token1_decimals)
    )
    encodeTypes = ["uint256"]
    encodeData = [result]
    result = "0x" + encode(encodeTypes, encodeData).hex()
    print(result)


def main():
    args = sys.argv[1:]
    return find_amount_to_sell_with_formula(*args)


__name__ == "__main__" and main()
