pragma solidity >=0.7.0 <0.9.0;

import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/TokenSr/ERC20/IERC20.sol';


contract DexEchange {
       
    enum Side {
        BUY,
        SELL
    }
    
    struct TokenStr {
        bytes32 tickerItem;
        address tokenAddress;
    }
    
    struct OrderItem {
        uint id;
        address traderAddress;
        Side side;
        bytes32 tickerItem;
        uint amount;
        uint filled;
        uint price;
        uint date;
    }
    
    mapping(bytes32 => TokenSr) public tokens;
    bytes32[] public tokenList;
    mapping(address => mapping(bytes32 => uint)) public traderBalances;
    mapping(bytes32 => mapping(uint => OrderItem[])) public orderBook;
    address public admin;
    uint public nextOrderId;
    uint public nextTradeId;
    bytes32 constant DAI = bytes32('DAI');
    
    event NewTradeItem(
        uint tradeId,
        uint orderId,
        bytes32 indexed tickerItem,
        address indexed trader1,
        address indexed trader2,
        uint amount,
        uint price,
        uint date
    );
    
    constructor() public {
        admin = msg.sender;
    }
    
    function addToken(
        bytes32 tickerItem,
        address tokenAddress)
        onlyAdmin()
        external {
        tokens[tickerItem] = TokenSr(tickerItem, tokenAddress);
        tokenList.push(tickerItem);
    }
    
    function deposit(
        uint amount,
        bytes32 tickerItem)
        tokenExist(tickerItem)
        external {
        IERC20(tokens[tickerItem].tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        traderBalances[msg.sender][tickerItem] += amount;
    }
    
    function withdraw(
        uint amount,
        bytes32 tickerItem)
        tokenExist(tickerItem)
        external {
        require(
            traderBalances[msg.sender][tickerItem] >= amount,
            'balance too low'
        ); 
        traderBalances[msg.sender][tickerItem] -= amount;
        IERC20(tokens[tickerItem].tokenAddress).transfer(msg.sender, amount);
    }
    
    function createLimitOrder(
        bytes32 tickerItem,
        uint amount,
        uint price,
        Side side)
        tokenExist(tickerItem)
        tokenIsNotDai(tickerItem)
        external {
        if(side == Side.SELL) {
            require(
                traderBalances[msg.sender][tickerItem] >= amount, 
                'TokenSr balance too low'
            );
        } else {
            require(
                traderBalances[msg.sender][DAI] >= amount * price,
                'dai balance too low'
            );
        }
        OrderItem[] storage orders = orderBook[tickerItem][uint(side)];
        orders.push(OrderItem(
            nextOrderId,
            msg.sender,
            side,
            tickerItem,
            amount,
            0,
            price,
            now 
        ));
        
        uint i = orders.length - 1;
        while(i > 0) {
            if(side == Side.BUY && orders[i - 1].price > orders[i].price) {
                break;   
            }
            if(side == Side.SELL && orders[i - 1].price < orders[i].price) {
                break;   
            }
            OrderItem memory OrderItem = orders[i - 1];
            orders[i - 1] = orders[i];
            orders[i] = OrderItem;
            i--;
        }
        nextOrderId++;
    }
    
    function createMarketOrder(
        bytes32 tickerItem,
        uint amount,
        Side side)
        tokenExist(tickerItem)
        tokenIsNotDai(tickerItem)
        external {
        if(side == Side.SELL) {
            require(
                traderBalances[msg.sender][tickerItem] >= amount, 
                'TokenSr balance too low'
            );
        }
        OrderItem[] storage orders = orderBook[tickerItem][uint(side == Side.BUY ? Side.SELL : Side.BUY)];
        uint i;
        uint remaining = amount;
        
        while(i < orders.length && remaining > 0) {
            uint available = orders[i].amount - orders[i].filled;
            uint matched = (remaining > available) ? available : remaining;
            remaining -= matched;
            orders[i].filled += matched;
            emit NewTradeItem(
                nextTradeId,
                orders[i].id,
                tickerItem,
                orders[i].traderAddress,
                msg.sender,
                matched,
                orders[i].price,
                now
            );
            if(side == Side.SELL) {
                traderBalances[msg.sender][tickerItem] -= matched;
                traderBalances[msg.sender][DAI] += matched * orders[i].price;
                traderBalances[orders[i].traderAddress][tickerItem] += matched;
                traderBalances[orders[i].traderAddress][DAI] -= matched * orders[i].price;
            }
            if(side == Side.BUY) {
                require(
                    traderBalances[msg.sender][DAI] >= matched * orders[i].price,
                    'dai balance too low'
                );
                traderBalances[msg.sender][tickerItem] += matched;
                traderBalances[msg.sender][DAI] -= matched * orders[i].price;
                traderBalances[orders[i].traderAddress][tickerItem] -= matched;
                traderBalances[orders[i].traderAddress][DAI] += matched * orders[i].price;
            }
            nextTradeId++;
            i++;
        }
        
        i = 0;
        while(i < orders.length && orders[i].filled == orders[i].amount) {
            for(uint j = i; j < orders.length - 1; j++ ) {
                orders[j] = orders[j + 1];
            }
            orders.pop();
            i++;
        }
    }
   
   modifier tokenIsNotDai(bytes32 tickerItem) {
       require(tickerItem != DAI, 'cannot trade DAI');
       _;
   }     
    
    modifier tokenExist(bytes32 tickerItem) {
        require(
            tokens[tickerItem].tokenAddress != address(0),
            'this TokenSr does not exist'
        );
        _;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, 'only admin');
        _;
    }
}
