pragma solidity ^0.4.20;
import "./Exoswaplab.sol";


contract LabInterface {
    address[] public tokenList;
    mapping(address => address) tokenToDex;
    mapping(address => address) DexToToken;
    function launchDex(address _token) public returns (address Dex);
    function getDexCount() public view returns (uint DexCount);
    function tokenToDexLookup(address _token) public view returns (address Dex);
    function DexToTokenLookup(address _Dex) public view returns (address token);
    event DexLaunch(address indexed Dex, address indexed token);
}


contract Exoswaplab is LabInterface {
    event DexLaunch(address indexed Dex, address indexed token);

    // index of tokens with registered Dexs
    address[] public tokenList;
    mapping(address => address) tokenToDex;
    mapping(address => address) DexToToken;

    function launchDex(address _token) public returns (address Dex) {
        require(tokenToDex[_token] == address(0));             //There can only be one Dex per token
        require(_token != address(0) && _token != address(this));
        ExoswapDex newDex = new ExoswapDex(_token);
        tokenList.push(_token);
        tokenToDex[_token] = newDex;
        DexToToken[newDex] = _token;
        DexLaunch(newDex, _token);
        return newDex;
    }

    function getDexCount() public view returns (uint DexCount) {
        return tokenList.length;
    }

    function tokenToDexLookup(address _token) public view returns (address Dex) {
        return tokenToDex[_token];
    }

    function DexToTokenLookup(address _Dex) public view returns (address token) {
        return DexToToken[_Dex];
    }
}
