pragma solidity >=0.6.0 <=0.8.0;

 import "@openzeppelin/contracts/access/Ownable.sol";
 import "./Token.sol";
 
contract CarRental is Ownable {
   
    string public name = "Car Rental";
    Token token; //Reference to deployed ERC20 Token contract
    address public payable wallet; //Address of the owner of Car Rental Shop
    uint8 collateralPremium=20; // discount % to be applied to standard rate for PREMIUM "collateralized customers"
    uint8 tokenConversionRate = 2; //conversion rate between Ether and Token, i.e. 1 Ether = 2 Token
    uint rate=1; //amount of wei to be charged per second (i.e. "standard rate")
    uint etherMinBalance=1; //minimum amount of ETH required to start Car rental
    uint tokenMinBalance= 1; //minimum amount of Tokens required to start Car rental   
    uint etherCollateralThreshold=1; //Threshold amount of ETH required to get PREMIUM "collateralized" rate
    uint tokenCollateralThreshold=1; //Threshold amount of Tokens required to get PREMIUM "collateralized" rate
    uint public no_of_agreement = 0; //agreement no.
    
    struct Car {                
        uint8 CarId; // Id of the car
        string carbrand;  // characteristcs of the car
        string color;
        string type;
        uint rent_per_hour;
        uint securityDeposit;
        bool notAvailable;
        bool damage;
        address customer; 
    }

    struct Customer { 
        uint8 CarId; // Id of rented Car       
        bool isRenting; // in order to start renting, `isRenting` should be false
        uint rate; //customer's applicable rental rate
        uint etherBalance; // customer internal ether account
        uint tokenBalance; // customer internal token account
        uint startTime; //starting time of the rental (in seconds)
        uint etherDebt; // amount in ether owed to Car Rental Shop
    }    

    mapping (address => Customer) customers ; // Record with customers data (i.e., balance, startTie, debt, rate, etc)
    mapping (uint8 => Car) Cars ; // Stock of Cars    

    modifier onlyCompany() {
        require(msg.sender == wallet, "Only company can access this");
        _;
    }
   
    modifier OnlyWhileNoPending(){
        require(customers[msg.sender].etherDebt == 0, "Not allowed to rent if debt is pending");
        _;
    }

    modifier OnlyWhileAvailable(uint8 _CarId){
        require(!Cars[_CarId].notAvailable, "Car not available");
        _;
    }

    modifier OnlyOneRental(){
        require(!customers[msg.sender].isRenting, "Another car rental in progress. Finish current rental first");
        _;
    }

    modifier EnoughRentFee(){
        require(customers[msg.sender].etherBalance >= etherMinBalance || customers[msg.sender].tokenBalance >= tokenMinBalance, "Not enough funds in your account");
        _;
    }
    
    modifier sameCustomer(uint8 _CarId) {
        require(msg.sender == Cars[_CarId].customer, "No previous agreement found with you & company");
        _;
    }
    
    modifier Notdamage(uint8 _CarId){
        require(!Cars[_CarId].damage, "Car damage");
        _;
    }

    event RentalStart(address _customer, uint _startTime, uint _rate, uint8 _CarId, uint _blockId);
    event RentalStop(address _customer, uint _stopTime, uint _totalAmount, uint _totalDebt, uint _blockId);
    event FundsReceived(address _customer, uint _etherAmount, uint _tokenAmount);
    event FundsWithdrawned(address _customer);
    event FundsReturned(address _customer, uint _etherAmount, uint _tokenAmount);
    event BalanceUpdated(address _customer, uint _etherAmount, uint _tokenAmount);
    event TokensReceived(address _customer, uint _tokenAmount);    
    event DebtUpdated (address _customer, uint _origAmount, uint _pendingAmount, uint _debitedAmount, uint _tokenDebitedAmount);
    event TokensBought (address _customer,uint _etherAmount, uint _tokenAmount);

    constructor (Token _token) Ownable() {
        token = _token;
        wallet = payable(msg.sender);
    }    
  
    function buyTokens() payable public {
        require(msg.value > 0, "You need to send some Ether");
        uint256 tokensTobuy = msg.value * tokenConversionRate;
        uint256 rentalBalance = token.balanceOf(address(this));        
        require(tokensTobuy <= rentalBalance, "Not enough tokens in the reserve");
        token.transfer(msg.sender, tokensTobuy);
        wallet.transfer(msg.value);
        emit TokensBought(msg.sender, msg.value, tokensTobuy);
    } 

    function transferFunds() payable public {
        uint amount = token.allowance(msg.sender, address(this));
        _updateBalances(msg.sender , msg.value);
        if (customers[msg.sender].etherDebt > 0) {
            _updateStandingDebt(msg.sender,customers[msg.sender].etherDebt);
        }
        emit FundsReceived(msg.sender, msg.value, amount);
    }

    function _returnFunds(address payable _customer) private{
        uint tokenAmount = customers[_customer].tokenBalance;
        token.transfer(_customer, tokenAmount);
        customers[_customer].tokenBalance = 0;
        uint etherAmount = customers[_customer].etherBalance;
        _customer.transfer(etherAmount);
        customers[_customer].etherBalance= 0;
        emit FundsReturned(_customer, etherAmount, tokenAmount);
    }
    
    function withdrawFunds() public {
        require(!customers[msg.sender].isRenting, "Bike rental in progress. Finish current rental first");        
        if (customers[msg.sender].etherDebt > 0) {
            _updateStandingDebt(msg.sender,customers[msg.sender].etherDebt);
        }
        _returnFunds(payable(msg.sender));
        emit FundsWithdrawned(msg.sender);
    }

    function _updateBalances(address _customer, uint _ethers) private {        
        uint amount = 0;
        if (_ethers > 0) {             
            customers[_customer].etherBalance += _ethers;             
        }
        if (token.allowance(_customer, address(this)) > 0){
            amount = token.allowance(_customer, address(this));
            token.transferFrom(_customer, address(this), amount);
            customers[_customer].tokenBalance += amount;            
            emit TokensReceived(_customer, amount);
        }
        emit BalanceUpdated(_customer, _ethers, amount);
    }

    function _updateStandingDebt(address _customer, uint _amount) private returns (uint) {
        uint tokenPendingAmount = _amount * tokenConversionRate;
        uint tokensDebitedAmount=0;
        
        //First try to cancel pending debt with tokens available in customer's token account balance        
        if (customers[_customer].tokenBalance >= tokenPendingAmount){            
            customers[_customer].tokenBalance -= tokenPendingAmount;
            customers[_customer].etherDebt = 0;
            tokensDebitedAmount = tokenPendingAmount;
            emit DebtUpdated(_customer, _amount , 0, 0, tokensDebitedAmount);
            return 0;
        }
        else {
            tokenPendingAmount -= customers[_customer].tokenBalance;
            tokensDebitedAmount = customers[_customer].tokenBalance;
            customers[_customer].tokenBalance = 0;
            customers[_customer].etherDebt = tokenPendingAmount / tokenConversionRate;
        }
        //If debt pending amount > 0, try to cancel it with Ether available in customer's Ether account balance 
        uint etherPendingAmount = tokenPendingAmount / tokenConversionRate;
        if (customers[_customer].etherBalance >= etherPendingAmount){
            customers[_customer].etherBalance -= etherPendingAmount;
            wallet.transfer(etherPendingAmount);
            customers[_customer].etherDebt = 0;
            emit DebtUpdated(_customer, _amount , 0, etherPendingAmount, tokensDebitedAmount);
            return 0;
            
        }
        else {
            etherPendingAmount -= customers[_customer].etherBalance;
            uint debitedAmount = customers[_customer].etherBalance;
            wallet.transfer(debitedAmount);
            customers[_customer].etherDebt = etherPendingAmount;
            customers[_customer].etherBalance = 0;
            emit DebtUpdated(_customer, _amount , customers[_customer].etherDebt, debitedAmount, tokensDebitedAmount);
            return customers[_customer].etherDebt;
        }        
    }
  
    function startRental (uint8 _bikeId) payable public{
        require(customers[msg.sender].etherDebt == 0, "Not allowed to rent if debt is pending");
        require(!bikes[_bikeId].notAvailable, "Car not available");
        require(!customers[msg.sender].isRenting, "Another bike rental in progress. Finish current rental first");        
        _updateBalances(msg.sender , msg.value);        
        uint etherBalance = customers[msg.sender].etherBalance;
        uint tokenBalance = customers[msg.sender].tokenBalance;
        require(etherBalance >= etherMinBalance || tokenBalance >= tokenMinBalance, "Not enough funds in your account");
        customers[msg.sender].isRenting = true;
        //if the customer has deposited collateral amount, set Premium rate
        if (etherBalance > etherCollateralThreshold || tokenBalance > tokenCollateralThreshold){
            customers[msg.sender].rate = (rate * (100 - collateralPremium)) / 100;
        }
        else {
            customers[msg.sender].rate = rate;
        }
        customers[msg.sender].startTime = block.timestamp;
        customers[msg.sender].bikeId = _bikeId;
        bikes[_bikeId].notAvailable = true;
        bikes[_bikeId].customer == msg.sender;
                

        emit RentalStart(msg.sender, block.timestamp, customers[msg.sender].rate, _bikeId, block.number);
    }

     function stopRental () external {
         uint startTime = customers[msg.sender].startTime;
         uint stopTime = block.timestamp;
         uint totalTime = stopTime - startTime;         
         uint amountToPay = customers[msg.sender].rate * totalTime;
         
         uint etherPendingAmount = _updateStandingDebt(msg.sender, amountToPay);

         if (etherPendingAmount == 0){             
             _returnFunds(payable(msg.sender));
         }
         
         uint8 bikeId = customers[msg.sender].bikeId ;         
         bikes[bikeId].notAvailable = false;
         bikes[bikeId].customer = address(0);
         customers[msg.sender].isRenting = false;
         customers[msg.sender].bikeId = 0;

         emit RentalStop(msg.sender, block.timestamp, amountToPay, customers[msg.sender].etherDebt, block.number);
     }
    
     function setRate(uint _rate) external onlyOwner {
         rate = _rate;
     }

    function setCollateralThreshold(uint _threshold) external onlyOwner {
         etherCollateralThreshold = _threshold;
         tokenCollateralThreshold = etherCollateralThreshold * tokenConversionRate;
     }

    function setEtherMinimumBalance(uint _etherMin) external onlyOwner {
         etherMinBalance = _etherMin;
         tokenMinBalance = etherMinBalance * tokenConversionRate;
     }
 
    function setTokenConversionRate(uint8 _conversion) external onlyOwner {
         tokenConversionRate = _conversion;         
     }

    function setCollateralPremium(uint8 _premium) external onlyOwner {
         collateralPremium = _premium;         
     }

    //truffle testing functions     

    function getCustomerRate(address _customer) external view returns (uint) {
         return customers[_customer].rate;
     } 

    function getRate() external view returns (uint) {
         return rate;
     }

     function getDebt(address customer) public view returns (uint) {
         return customers[customer].etherDebt;
     }
     
     function getEtherAccountBalance(address customer) public view returns (uint) {
         return customers[customer].etherBalance;
     }

     function getTokenAccountBalance(address customer) public view returns (uint) {
         return customers[customer].tokenBalance;
     }
}
