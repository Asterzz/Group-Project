// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

 import "@openzeppelin/contracts/access/Ownable.sol";
 import "./Token.sol";
 
contract CarRental {
    string public nameOfContract = "Car Rental";
    Token token; // reference to deployed ERC20 Token contract
    address owner;
    address payable wallet; // address of the owner of Car Rental Shop
    uint public carCount = 0; // number of cars in stock
    uint tokenConversionRate = 2; //conversion rate between Ether and Token, i.e. 1 Ether = 2 Token
    uint etherMinBalance = 1 ether; // minimum amount of ETH required to start Car rental
    uint tokenMinBalance = etherMinBalance * tokenConversionRate; // minimum amount of Tokens required to start Car rental   
    
    struct Car {
        uint carId; // Id of the car
        string carBrand;  // characteristcs of the car
        string color;
        string carType;
        uint rentPerHour;
        uint securityDeposit;
        bool notAvailable;
        bool damage;
        address customer; 
    }

    struct Customer { 
        uint carId; // Id of rented Car       
        bool isRenting; // in order to start renting, `isRenting` should be false
        uint etherBalance; // customer internal ether account
        uint tokenBalance; // customer internal token account
        uint startTime; // starting time of the rental (in seconds)
        uint etherDebt; // amount in ether owed to Car Rental Shop
        bool existence; // existing status of customer
    }    

    struct Log{
        uint carId; // Id of rented Car  
        uint time; // starting time of the rental (in seconds)
        uint amount; // total rental amount
    }

    mapping (address => Customer) Customers ; // Record with customers data (i.e., balance, startTime, debt, rate, etc)
    mapping (uint => Car) Cars ; // Stock of Cars   
    mapping (address => Log[]) Logs; // Renting Record of customer

    modifier onlyCompany() {
        require(msg.sender == wallet, "Only company can access this");
        _;
    }
   
    modifier OnlyWhileNoPending(){
        require(Customers[msg.sender].etherDebt == 0, "Not allowed to rent if debt is pending");
        _;
    }

    modifier OnlyWhileAvailable(uint carId){
        require(!Cars[carId].notAvailable, "Car not available");
        _;
    }

    modifier OnlyOneRental(){
        require(!Customers[msg.sender].isRenting, "Another car rental in progress. Finish current rental first");
        _;
    }

    modifier EnoughRentFee(){
        require(Customers[msg.sender].etherBalance >= etherMinBalance || Customers[msg.sender].tokenBalance >= tokenMinBalance, "Not enough funds in your account");
        _;
    }
    
    modifier sameCustomer(uint carId) {
        require(msg.sender == Cars[carId].customer, "No previous agreement found with you & company");
        _;
    }
    
    modifier Notdamage(uint carId){
        require(!Cars[carId].damage, "Car damage");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Function accessible only by the owner");
        _;
    }

    modifier onlyCustomer() {
        require(msg.sender != owner, "Function accessible only by the customer");
        _;
    }

    event RentalStart(address _customer, uint _startTime, uint carId, uint _blockId);
    event RentalStop(address _customer, uint _stopTime, uint _totalAmount, uint _totalDebt, uint _blockId);
    event FundsReceived(address _customer, uint _etherAmount, uint _tokenAmount);
    event FundsWithdrawned(address _customer);
    event FundsReturned(address _customer, uint _etherAmount, uint _tokenAmount);
    event BalanceUpdated(address _customer, uint _etherAmount, uint _tokenAmount);
    event TokensReceived(address _customer, uint _tokenAmount);    
    event DebtUpdated (address _customer, uint _origAmount, uint _pendingAmount, uint _debitedAmount, uint _tokenDebitedAmount);
    event TokensBought (address _customer,uint _etherAmount, uint _tokenAmount);

    constructor (Token _token) payable {
        token = _token;
        owner = msg.sender;
        wallet = payable(msg.sender);
        addDefaultCar();
        //token.transfer(address(this), token.totalSupply());
    } 

    function tokenToContract() public{ // does not work
        token.transfer(address(this), token.balanceOf(owner));
    }

    function addCar(uint _carId, string memory _carBrand, string memory _color, string memory _type, uint _rent) public onlyOwner {
        require(Cars[_carId].customer == address(0), "Car ID already occupied");
        uint _deposit = _rent * 3;
        Cars[_carId] = Car(_carId, _carBrand, _color, _type, _rent, _deposit, false, false, owner);
        carCount += 1;
    }

    function addDefaultCar() public onlyOwner {
        addCar(1001, "Brand A", "Silver", "Large", 1 ether);
        addCar(1002, "Brand A", "Black", "Large", 1 ether);
        addCar(1003, "Brand B", "White", "SUV", 1 ether);
        addCar(1004, "Brand B", "Black", "SUV", 1 ether);
        addCar(1005, "Brand C", "Orange", "Sportscar", 5 ether);
        addCar(1006, "Boeing", "White", "787", 10 ether);
    }

    function viewCar(uint _carId) public view returns (uint, string memory, string memory, string memory, uint, uint, string memory, bool, address) {
        Car memory temp = Cars[_carId];
        string memory status;
        if (temp.notAvailable){
            status = "Occupied";
        }
        else{
            status = "Available";
        }
        return (temp.carId, temp.carBrand, temp.color, temp.carType,
            temp.rentPerHour/1000000000000000000,
            temp.securityDeposit/1000000000000000000,
            status, temp.damage, temp.customer);
    }

    function buyTokens() payable public {
        require(msg.value > 0, "You need to send some Ether");
        uint tokensTobuy = msg.value * tokenConversionRate;
        uint rentalBalance = token.balanceOf(address(this));        
        require(tokensTobuy <= rentalBalance, "Not enough tokens in the reserve");
        token.transfer(msg.sender, tokensTobuy);
        token.approve(owner, tokensTobuy);
        wallet.transfer(msg.value);
        emit TokensBought(msg.sender, msg.value, tokensTobuy);
    }

    function transferFunds() payable public {
        uint amount = token.allowance(msg.sender, address(this));
        _updateBalances(msg.sender , msg.value);
        if (Customers[msg.sender].etherDebt > 0) {
            _updateStandingDebt(msg.sender,Customers[msg.sender].etherDebt);
        }
        emit FundsReceived(msg.sender, msg.value, amount);
    }

    function _returnFunds(address payable _customer) private{
        uint tokenAmount = Customers[_customer].tokenBalance;
        token.transfer(_customer, tokenAmount);
        Customers[_customer].tokenBalance = 0;
        uint etherAmount = Customers[_customer].etherBalance;
        _customer.transfer(etherAmount);
        Customers[_customer].etherBalance= 0;
        emit FundsReturned(_customer, etherAmount, tokenAmount);
    }
    
    function withdrawFunds() public {
        require(!Customers[msg.sender].isRenting, "Bike rental in progress. Finish current rental first");        
        if (Customers[msg.sender].etherDebt > 0) {
            _updateStandingDebt(msg.sender,Customers[msg.sender].etherDebt);
        }
        _returnFunds(payable(msg.sender));
        emit FundsWithdrawned(msg.sender);
    }

    function _updateBalances(address _customer, uint _ethers) private {        
        uint amount = 0;
        if (_ethers > 0) {             
            Customers[_customer].etherBalance += _ethers;             
        }
        if (token.allowance(_customer, address(this)) > 0){
            amount = token.allowance(_customer, address(this));
            token.transferFrom(_customer, address(this), amount);
            Customers[_customer].tokenBalance += amount;            
            emit TokensReceived(_customer, amount);
        }
        emit BalanceUpdated(_customer, _ethers, amount);
    }

    function _updateStandingDebt(address _customer, uint _amount) private returns (uint) {
        uint tokenPendingAmount = _amount * tokenConversionRate;
        uint tokensDebitedAmount=0;
        
        //First try to cancel pending debt with tokens available in customer's token account balance        
        if (Customers[_customer].tokenBalance >= tokenPendingAmount){            
            Customers[_customer].tokenBalance -= tokenPendingAmount;
            Customers[_customer].etherDebt = 0;
            tokensDebitedAmount = tokenPendingAmount;
            emit DebtUpdated(_customer, _amount , 0, 0, tokensDebitedAmount);
            return 0;
        }
        else {
            tokenPendingAmount -= Customers[_customer].tokenBalance;
            tokensDebitedAmount = Customers[_customer].tokenBalance;
            Customers[_customer].tokenBalance = 0;
            Customers[_customer].etherDebt = tokenPendingAmount / tokenConversionRate;
        }
        //If debt pending amount > 0, try to cancel it with Ether available in customer's Ether account balance 
        uint etherPendingAmount = tokenPendingAmount / tokenConversionRate;
        if (Customers[_customer].etherBalance >= etherPendingAmount){
            Customers[_customer].etherBalance -= etherPendingAmount;
            wallet.transfer(etherPendingAmount);
            Customers[_customer].etherDebt = 0;
            emit DebtUpdated(_customer, _amount , 0, etherPendingAmount, tokensDebitedAmount);
            return 0;
            
        }
        else {
            etherPendingAmount -= Customers[_customer].etherBalance;
            uint debitedAmount = Customers[_customer].etherBalance;
            wallet.transfer(debitedAmount);
            Customers[_customer].etherDebt = etherPendingAmount;
            Customers[_customer].etherBalance = 0;
            emit DebtUpdated(_customer, _amount , Customers[_customer].etherDebt, debitedAmount, tokensDebitedAmount);
            return Customers[_customer].etherDebt;
        }
    }

    function startRental(uint _carId) public payable onlyCustomer {
        // (modifiers:) onlyCompany OnlyWhileNoPending OnlyWhileAvailable(_carId) EnoughRentFee sameCustomer(_carId) Notdamage(_carId)
        //check the status of car
        require(Cars[_carId].customer != address(0), "Car not exist");
        require(!Cars[_carId].notAvailable, "Car not available"); // OnlyWhileAvailable
        require(!Cars[_carId].damage, "Car damage"); // Notdamage

        //check the status of customer
        require(Customers[msg.sender].etherDebt == 0, "Not allowed to rent if debt is pending");
        _updateBalances(msg.sender, msg.value);        
        uint etherBalance = Customers[msg.sender].etherBalance;
        uint tokenBalance = Customers[msg.sender].tokenBalance;
        require(etherBalance >= etherMinBalance || tokenBalance >= tokenMinBalance, "Not enough funds in your account");
        require(etherBalance + tokenBalance / tokenConversionRate >= Cars[_carId].securityDeposit, "Not enough funds to fulfill security deposit");

        //customer status updated
        Customers[msg.sender].existence = true;
        Customers[msg.sender].isRenting = true;
        Customers[msg.sender].startTime = block.timestamp;
        Customers[msg.sender].carId = _carId;

        //car status updated
        Cars[_carId].notAvailable = true;
        Cars[_carId].customer = msg.sender;
        emit RentalStart(msg.sender, block.timestamp, _carId, block.number);
    }

    function stopRental() external onlyCustomer returns(uint, uint) {
        require(Customers[msg.sender].isRenting = true, "You are not renting a car");
        uint startTime = Customers[msg.sender].startTime;
        uint stopTime = block.timestamp;
        uint totalTime = stopTime - startTime;

        uint _carId = Customers[msg.sender].carId;

        //balance settlement
        uint amountToPay = Cars[_carId].rentPerHour * totalTime / 3600;
        if (Cars[_carId].damage){
            amountToPay += Cars[_carId].securityDeposit;
        }
        uint etherPendingAmount = _updateStandingDebt(msg.sender, amountToPay);
        if (etherPendingAmount == 0){
            _returnFunds(payable(msg.sender));
        }

        //update car status
        Cars[_carId].notAvailable = false;
        Cars[_carId].customer = owner;
        
        //update customer status
        Customers[msg.sender].carId = 0;
        Customers[msg.sender].isRenting = false;
        
        //record rent time and fee
        Logs[msg.sender].push(Log(_carId, totalTime, amountToPay));
        emit RentalStop(msg.sender, block.timestamp, amountToPay, Customers[msg.sender].etherDebt, block.number);
        return (totalTime, amountToPay);
    }

    function getLog(uint index) public view returns(address, uint, uint, uint){
        Log memory temp = Logs[msg.sender][index];
        return (msg.sender, temp.carId, temp.time, temp.amount);
    }

    function damageStateTransition(uint _carId) public onlyOwner{
        if (Cars[_carId].damage){
            Cars[_carId].damage = false;
        }
        else{
            Cars[_carId].damage = true;
        }
    }

    //functions for testing     

    function getDebt(address customer) public view returns (uint) {
        return Customers[customer].etherDebt;
    }
    
    function getEtherAccountBalance(address customer) public view returns (uint) {
        return Customers[customer].etherBalance;
    }

    function getEtherAccountBalanceinEther() public view returns (uint) {
        return Customers[msg.sender].etherBalance/1000000000000000000;
    }

    function getTokenAccountBalance(address customer) public view returns (uint) {
        return Customers[customer].tokenBalance;
    }
    
    function getContractTokenBalance() public view returns(uint){
        return token.balanceOf(address(this));
    }

    function getOwnership() public view returns (bool) {
        return msg.sender == owner;
    }

    function getCustomerStatus() public view onlyCustomer returns(string memory, uint, uint){
        require(Customers[msg.sender].existence, "Customer not exist");
        Customer memory temp = Customers[msg.sender];
        string memory rent;
        uint cid = temp.carId;
        if (temp.isRenting){
            rent = "Is Renting";
        }
        else{
            rent = "Not Renting";
        }
        return (rent, cid, temp.startTime);
    }
}