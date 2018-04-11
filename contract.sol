pragma solidity ^0.4.8;

contract Owned {
    address public owner;
    
    event TransferOwnership(address oldaddr, address newaddr);
    
    modifier onlyOwner(){ if (msg.sender != owner) throw; _;}
    
    function Owned() public{
        owner = msg.sender;
    }
    
    function transferOwnership(address _new) onlyOwner public{
        address oldaddr = owner;
        owner = _new;
        emit TransferOwnership(oldaddr, owner);
    }
}

contract Members is Owned {
    address public coin;
    MemberStatus[] public status;
    mapping (address => History) public tradingHistory;
    
    struct MemberStatus {
        string name;
        uint256 times;
        uint256 sum;
        int8 rate;
    }
    
    struct History {
        uint256 times;
        uint256 sum;
        uint256 statusIndex;
    }
    
    modifier onlyCoin() { if (msg.sender == coin) _; }
    
    function setCoin(address _addr) onlyOwner public{
        coin = _addr;
    }
    
    function pushStatus (string _name, uint256 _times, uint256 _sum, int8 _rate) onlyOwner public{
        status.push(MemberStatus({
            name: _name
          , times: _times
          , sum: _sum
          , rate: _rate
        }));
    }
    
    function editStatus(uint256 _index, string _name, uint256 _times, uint256 _sum, int8 _rate) public{
        if (_index < status.length){
            status[_index].name = _name;
            status[_index].times = _times;
            status[_index].sum = _sum;
            status[_index].rate = _rate;
        }
    }
    
    function updateHistory(address _member, uint256 _value) public onlyCoin {
        tradingHistory[_member].times += 1;
        tradingHistory[_member].sum += _value;
        
        uint256 index;
        int8 tmprate;
        
        for (uint i = 0; i< status.length; i++){
            if (tradingHistory[_member].times >= status[i].times &&
                tradingHistory[_member].sum >= status[i].sum &&
                tmprate < status[i].rate) {
                    index = i;
            }
        }
        tradingHistory[_member].statusIndex = index;
    }
    
    function getCashbackRate(address _member) public constant returns (int8 rate){
        rate = status[tradingHistory[_member].statusIndex].rate;
    }
}

contract  MLCoin is Owned {
    // (1) 상태 변수 선언
    string public name; // 토큰 이름
    string public symbol; // 토큰 단위
    uint8 public decimals; // 소수점 이하 자릿수
    uint256 public totalSupply; // 토큰 총량
    mapping (address => uint256) public balanceOf; // 각 주소의 잔고
    mapping (address => bool) public blackList; // 블랙리스트
    mapping (address => Members) public members;
 
    // (3) 이벤트 알림
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Blacklisted(address indexed target);
    event DeleteFromBlacklist(address indexed target);
    event RejectedPaymentToBlacklistedAddr(address indexed from, address indexed to, uint256 value);
    event RejectedPaymentFromBlacklistedAddr(address indexed from, address indexed to, uint256 value);
    event Cashback(address indexed from, address indexed to, uint256 value);

    // (4) 생성자
    function MLCoin(uint256 _supply, string _name, string _symbol, uint8 _decimals) public {
        balanceOf[msg.sender] = _supply;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _supply;
    }   
    
    // (5) 주소를 블랙리스트에 등록  
    function blacklisting(address _addr) onlyOwner public{
        blackList[_addr] = true;
        emit Blacklisted(_addr);
    }   
 
    // (6) 주소를 블랙리스트에서 제거
    function deleteFromBlacklist(address _addr) onlyOwner public{
        blackList[_addr] = false; 
        emit DeleteFromBlacklist(_addr);
    }
    
    function setMembers(Members _members) public {
        members[msg.sender] = Members(_members);
    }
            
    // (7) 송금
    function transfer(address _to, uint256 _value) public {
        // 부정 송금 확인
        if (balanceOf[msg.sender] < _value) revert();
        if (balanceOf[_to] + _value < balanceOf[_to]) revert();
        // 블랙리스트에 존재하는 주소는 입출금 불가
        if (blackList[msg.sender] == true) {
            emit RejectedPaymentFromBlacklistedAddr(msg.sender, _to, _value);
        } else if (blackList[_to] > true) {
            emit RejectedPaymentToBlacklistedAddr(msg.sender, _to, _value);
        } else {
            uint256 cashback = 0;
            if (members[_to] > address(0)){
                cashback = _value / 100 * uint256(members[_to].getCashbackRate(msg.sender));
                members[_to].updateHistory(msg.sender, _value);
            }
            
            balanceOf[msg.sender] -= (_value - cashback);
            balanceOf[_to] += (_value - cashback);
            
            emit Transfer(msg.sender, _to, _value);
            emit Cashback(_to, msg.sender, cashback);
        }   
    }   
}

contract CrowdSale is Owned {
    uint256 public fundingGoal;
    uint256 public deadline;
    uint256 public price;
    uint256 public transferableToken;
    uint256 public soldToken;
    uint256 public startTime;
    MLCoin public tokenReward;
    bool public fundingGoalReached;
    bool public isOpened;
    mapping (address => Property) public fundersProperty;
    
    struct Property {
        uint256 paymentEther;
        uint256 reservedToken;
        bool withdrawed;
    }
    
    event CrowdsaleStart(uint fundingGoal, uint deadline, uint transferableToken, address beneficiary);
    event ReservedToken(address backer, uint amount, uint token);
    event CheckGoalReached(address beneficiary, uint fundingGoal, uint amountRaised, bool reached, uint raisedToken);
    event WithdrawalToken(address addr, uint amount, bool result);
    event WithdrawalEther(address addr, uint amount, bool result);
    
    modifier afterDeadline() { if (now >= deadline) _; }
    
    function CrowdSale(uint _fundingGoalInEthers, uint _transferableToken, 
                       uint _amountOfTokenPerEther, MLCoin _addressOfTokenUsedAsReward){
    
        fundingGoal = _fundingGoalInEthers * 1 ether;
        price = 1 ether / _amountOfTokenPerEther;
        transferableToken = _transferableToken;
        tokenReward = MLCoin(_addressOfTokenUsedAsReward);
                           
    }
    
    function() payable{
        if (!isOpened || now >= deadline) throw;
        
        uint amount = msg.value;
        uint token = amount / price * (100 + currentSwaprate()) / 100;
        
        if (token == 0 || soldToken + token > transferableToken) revert();
        fundersProperty[msg.sender].paymentEther += amount;
        fundersProperty[msg.sender].reservedToken += token;
        soldToken += token;
        emit ReservedToken(msg.sender, amount, token);
    }
    
    function start(uint _durationInMinutes) onlyOwner {
        if (fundingGoal == 0 || transferableToken == 0 || price == 0 || tokenReward == address(0) ||
            _durationInMinutes == 0 || startTime != 0){
                
            throw;
            
        }
        if (tokenReward.balanceOf(this) >= transferableToken){
            startTime = now;
            deadline = now + _durationInMinutes * 1 minutes;
            isOpened = true;
            CrowdsaleStart(fundingGoal, deadline, transferableToken, owner);
        }
    }
    
    function currentSwaprate() constant returns (uint){
        if (startTime + 3 minutes > now)
        {
            return 100;    
        } else if (startTime + 5 minutes > now){
            return 50;
        } else if (startTime + 10 minutes > now){
            return 20;
        } else {
            return 0;
        }
    }
    
    function getRemainingTimeEthToken() constant returns (uint min, uint shortage, uint remainToken){
        if (now < deadline) {
            min = (deadline - now) / (1 minutes);
        }
        shortage = (fundingGoal - this.balance) / (1 ether);
        remainToken = transferableToken - soldToken;
    }
    
    function checkGoalReached() afterDeadline {
        if (isOpened){
            if (this.balance >= fundingGoal){
                fundingGoalReached = true;
            }
            isOpened = false;
            CheckGoalReached(owner, fundingGoal, this.balance, fundingGoalReached, soldToken);
        }
    }
    
    function withdrawalOwner() onlyOwner{
        if (isOpened) revert();
        
        if (fundingGoalReached){
            uint amount = this.balance;
            if (amount > 0){
                bool ok = msg.sender.call.value(amount)();
                WithdrawalEther(msg.sender, amount, ok);
            }
            
            uint val = transferableToken - soldToken;
            if (val > 0){
                tokenReward.transfer(msg.sender, transferableToken - soldToken);
                WithdrawalToken(msg.sender, val, true);
            }
        } else {
            uint val2 = tokenReward.balanceOf(this);
            tokenReward.transfer(msg.sender, val2);
            WithdrawalToken(msg.sender, val2, true);
        }
    }
    
    function withdrawl(){
        if (isOpened) revert();
        
        if (fundersProperty[msg.sender].withdrawed) revert();
        
        if (fundingGoalReached){
            if (fundersProperty[msg.sender].reservedToken > 0){
                tokenReward.transfer(msg.sender, fundersProperty[msg.sender].reservedToken);
                fundersProperty[msg.sender].withdrawed = true;
                WithdrawalToken(msg.sender, fundersProperty[msg.sender].reservedToken, fundersProperty[msg.sender].withdrawed);
            }
        } else {
            if (fundersProperty[msg.sender].paymentEther > 0){
                if (msg.sender.call.value(fundersProperty[msg.sender].paymentEther)()){
                    fundersProperty[msg.sender].withdrawed = true;
                }
                WithdrawalEther(msg.sender, fundersProperty[msg.sender].paymentEther, fundersProperty[msg.sender].withdrawed);
            }
        }
    }
}

