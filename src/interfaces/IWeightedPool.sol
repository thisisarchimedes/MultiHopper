pragma solidity ^0.8.19.0;

interface IWeightedPool {
    function getNormalizedWeights() external view returns (uint256[] memory);
    function getSwapFeePercentage() external view returns (uint256);
}
