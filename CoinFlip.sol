pragma solidity ^0.4.25;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {
    int256 constant private INT256_MIN = -2**255;

    /**
    * @dev Multiplies two unsigned integers, reverts on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
    * @dev Multiplies two signed integers, reverts on overflow.
    */
    function mul(int256 a, int256 b) internal pure returns (int256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        require(!(a == -1 && b == INT256_MIN)); // This is the only case of overflow not detected by the check below

        int256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
    * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
    * @dev Integer division of two signed integers truncating the quotient, reverts on division by zero.
    */
    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != 0); // Solidity only automatically asserts when dividing by 0
        require(!(b == -1 && a == INT256_MIN)); // This is the only case of overflow

        int256 c = a / b;

        return c;
    }

    /**
    * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
    * @dev Subtracts two signed integers, reverts on overflow.
    */
    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a));

        return c;
    }

    /**
    * @dev Adds two unsigned integers, reverts on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
    * @dev Adds two signed integers, reverts on overflow.
    */
    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a));

        return c;
    }

    /**
    * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
    * reverts when dividing by zero.
    */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

contract TheBetCoinFlip {
    using SafeMath for uint256;

    enum GameState {
        Pending,
        Starting
    }

    uint256 constant public FEE_PERCENT = 10;
    uint256 constant public MIN_BET = 0.01 ether;
    uint256 constant public HEADS = 0;
    uint256 constant public TAILS = 1;
    uint256 constant public ROUND_TIME = 180; // 3 Minutes
    uint256 constant public FINALIZE_WAIT_DURATION = 60; // 60 Seconds
    // 15 seconds on Ethereum, 12 seconds used instead to make sure blockHash unavaiable
    // when slideEndTime reached
    // keyBlockNumber will be estimated again after every slot buy
    uint256 constant public BLOCK_TIME = 12;
    uint256 constant public MAX_BLOCK_DISTANCE = 254;

    uint256 public amountHeads = 0;
    uint256 public totalGamblerHeads = 0;
    uint256 public amountTails = 0;
    uint256 public totalGamblerTails = 0;
    uint256 public round = 1;

    uint256 public roundTime = 0;
    uint256 public startTime = 0;
    uint256 public slideEndTime = 0;
    uint256 public keyBlockNr;
    address public dealer;

    GameState public state = GameState.Pending;

    // A structure representing a single bet
    struct Bet {
        // Wager amount in wei
        uint256 amount;
        // Number choose bet
        uint256 betNumber;
        // Address of a gambler, used to pay out winning bets
        address gambler;
    }

    // Array from comits to all currently active & processed bets
    Bet[] public bets;

    event Commit(address _gambler, uint256 _betNumber, uint256 _amount);
    event Finalize(uint256 _luckyNumber);
    event Winner(address _gambler, uint256 _amount);
    event StartGame(uint256 _round, uint256 _startTime, uint256 _slideEndTime);

    constructor() public {
        dealer = msg.sender;
    }

    // Throws if called by any account other than the dealer.
    modifier onlyDealer() {
        require(msg.sender == dealer);
        _;
    }

    function setRoundTime(uint256 _time) external onlyDealer() {
        roundTime = _time;
    }

    function betable() public view returns(bool) {
        if (block.timestamp > startTime && block.timestamp < slideEndTime) {
            return true;
        }
        return false;
    }

    // Betting logic
    function placeBet(uint256 _number) external payable {
        uint256 amount = msg.value;
        require(amount >= MIN_BET, "Amount should be more than minimum");

        if (state == GameState.Starting) {
            require(betable(), "Not allow gambler bet");
        }

        bets.push(Bet({
            amount: amount,
            betNumber: _number,
            gambler: msg.sender
        }));

        if (_number == HEADS) {
            amountHeads = amountHeads.add(amount);
            totalGamblerHeads = totalGamblerHeads.add(1);
        } else {
            amountTails = amountTails.add(amount);
            totalGamblerTails = totalGamblerTails.add(1);
        }

        emit Commit(msg.sender, _number, amount);

        if (amountHeads > 0 && amountTails > 0 && state == GameState.Pending) {
            state = GameState.Starting;
            startTime = block.timestamp;
            slideEndTime = startTime.add(ROUND_TIME);
            keyBlockNr = genEstKeyBlockNr(slideEndTime);

            emit StartGame(round, startTime, slideEndTime);
        }
    }

    function finalizeable() public view returns(bool) {
        uint256 finalizeTime = FINALIZE_WAIT_DURATION.add(slideEndTime);

        if (finalizeTime > block.timestamp) return false; // too soon to finalize
        if (keyBlockNr >= block.number) return false; //block hash not exist
        if (state != GameState.Starting) return false;
        return true;
    }

    function getKeyBlockNr(uint256 _estKeyBlockNr) public view returns(uint256) {
        require(block.number > _estKeyBlockNr, "blockHash not avaiable");
        uint256 jump = block.number.sub( _estKeyBlockNr).div(MAX_BLOCK_DISTANCE.mul(MAX_BLOCK_DISTANCE));
        return _estKeyBlockNr.add(jump);
    }

    // get block hash of first block with blocktime > _endTime
    function getSeed(uint256 _keyBlockNr) public view returns (uint256) {
        // Key Block not mined atm
        if (block.number <= _keyBlockNr) return block.number;
        return uint256(blockhash(_keyBlockNr));
    }

    // Only dealer can finalizeGame
    function finalizeGame() public payable {
        require(finalizeable(), "Not ready to draw results");

        uint256 keyBlockNrFinal = getKeyBlockNr(keyBlockNr);
        uint256 _seed = getSeed(keyBlockNrFinal);

        uint256 luckyNumber = getLuckyNumber(_seed);
        uint256 amountWin;
        uint256 amountReturn;

        // Calulate total amount win in round
        if (luckyNumber == HEADS) {
            amountWin = amountTails;
            amountReturn = amountHeads;
        } else {
            amountWin = amountHeads;
            amountReturn = amountTails;
        }

        // Calulate fee tranfer to dealer
        uint256 fee = amountWin.mul(FEE_PERCENT).div(100);
        dealer.transfer(fee);
        amountWin = amountWin.sub(fee);

        // Calulate amount win for each gambler
        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].betNumber == luckyNumber) {
                uint256 amount = bets[i].amount.mul(100).div(amountReturn).mul(amountWin).div(100).add(bets[i].amount);
                bets[i].gambler.transfer(amount);

                emit Winner(bets[i].gambler, amount);
            }
        }

        emit Finalize(luckyNumber);
        round.add(1);
        delete bets;
        totalGamblerHeads = 0;
        totalGamblerTails = 0;
        amountHeads = 0;
        amountTails = 0;
        state = GameState.Pending;
    }

    // Key Block in future
    function genEstKeyBlockNr(uint256 _endTime) public view returns(uint256) {
        if (block.timestamp >= _endTime) return block.number.add(8);
        uint256 timeDist = _endTime.sub(block.timestamp);
        uint256 estBlockDist = timeDist.div(BLOCK_TIME);
        return block.number.add(estBlockDist).add(8);
    }

    // Get random 1 | 0
    function getLuckyNumber(uint256 _seed) public pure returns(uint256) {
        return (_seed % 2);
    }
}
