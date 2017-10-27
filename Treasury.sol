pragma solidity ^0.4.11;


contract Callisto_treasury
{
    
    event VoterWeight(address indexed _owner, uint256 _amount);
    event ProposalCreated(bytes32 indexed _signature);
    
    enum Mode { inactive, active, currently_voted, rejected }
    
    struct proposal
    {
        bool    voting;             // is the proposal currently in voting statge or not.
        uint256 start_time;         // timestamp of the proposal start.
        string  source;             // humanising variable, link or proposal
                                    // explanation text.
        
        uint256 vote_end;           // timestamp of the voting end.
        uint256 vote_YES;           // total YES votes weight.
        uint256 vote_NO;            // total NO votes weight.
        
        uint256 funding_end;         // duration of the work.
        uint256 funding_amount;      // monthly amount of funding.
        address funding_destination; // the address that will receive funding.
        uint256 funding_withdrawn;   // the amount that was already withdrawn.
        
        mapping (address => bool) voted;
    }
    
    struct voter
    {
        uint256 allowed_withdrawal_time;
        uint256 balance;
        uint256 autoconfirm_endtime;
    }
    
    mapping (bytes32 => proposal) public proposals;
    mapping (address => voter) public voters;
    uint256 public total_vote_weight;
    uint256 public voting_duration;
    uint256 public min_voterate = 35;
    
    function() payable
    {
        deposited(msg.sender, msg.value);
    }
    
    // Internal functions.
    
    function deposited(address _owner, uint256 _amount) private
    {
        voters[msg.sender].autoconfirm_endtime = now + 30 days;
        voters[msg.sender].balance += _amount;
        total_vote_weight += _amount;
        
        VoterWeight(_owner, voters[_owner].balance);
    }
    
    function extracted(address _owner, uint256 _amount) private
    {
        voters[msg.sender].balance -= _amount;
        total_vote_weight -= _amount;
        
        VoterWeight(_owner, voters[_owner].balance);
    }
    
    function is_voter(address _addr) private returns (bool)
    {
        return (voters[_addr].balance > 0);
    }
    
    // Ordinaty functions.
    
    function deposit() external payable
    {
        deposited(msg.sender, msg.value);
    }
    
    function withdraw_deposit() external
    {
        msg.sender.transfer(voters[msg.sender].balance);
        extracted(msg.sender, voters[msg.sender].balance);
    }
    
    function withdraw_deposit(uint256 _amount) external
    {
        assert(_amount >= voters[msg.sender].balance);
        assert(voters[msg.sender].allowed_withdrawal_time >= now);
        msg.sender.transfer(_amount);
        extracted(msg.sender, _amount);
    }
    
    function refund(address _destination) external
    {
        assert(voters[_destination].autoconfirm_endtime < now);
        
        extracted(_destination, voters[_destination].balance);
        _destination.transfer(voters[_destination].balance);
    }
    
    // Proposals functions.
    
    function create_proposal(address _destination, uint256 _funding_monthly, uint256 _duration) external
    {
        assert(is_voter(msg.sender) && _destination != 0x0 && _duration > now);
        
        bytes32 _sig = sha256(now, _destination, _funding_monthly, _duration);
        
        // assign proposal.
        proposals[_sig].start_time          = now;
        proposals[_sig].funding_destination = _destination;
        proposals[_sig].funding_end         = now + _duration;
        proposals[_sig].funding_amount      = _funding_monthly;
        proposals[_sig].voting              = true;
        proposals[_sig].vote_end            = now + voting_duration;
    }
    
    function vote(bytes32 _id, bool _YES) external only_voting(_id)
    {
        assert(voters[msg.sender].balance > 0 && !proposals[_id].voted[msg.sender]);
        proposals[_id].voted[msg.sender] = true;
        
        /* If the voter can withdraw funds earlier than the results
           of the proposal will be evaluated,
           we must retain the funds to prevent the voter
           from voting with multiple addresses with his funds.
        */
        if(voters[msg.sender].allowed_withdrawal_time < proposals[_id].vote_end)
        {
            voters[msg.sender].allowed_withdrawal_time = proposals[_id].vote_end;
        }
        
        if(_YES)
        {
            proposals[_id].vote_YES += voters[msg.sender].balance;
        }
        else
        {
            proposals[_id].vote_NO  += voters[msg.sender].balance;
        }
    }
    
    function evaluate_proposal(bytes32 _id) external only_voting(_id)
    {
        assert(proposals[_id].vote_end < now);
        
        if(proposals[_id].vote_YES > ( min_voterate * total_vote_weight / 100 ) 
        && ( proposals[_id].vote_NO < proposals[_id].vote_YES ))
        {
            proposals[_id].voting = false; // consider the proposal approved.
        }
        else
        {
            proposals[_id].voting = false;
            proposals[_id].funding_amount = 0; // zero funding allowed.
        }
    }
    
    function withdraw_funding(bytes32 _id) not_voting(_id)
    {
        if(now < proposals[_id].funding_end)
        {
            proposals[_id].funding_destination.transfer(
                (proposals[_id].funding_amount - proposals[_id].funding_withdrawn) *
                ( (now - proposals[_id].start_time) / 30 days )
                );
        }
        else
        {
            proposals[_id].funding_destination.transfer(
                (proposals[_id].funding_amount - proposals[_id].funding_withdrawn) *
                ( (proposals[_id].funding_end - proposals[_id].start_time) / 30 days )
                );
        }
        
    }
    
    modifier only_voting(bytes32 _sig)
    {
        assert(proposals[_sig].voting);
        _;
    }
    
    modifier not_voting(bytes32 _sig)
    {
        assert(!proposals[_sig].voting);
        _;
    }
}
