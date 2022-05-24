pragma solidity ^0.4.18;
import "./SafeMath.sol";
import "./BEP20Interface.sol";
import "./ExoswapLab.sol";


contract ExoswapDex {
    using SafeMath for uint256;

    /// EVENTS
    event bnbToTokenPurchase(address indexed buyer, uint256 indexed bnbIn, uint256 indexed tokensOut);
    event TokenTobnbPurchase(address indexed buyer, uint256 indexed tokensIn, uint256 indexed bnbOut);
    event Investment(address indexed liquidityProvider, uint256 indexed sharesPurchased);
    event Divestment(address indexed liquidityProvider, uint256 indexed sharesBurned);

    /// CONSTANTS
    uint256 public constant FEE_RATE = 500;        //fee = 1/feeRate = 0.2%

    /// STORAGE
    uint256 public bnbPool;
    uint256 public tokenPool;
    uint256 public invariant;
    uint256 public totalShares;
    address public tokenAddress;
    address public factoryAddress;
    mapping(address => uint256) shares;
    BEP20Interface token;
    FactoryInterface factory;

    /// MODIFIERS
    modifier exchangeInitialized() {
        require(invariant > 0 && totalShares > 0);
        _;
    }

    /// CONSTRUCTOR
    function ExoswapDex(address _tokenAddress) public {
        tokenAddress = _tokenAddress;
        factoryAddress = msg.sender;
        token = BEP20Interface(tokenAddress);
        factory = FactoryInterface(factoryAddress);
    }

    /// FALLBACK FUNCTION
    function() public payable {
        require(msg.value != 0);
        bnbToToken(msg.sender, msg.sender, msg.value, 1);
    }

    / FUNCTIONS
    function initializeExchange(uint256 _tokenAmount) payable {
        require(invariant == 0 && totalShares == 0);
        // Prevents share cost from being too high or too low - potentially needs work
        require(msg.value >= 10000 && _tokenAmount >= 10000 && msg.value <= 5*10**18);
        bnbPool = msg.value;
        tokenPool = _tokenAmount;
        invariant = bnbPool.mul(tokenPool);
        shares[msg.sender] = 1000;
        totalShares = 1000;
        require(token.transferFrom(msg.sender, address(this), _tokenAmount));
    }

    // Buyer swaps bnb for Tokens
    function bnbToTokenSwap(
        uint256 _minTokens,
        uint256 _timeout
    )
        payable
    {
        require(msg.value > 0 && _minTokens > 0 && now < _timeout);
        bnbToToken(msg.sender, msg.sender, msg.value,  _minTokens);
    }

    // Payer pays in bnb, recipient receives Tokens
    function bnbToTokenPayment(
        uint256 _minTokens,
        uint256 _timeout,
        address _recipient
    )
        payable
    {
        require(msg.value > 0 && _minTokens > 0 && now < _timeout);
        require(_recipient != address(0) && _recipient != address(this));
        bnbToToken(msg.sender, _recipient, msg.value,  _minTokens);
    }

    // Buyer swaps Tokens for bnb
    function tokenTobnbSwap(
        uint256 _tokenAmount,
        uint256 _minbnb,
        uint256 _timeout
    )
    {
        require(_tokenAmount > 0 && _minbnb > 0 && now < _timeout);
        tokenTobnb(msg.sender, msg.sender, _tokenAmount, _minbnb);
    }

    // Payer pays in Tokens, recipient receives bnb
    function tokenTobnbPayment(
        uint256 _tokenAmount,
        uint256 _minbnb,
        uint256 _timeout,
        address _recipient
    )
    {
        require(_tokenAmount > 0 && _minbnb > 0 && now < _timeout);
        require(_recipient != address(0) && _recipient != address(this));
        tokenTobnb(msg.sender, _recipient, _tokenAmount, _minbnb);
    }

    // Buyer swaps Tokens in current exchange for Tokens of provided address
    function tokenToTokenSwap(
        address _tokenPurchased,                  // Must be a token with an attached Exoswap exchange
        uint256 _tokensSold,
        uint256 _minTokensReceived,
        uint256 _timeout
    )
    {
        require(_tokensSold > 0 && _minTokensReceived > 0 && now < _timeout);
        tokenToTokenOut(_tokenPurchased, msg.sender, msg.sender, _tokensSold, _minTokensReceived);
    }

    // Payer pays in exchange Token, recipient receives Tokens of provided address
    function tokenToTokenPayment(
        address _tokenPurchased,
        address _recipient,
        uint256 _tokensSold,
        uint256 _minTokensReceived,
        uint256 _timeout
    )
    {
        require(_tokensSold > 0 && _minTokensReceived > 0 && now < _timeout);
        require(_recipient != address(0) && _recipient != address(this));
        tokenToTokenOut(_tokenPurchased, msg.sender, _recipient, _tokensSold, _minTokensReceived);
    }

    // Function called by another Exoswap exchange in Token to Token swaps and payments
    function tokenToTokenIn(
        address _recipient,
        uint256 _minTokens
    )
        payable
        returns (bool)
    {
        require(msg.value > 0);
        address exchangeToken = factory.exchangeToTokenLookup(msg.sender);
        require(exchangeToken != address(0));   // Only a Exoswap exchange can call this function
        bnbToToken(msg.sender, _recipient, msg.value, _minTokens);
        return true;
    }

    // Invest liquidity and receive market shares
    function investLiquidity(
        uint256 _minShares
    )
        payable
        exchangeInitialized
    {
        require(msg.value > 0 && _minShares > 0);
        uint256 bnbPerShare = bnbPool.div(totalShares);
        require(msg.value >= bnbPerShare);
        uint256 sharesPurchased = msg.value.div(bnbPerShare);
        require(sharesPurchased >= _minShares);
        uint256 tokensPerShare = tokenPool.div(totalShares);
        uint256 tokensRequired = sharesPurchased.mul(tokensPerShare);
        shares[msg.sender] = shares[msg.sender].add(sharesPurchased);
        totalShares = totalShares.add(sharesPurchased);
        bnbPool = bnbPool.add(msg.value);
        tokenPool = tokenPool.add(tokensRequired);
        invariant = bnbPool.mul(tokenPool);
        Investment(msg.sender, sharesPurchased);
        require(token.transferFrom(msg.sender, address(this), tokensRequired));
    }

    // Divest market shares and receive liquidity
    function divestLiquidity(
        uint256 _sharesBurned,
        uint256 _minbnb,
        uint256 _minTokens
    )
    {
        require(_sharesBurned > 0);
        shares[msg.sender] = shares[msg.sender].sub(_sharesBurned);
        uint256 bnbPerShare = bnbPool.div(totalShares);
        uint256 tokensPerShare = tokenPool.div(totalShares);
        uint256 bnbDivested = bnbPerShare.mul(_sharesBurned);
        uint256 tokensDivested = tokensPerShare.mul(_sharesBurned);
        require(bnbDivested >= _minbnb && tokensDivested >= _minTokens);
        totalShares = totalShares.sub(_sharesBurned);
        bnbPool = bnbPool.sub(bnbDivested);
        tokenPool = tokenPool.sub(tokensDivested);
        if (totalShares == 0) {
            invariant = 0;
        } else {
            invariant = bnbPool.mul(tokenPool);
        }
        Divestment(msg.sender, _sharesBurned);
        require(token.transfer(msg.sender, tokensDivested));
        msg.sender.transfer(bnbDivested);
    }

    // View share balance of an address
    function getShares(
        address _provider
    )
        view
        returns(uint256 _shares)
    {
        return shares[_provider];
    }

    /// INTERNAL FUNCTIONS
    function bnbToToken(
        address buyer,
        address recipient,
        uint256 bnbIn,
        uint256 minTokensOut
    )
        internal
        exchangeInitialized
    {
        uint256 fee = bnbIn.div(FEE_RATE);
        uint256 newbnbPool = bnbPool.add(bnbIn);
        uint256 tempbnbPool = newbnbPool.sub(fee);
        uint256 newTokenPool = invariant.div(tempbnbPool);
        uint256 tokensOut = tokenPool.sub(newTokenPool);
        require(tokensOut >= minTokensOut && tokensOut <= tokenPool);
        bnbPool = newbnbPool;
        tokenPool = newTokenPool;
        invariant = newbnbPool.mul(newTokenPool);
        bnbToTokenPurchase(buyer, bnbIn, tokensOut);
        require(token.transfer(recipient, tokensOut));
    }

    function tokenTobnb(
        address buyer,
        address recipient,
        uint256 tokensIn,
        uint256 minbnbOut
    )
        internal
        exchangeInitialized
    {
        uint256 fee = tokensIn.div(FEE_RATE);
        uint256 newTokenPool = tokenPool.add(tokensIn);
        uint256 tempTokenPool = newTokenPool.sub(fee);
        uint256 newbnbPool = invariant.div(tempTokenPool);
        uint256 bnbOut = bnbPool.sub(newbnbPool);
        require(bnbOut >= minbnbOut && bnbOut <= bnbPool);
        tokenPool = newTokenPool;
        bnbPool = newbnbPool;
        invariant = newbnbPool.mul(newTokenPool);
        TokenTobnbPurchase(buyer, tokensIn, bnbOut);
        require(token.transferFrom(buyer, address(this), tokensIn));
        recipient.transfer(bnbOut);
    }

    function tokenToTokenOut(
        address tokenPurchased,
        address buyer,
        address recipient,
        uint256 tokensIn,
        uint256 minTokensOut
    )
        internal
        exchangeInitialized
    {
        require(tokenPurchased != address(0) && tokenPurchased != address(this));
        address exchangeAddress = factory.tokenToExchangeLookup(tokenPurchased);
        require(exchangeAddress != address(0) && exchangeAddress != address(this));
        uint256 fee = tokensIn.div(FEE_RATE);
        uint256 newTokenPool = tokenPool.add(tokensIn);
        uint256 tempTokenPool = newTokenPool.sub(fee);
        uint256 newbnbPool = invariant.div(tempTokenPool);
        uint256 bnbOut = bnbPool.sub(newbnbPool);
        require(bnbOut <= bnbPool);
        ExoswapDex exchange = ExoswapDex(exchangeAddress);
        TokenTobnbPurchase(buyer, tokensIn, bnbOut);
        tokenPool = newTokenPool;
        bnbPool = newbnbPool;
        invariant = newbnbPool.mul(newTokenPool);
        require(token.transferFrom(buyer, address(this), tokensIn));
        require(exchange.tokenToTokenIn.value(bnbOut)(recipient, minTokensOut));
    }
}
