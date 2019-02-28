pragma solidity ^0.4.25;

contract TheBetCoinFlip {
    enum GameState {
        Pending,
        Starting
    }

    uint256 constant FEE_PERCENT = 10;
    uint256 constant MIN_BET = 0.01 ether;
    uint256 constant HEADS = 0;
    uint256 constant TAILS = 1;
    uint256 constant ROUND_TIME = 10; // 5 minutes

    uint256 public amountHeads = 0;
    uint256 public totalGamblerHeads = 0;
    uint256 public amountTails = 0;
    uint256 public totalGamblerTails = 0;
    uint256 public round = 1;
    uint256 public roundTime = 0;
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
    event StartGame(uint256 _round);

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

    // Betting logic
    function placeBet(uint256 _number) external payable {
        uint256 amount = msg.value;
        require(amount >= MIN_BET, "Amount should be more than minimum");

        bets.push(Bet({
            amount: amount,
            betNumber: _number,
            gambler: msg.sender
        }));

        if (_number == HEADS) {
            amountHeads += amount;
            totalGamblerHeads++;
        } else {
            amountTails += amount;
            totalGamblerTails++;
        }

        emit Commit(msg.sender, _number, amount);

        if (amountHeads > 0 && amountTails > 0 && state == GameState.Pending) {
            state = GameState.Starting;
            roundTime += (now + ROUND_TIME);
            emit StartGame(round);
        }
    }

    // Only dealer can finalizeGame
    function finalizeGame() public payable {
        require(totalGamblerHeads > 0, "No player choose Heads");
        require(totalGamblerTails > 0, "No player choose Tails");
        require(amountHeads > 0, "Amount need to be more than 0");
        require(amountTails > 0, "Amount need to be more than 0");
        require(state == GameState.Starting);

        if (msg.sender != dealer && roundTime > now) {
            revert();
        }

        uint256 luckyNumber = generateLuckyNumber();
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
        uint256 fee = (amountWin * FEE_PERCENT) / 100;
        dealer.transfer(fee);
        amountWin = amountWin - fee;

        // Calulate amount win for each gambler
        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].betNumber == luckyNumber) {
                uint256 amount = ((((bets[i].amount * 100) / amountReturn) * amountWin) / 100) + bets[i].amount;
                bets[i].gambler.transfer(amount);

                emit Winner(bets[i].gambler, amount);
            }
        }

        emit Finalize(luckyNumber);
        round++;
        delete bets;
        totalGamblerHeads = 0;
        totalGamblerTails = 0;
        amountHeads = 0;
        amountTails = 0;
        state = GameState.Pending;
    }

    function maxRandom() private returns (uint256 number) {
        return uint256(keccak256(
            block.blockhash(block.number - 1),
            block.coinbase,
            block.difficulty,
            bets.length
        ));
    }

    // Generate 1 | 0
    function generateLuckyNumber() private returns (uint256 number) {
        return (maxRandom() % 2);
    }
}
