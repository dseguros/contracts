pragma solidity ^0.5.11;

import './AccountFrozenBalances.sol';
import './Ownable.sol';
import './Whitelisted.sol';
import './Burnable.sol';
import './Pausable.sol';
import './Mintable.sol';
import './Meltable.sol';
import "./Rules.sol";
import "./TokenRecipient.sol";

contract DifsToken is AccountFrozenBalances, Ownable, Whitelisted, Burnable, Pausable, Mintable, Meltable {
    using SafeMath for uint256;
    using Rules for Rules.Rule;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupplyLimit;


    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private _totalSupply;

    enum RoleType { Invalid, FUNDER, DEVELOPER, MARKETER, COMMUNITY, SEED }

    struct FreezeData {
        bool initialzed;
        uint256 frozenAmount;       // fronzen amount
        uint256 startBlock;         // freeze block for start.
        uint256 lastFreezeBlock;
    }

    mapping (address => RoleType) private _roles;
    mapping (uint256 => Rules.Rule) private _rules;
    mapping (address => FreezeData) private _freeze_datas;
    uint256 public monthIntervalBlock = 172800;    
    uint256 public yearIntervalBlock = 2102400;    

    bool public seedPause = true;
    uint256 public seedMeltStartBlock = 0;       

    bool public ruleReady;

    modifier onlyReady(){
        require(ruleReady, "ruleReady is false");
        _;
    }            

    modifier canClaim() {
        require(uint256(_roles[msg.sender]) != uint256(RoleType.Invalid), "Invalid user role");
        require(_freeze_datas[msg.sender].initialzed);
        if(_roles[msg.sender] == RoleType.SEED){
            require(!seedPause, "Seed is not time to unlock yet");
        }
        _;
    }


    modifier canTransfer() {
        if(paused()){
            require (isWhitelisted(msg.sender) == true, "can't perform an action");
        }
        _;
    }

    modifier canMint(uint256 _amount) {
        require((_totalSupply + _amount) <= totalSupplyLimit, "Mint: Exceed the maximum circulation");
        _;
    }

    modifier canBatchMint(uint256[] memory _amounts) {
        uint256 mintAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintAmount = mintAmount.add(_amounts[i]);
        }
        require(mintAmount <= totalSupplyLimit, "BatchMint: Exceed the maximum circulation");
        _;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event Freeze(address indexed from, uint256 amount);
    event Melt(address indexed from, uint256 amount);
    event MintFrozen(address indexed to, uint256 amount);
    event FrozenTransfer(address indexed from, address indexed to, uint256 value);
    event Claim(address indexed from, uint256 amount);

    constructor (string memory _name, string memory _symbol, uint8 _decimals) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupplyLimit = 1024 * 1024 * 1024 * 10 ** uint256(decimals);
        //mint(msg.sender, 0);
        ruleReady = false;
    }

    function readyRule() onlyOwner public {
        ruleReady = true;
        _rules[uint256(RoleType.FUNDER)].setRule(yearIntervalBlock, 10);
        _rules[uint256(RoleType.DEVELOPER)].setRule(monthIntervalBlock, 2);
        _rules[uint256(RoleType.MARKETER)].setRule(monthIntervalBlock, 1);
        _rules[uint256(RoleType.COMMUNITY)].setRule(monthIntervalBlock, 10);
        _rules[uint256(RoleType.SEED)].setRule(monthIntervalBlock, 10);
    }

    function roleType(address account) public view returns (uint256) {
        return uint256(_roles[account]);
    }

    function startBlock(address account) public view returns (uint256) {
        return _freeze_datas[account].startBlock;
    }

    function lastestFreezeBlock(address account) public view returns (uint256) {
        return _freeze_datas[account].lastFreezeBlock;
    }

    function freezeAmount(address account) public view returns(uint256) {
        uint256 lastFreezeBlock = _freeze_datas[account].lastFreezeBlock;
        if(uint256(_roles[account]) == uint256(RoleType.SEED)) {
            require(!seedPause, "seed pause is true, can't to claim");
            if(seedMeltStartBlock != 0 && seedMeltStartBlock > lastFreezeBlock) {
                lastFreezeBlock = seedMeltStartBlock;
            }
        }
        uint256 amount = _rules[uint256(_roles[account])].freezeAmount(_freeze_datas[account].frozenAmount , _freeze_datas[account].startBlock, lastFreezeBlock, block.number);
        if(amount > _frozen_balanceOf(msg.sender)) {
            amount = _frozen_balanceOf(msg.sender);
        }
        return amount;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account].add(_frozen_balanceOf(account));
    }

    function frozenBalanceOf(address account) public view returns (uint256) {
        return _frozen_balanceOf(account);
    }

    function transfer(address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool) {
        TokenRecipient spender = TokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(address sender, address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }


    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }


    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
        return true;
    }

    function mint(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(uint256 amount) public whenBurn {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public whenBurn {
        _burnFrom(account, amount);
    }

    function destroy(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function destroyFrozen(address account, uint256 amount) public onlyOwner {
        _burnFrozen(account, amount);
    }

    function mintBatchToken(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchToken: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchToken: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mint(accounts[i], amounts[i]);
        }

        return true;
    }

    function transferFrozenToken(address from, address to, uint256 amount) public onlyOwner returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _frozen_sub(from, amount);
        _frozen_add(to, amount);

        emit FrozenTransfer(from, to, amount);
        emit Transfer(from, to, amount);

        return true;
    }

    function freezeTokens(address account, uint256 amount) public onlyOwner returns (bool) {
        _freeze(account, amount);
        emit Transfer(account, address(this), amount);
        return true;
    }

    function meltTokens(address account, uint256 amount) public onlyMelter returns (bool) {
        _melt(account, amount);
        emit Transfer(address(this), account, amount);
        return true;
    }

    function mintFrozenTokens(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mintfrozen(account, amount);
        return true;
    }

    function mintBatchFrozenTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintfrozen(accounts[i], amounts[i]);
        }

        return true;
    }

    function mintFrozenTokensForFunder(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Funder: specified account already initialzed");
        _roles[account] = RoleType.FUNDER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForDeveloper(address account, uint256 amount) public onlyMinter  onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Developer: specified account already initialzed");
        _roles[account] = RoleType.DEVELOPER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForMarketer(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Marketer: specified account already initialzed");
        _roles[account] = RoleType.MARKETER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForCommunity(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Community: specified account already initialzed");
        _roles[account] = RoleType.COMMUNITY;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForSeed(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Seed: specified account already initialzed");
        _roles[account] = RoleType.SEED;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function meltBatchTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMelter returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _melt(accounts[i], amounts[i]);
            emit Transfer(address(this), accounts[i], amounts[i]);
        }

        return true;
    }

    function claimTokens() public canClaim returns (bool) {
        //Rules.Rule storage rule = _rules[uint256(_roles[msg.sender])];
        uint256 lastFreezeBlock = _freeze_datas[msg.sender].lastFreezeBlock;
        if(uint256(_roles[msg.sender]) == uint256(RoleType.SEED)) {
            require(!seedPause, "seed pause is true, can't to claim");
            if(seedMeltStartBlock != 0 && seedMeltStartBlock > lastFreezeBlock) {
                lastFreezeBlock = seedMeltStartBlock;
            }
        }
        uint256 amount = _rules[uint256(_roles[msg.sender])].freezeAmount(_freeze_datas[msg.sender].frozenAmount, _freeze_datas[msg.sender].startBlock, lastFreezeBlock, block.number);
        require(amount > 0, "Melt amount must be greater than 0");
        // border amount
        if(amount > _frozen_balanceOf(msg.sender)) {
            amount = _frozen_balanceOf(msg.sender);
        }
        _melt(msg.sender, amount); 

        _freeze_datas[msg.sender].lastFreezeBlock = block.number;

        emit Claim(msg.sender, amount);
        return true;
    }

    function startSeedPause() onlyOwner public {
        seedPause = false;
        seedMeltStartBlock = block.number;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }


    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        require(account != address(this), "ERC20: mint to the contract address");
        require(amount > 0, "ERC20: mint amount should be > 0");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(this), account, amount);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _totalSupply = _totalSupply.sub(value);
        _balances[account] = _balances[account].sub(value);
        emit Transfer(account, address(this), value);
    }

    function _approve(address _owner, address spender, uint256 value) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][spender] = value;
        emit Approval(_owner, spender, value);
    }

    function _burnFrom(address account, uint256 amount) internal {
        _burn(account, amount);
        _approve(account, msg.sender, _allowances[account][msg.sender].sub(amount));
    }

    function _freeze(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: freeze from the zero address");
        require(amount > 0, "ERC20: freeze from the address: amount should be > 0");

        _balances[account] = _balances[account].sub(amount);
        _frozen_add(account, amount);

        emit Freeze(account, amount);
    }

    function _mintfrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint frozen to the zero address");
        require(account != address(this), "ERC20: mint frozen to the contract address");
        require(amount > 0, "ERC20: mint frozen amount should be > 0");

        _totalSupply = _totalSupply.add(amount);

        emit Transfer(address(this), account, amount);

        _frozen_add(account, amount);

        emit MintFrozen(account, amount);
    }

    function _melt(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: melt from the zero address");
        require(amount > 0, "ERC20: melt from the address: value should be > 0");
        require(_frozen_balanceOf(account) >= amount, "ERC20: melt from the address: balance < amount");

        _frozen_sub(account, amount);
        _balances[account] = _balances[account].add(amount);

        emit Melt(account, amount);
    }

    function _burnFrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: frozen burn from the zero address");

        _totalSupply = _totalSupply.sub(amount);
        _frozen_sub(account, amount);

        emit Transfer(account, address(this), amount);
    }
}