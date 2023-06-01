pragma solidity ^0.8.10;

interface IStablePool {
    function getSwapFeePercentage() external view returns (uint256);
    function getAmplificationParameter() external view returns (uint256, bool, uint256);
    function getLastInvariant() external view returns (uint256, uint256);
}
