pragma solidity ^0.8.10;

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "src/AuraWeightedPoolAdapter.sol";
import { AuraStablePoolAdapter } from "src/AuraStablePoolAdapter.sol";

contract MultiPoolStrategyFactory is Ownable {
    using Clones for address;

    address public convexAdapterImplementation;
    address public auraWeightedAdapterImplementation;
    address public auraStableAdapterImplementation;
    address public multiPoolStrategyImplementation;
    address public monitor;

    constructor(address _monitor) Ownable() {
        convexAdapterImplementation = address(new ConvexPoolAdapter());
        multiPoolStrategyImplementation = address(new MultiPoolStrategy());
        auraWeightedAdapterImplementation = address(new AuraWeightedPoolAdapter());
        auraStableAdapterImplementation = address(new AuraStablePoolAdapter());
        monitor = _monitor;
    }

    function createConvexAdapter(
        address _curvePool,
        address _multiPoolStrategy,
        uint256 _convexPid,
        uint256 _tokensLength,
        address _zapper,
        bool _isMetaPool,
        bool _useEth,
        bool _indexUint
    )
        external
        onlyOwner
        returns (address convexAdapter)
    {
        convexAdapter = convexAdapterImplementation.cloneDeterministic(
            keccak256(
                abi.encodePacked(
                    _curvePool, _multiPoolStrategy, _convexPid, _tokensLength, _zapper, _isMetaPool, _useEth, _indexUint
                )
            )
        );
        ConvexPoolAdapter(payable(convexAdapter)).initialize(
            _curvePool, _multiPoolStrategy, _convexPid, _tokensLength, _zapper, _isMetaPool, _useEth, _indexUint
        );
    }

    function createAuraWeightedPoolAdapter(
        bytes32 _poolId,
        address _multiPoolStrategy,
        uint256 _auraPid
    )
        external
        onlyOwner
        returns (address auraAdapter)
    {
        auraAdapter = auraWeightedAdapterImplementation.cloneDeterministic(
            keccak256(abi.encodePacked(_poolId, _multiPoolStrategy, _auraPid))
        );
        AuraWeightedPoolAdapter(payable(auraAdapter)).initialize(_poolId, _multiPoolStrategy, _auraPid);
    }

    function createAuraStablePoolAdapter(
        bytes32 _poolId,
        address _multiPoolStrategy,
        uint256 _auraPid
    )
        external
        onlyOwner
        returns (address auraAdapter)
    {
        auraAdapter = auraStableAdapterImplementation.cloneDeterministic(
            keccak256(abi.encodePacked(_poolId, _multiPoolStrategy, _auraPid))
        );
        AuraStablePoolAdapter(payable(auraAdapter)).initialize(_poolId, _multiPoolStrategy, _auraPid);
    }

    function createMultiPoolStrategy(
        address _underlyingToken,
        string calldata _strategyName
    )
        external
        onlyOwner
        returns (address multiPoolStrategy)
    {
        multiPoolStrategy = multiPoolStrategyImplementation.cloneDeterministic(
            keccak256(abi.encodePacked(_underlyingToken, monitor, _strategyName))
        );
        MultiPoolStrategy(multiPoolStrategy).initalize(_underlyingToken, monitor);
        MultiPoolStrategy(multiPoolStrategy).transferOwnership(msg.sender);
    }
}