import React, { useState, useEffect, useRef } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useToast } from '@/components/ui/use-toast';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { aptosClient } from '@/utils/aptosClient';
import { 
  getRouletteViewFunctions,
  parseRouletteConfig,
  parseRoulettePayoutTable,
  placeRouletteBet,
  clearRouletteResult,
  parseRouletteResult,
  RouletteResult,
  RouletteConfig,
  RoulettePayoutTable,
} from '@/entry-functions/chaincasino';
import { formatAPT, GAMES_ADDRESS } from '@/constants/chaincasino';
import { RouletteWheel } from 'react-casino-roulette';
import 'react-casino-roulette/dist/index.css';

// Enhanced RetroCard component with hover effects
const RetroCard = ({ children, className = "", glowOnHover = false }: { 
  children: React.ReactNode; 
  className?: string;
  glowOnHover?: boolean;
}) => {
  const [isHovered, setIsHovered] = useState(false);
  
  return (
    <div 
      className={`retro-card transition-all duration-300 ${glowOnHover ? 'hover:shadow-[0_0_30px_rgba(0,195,255,0.4)]' : ''} ${className}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      style={{
        transform: isHovered && glowOnHover ? 'translateY(-5px)' : 'translateY(0)',
      }}
    >
      {children}
    </div>
  );
};

// Comprehensive bet selection type
type BetSelection = {
  type: 'straight' | 'red' | 'black' | 'even' | 'odd' | 'high' | 'low' | 'dozen' | 'column';
  betFlag: number;
  betValue: number;
  label: string;
  payout: string;
  numbers?: number[];
};

// Roulette number color helper
const getNumberColor = (num: number): 'red' | 'black' | 'green' => {
  if (num === 0) return 'green';
  const redNumbers = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];
  return redNumbers.includes(num) ? 'red' : 'black';
};

// Number grid component for straight bets
const NumberGrid = ({ 
  selectedNumber, 
  onNumberSelect, 
  disabled 
}: { 
  selectedNumber: number | null;
  onNumberSelect: (num: number) => void;
  disabled: boolean;
}) => {
  const numbers = Array.from({ length: 37 }, (_, i) => i); // 0-36

  return (
    <div className="bg-black/40 border border-cyan-400/30 rounded-lg p-4">
      <h4 className="text-cyan-400 font-bold mb-3 retro-terminal-font">Straight Up Bets (35:1)</h4>
      <div className="grid grid-cols-6 gap-1">
        {numbers.map(num => {
          const color = getNumberColor(num);
          const isSelected = selectedNumber === num;
          
          return (
            <Button
              key={num}
              onClick={() => onNumberSelect(num)}
              disabled={disabled}
              className={`
                h-10 w-10 text-sm font-bold transition-all duration-200
                ${color === 'red' ? 'bg-red-600 hover:bg-red-500 border-red-400' : ''}
                ${color === 'black' ? 'bg-gray-800 hover:bg-gray-700 border-gray-600' : ''}
                ${color === 'green' ? 'bg-green-600 hover:bg-green-500 border-green-400' : ''}
                ${isSelected ? 'ring-2 ring-yellow-400 scale-110' : ''}
                ${disabled ? 'opacity-50 cursor-not-allowed' : ''}
                border-2 text-white
              `}
            >
              {num}
            </Button>
          );
        })}
      </div>
    </div>
  );
};

// Statistics display component
const GameStats = ({ 
  lastResult, 
  history, 
  gameConfig 
}: { 
  lastResult: RouletteResult | null;
  history: number[];
  gameConfig: RouletteConfig | null;
}) => {
  const stats = {
    redCount: history.filter(n => getNumberColor(n) === 'red').length,
    blackCount: history.filter(n => getNumberColor(n) === 'black').length,
    evenCount: history.filter(n => n !== 0 && n % 2 === 0).length,
    oddCount: history.filter(n => n % 2 === 1).length,
  };

  return (
    <RetroCard className="p-4" glowOnHover>
      <h3 className="text-cyan-400 font-bold mb-3 retro-terminal-font">Game Statistics</h3>
      
      {lastResult && (
        <div className="bg-black/50 border border-purple-400/30 rounded p-3 mb-4">
          <div className="text-center">
            <div className="text-2xl font-bold text-yellow-400 mb-2">
              Last Spin: {lastResult.winning_number}
            </div>
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div>Color: <span className={`font-bold ${getNumberColor(lastResult.winning_number) === 'red' ? 'text-red-400' : getNumberColor(lastResult.winning_number) === 'black' ? 'text-gray-300' : 'text-green-400'}`}>
                {getNumberColor(lastResult.winning_number).toUpperCase()}
              </span></div>
              <div>Type: <span className="text-cyan-400">
                {lastResult.winning_number === 0 ? 'ZERO' : 
                 lastResult.winning_number % 2 === 0 ? 'EVEN' : 'ODD'}
              </span></div>
              <div>Wagered: <span className="text-yellow-400">{formatAPT(lastResult.total_wagered)}</span></div>
              <div>Payout: <span className={lastResult.net_result ? 'text-green-400' : 'text-red-400'}>
                {formatAPT(lastResult.total_payout)}
              </span></div>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 gap-3 text-sm">
        <div className="bg-red-900/30 border border-red-500/30 rounded p-2 text-center">
          <div className="text-red-400 font-bold">RED</div>
          <div className="text-white">{stats.redCount}/{history.length}</div>
        </div>
        <div className="bg-gray-900/30 border border-gray-500/30 rounded p-2 text-center">
          <div className="text-gray-300 font-bold">BLACK</div>
          <div className="text-white">{stats.blackCount}/{history.length}</div>
        </div>
        <div className="bg-blue-900/30 border border-blue-500/30 rounded p-2 text-center">
          <div className="text-blue-400 font-bold">EVEN</div>
          <div className="text-white">{stats.evenCount}/{history.length}</div>
        </div>
        <div className="bg-purple-900/30 border border-purple-500/30 rounded p-2 text-center">
          <div className="text-purple-400 font-bold">ODD</div>
          <div className="text-white">{stats.oddCount}/{history.length}</div>
        </div>
      </div>

      {gameConfig && (
        <div className="mt-4 text-xs text-gray-400 border-t border-gray-600 pt-3">
          <div>House Edge: {(gameConfig.house_edge_bps / 100).toFixed(2)}%</div>
          <div>Bet Range: {formatAPT(gameConfig.min_bet)} - {formatAPT(gameConfig.max_bet)}</div>
        </div>
      )}
    </RetroCard>
  );
};

const AptosRoulette = () => {
  const { account, connected, signAndSubmitTransaction } = useWallet();
  const { toast } = useToast();
  
  // Contract state
  const [gameConfig, setGameConfig] = useState<RouletteConfig | null>(null);
  const [payoutTable, setPayoutTable] = useState<RoulettePayoutTable | null>(null);
  const [lastResult, setLastResult] = useState<RouletteResult | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [configError, setConfigError] = useState<string | null>(null);

  // UI state
  const [betAmount, setBetAmount] = useState('');
  const [betSelection, setBetSelection] = useState<BetSelection | null>(null);
  const [selectedNumber, setSelectedNumber] = useState<number | null>(null);
  const [isSpinning, setIsSpinning] = useState(false);
  const [winningNumber, setWinningNumber] = useState<number | null>(null);
  const [history, setHistory] = useState<number[]>([]);
  const [showNumberGrid, setShowNumberGrid] = useState(false);
  
  // Result tracking state (like SevenOut)
  const [waitingForNewResult, setWaitingForNewResult] = useState(false);
  const [lastResultHash, setLastResultHash] = useState<string>('');

  // Available bet types
  const BET_TYPES: BetSelection[] = [
    { type: 'red', betFlag: 4, betValue: 1, label: 'Red', payout: '1:1', numbers: [1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36] },
    { type: 'black', betFlag: 4, betValue: 0, label: 'Black', payout: '1:1', numbers: [2,4,6,8,10,11,13,15,17,20,22,24,26,28,29,31,33,35] },
    { type: 'even', betFlag: 5, betValue: 1, label: 'Even', payout: '1:1', numbers: Array.from({length: 18}, (_, i) => (i + 1) * 2) },
    { type: 'odd', betFlag: 5, betValue: 0, label: 'Odd', payout: '1:1', numbers: Array.from({length: 18}, (_, i) => (i * 2) + 1) },
    { type: 'high', betFlag: 6, betValue: 1, label: '19-36', payout: '1:1', numbers: Array.from({length: 18}, (_, i) => i + 19) },
    { type: 'low', betFlag: 6, betValue: 0, label: '1-18', payout: '1:1', numbers: Array.from({length: 18}, (_, i) => i + 1) },
    { type: 'dozen', betFlag: 7, betValue: 1, label: '1st 12', payout: '2:1', numbers: Array.from({length: 12}, (_, i) => i + 1) },
    { type: 'dozen', betFlag: 7, betValue: 2, label: '2nd 12', payout: '2:1', numbers: Array.from({length: 12}, (_, i) => i + 13) },
    { type: 'dozen', betFlag: 7, betValue: 3, label: '3rd 12', payout: '2:1', numbers: Array.from({length: 12}, (_, i) => i + 25) },
    { type: 'column', betFlag: 8, betValue: 1, label: 'Col 1', payout: '2:1', numbers: [1,4,7,10,13,16,19,22,25,28,31,34] },
    { type: 'column', betFlag: 8, betValue: 2, label: 'Col 2', payout: '2:1', numbers: [2,5,8,11,14,17,20,23,26,29,32,35] },
    { type: 'column', betFlag: 8, betValue: 3, label: 'Col 3', payout: '2:1', numbers: [3,6,9,12,15,18,21,24,27,30,33,36] },
  ];

  // Load game configuration
  useEffect(() => {
    const loadGameConfig = async () => {
      if (!connected) {
        setIsLoading(false);
        return;
      }
      
      try {
        console.log('🎰 Loading AptosRoulette configuration...');
        setIsLoading(true);
        setConfigError(null);
        
        // Check if game is ready first
        const readyResponse = await aptosClient().view({
          payload: {
            function: getRouletteViewFunctions().isReady,
            functionArguments: []
          }
        });
        
        const gameIsReady = Boolean(readyResponse[0]);
        setIsReady(gameIsReady);
        
        if (!gameIsReady) {
          setConfigError('Game is not ready. Please ensure AptosRoulette is properly initialized.');
          setIsLoading(false); // ✅ Fix: Always clear loading state
          return;
        }
        
        // Load game config
        const configResponse = await aptosClient().view({
          payload: {
            function: getRouletteViewFunctions().gameConfig,
            functionArguments: []
          }
        });
        
        const config = parseRouletteConfig(configResponse);
        setGameConfig(config);
        
        // Load payout table
        const payoutResponse = await aptosClient().view({
          payload: {
            function: getRouletteViewFunctions().payoutTable,
            functionArguments: []
          }
        });
        
        const payouts = parseRoulettePayoutTable(payoutResponse);
        setPayoutTable(payouts);
        
        toast({
          title: "🎯 Roulette Ready!",
          description: "European Roulette table is ready for action!",
          variant: "default"
        });
        
      } catch (error) {
        console.error('❌ Failed to load game config:', error);
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        setConfigError(`Failed to load game configuration: ${errorMessage}`);
        
        toast({
          title: "Configuration Error",
          description: "Unable to load game configuration. Please try again.",
          variant: "destructive"
        });
      } finally {
        setIsLoading(false);
      }
    };
    
    loadGameConfig();
  }, [connected, toast]);

  // Check for existing results on mount
  useEffect(() => {
    const checkForResults = async () => {
      if (!connected || !account) return;
      
      try {
        const res = await aptosClient().view({
          payload: {
            function: `${GAMES_ADDRESS}::AptosRoulette::get_latest_result`,
            functionArguments: [account.address],
          },
        });

        const result = parseRouletteResult(res);
        if (result && result.total_wagered > 0) {
          setLastResult(result);
          setLastResultHash(JSON.stringify(result));  // Store hash for comparison
          setHistory(prev => [result.winning_number, ...prev.slice(0, 19)]);
        }
      } catch (error) {
        // No existing result, which is fine
        console.log('No existing results found');
      }
    };

    checkForResults();
  }, [connected, account]);

  // Handle bet placement
  const handlePlaceBet = async () => {
    if (!betSelection || !betAmount || !gameConfig) {
      toast({
        title: 'Invalid Bet',
        description: 'Please select a bet type and enter a valid amount.',
        variant: 'destructive',
      });
      return;
    }

    const amount = parseFloat(betAmount) * 100_000_000; // Convert to octas
    if (amount < gameConfig.min_bet || amount > gameConfig.max_bet) {
      toast({
        title: 'Invalid Amount',
        description: `Bet must be between ${formatAPT(gameConfig.min_bet)} and ${formatAPT(gameConfig.max_bet)} APT.`,
        variant: 'destructive',
      });
      return;
    }

    setWaitingForNewResult(true);
    // Don't start spinning until transaction is confirmed

    try {
      let payload;
      
      if (betSelection.type === 'straight' && selectedNumber !== null) {
        // Straight number bet
        payload = placeRouletteBet({
          betFlag: 0, // Straight up bet flag
          betValue: selectedNumber,
          betNumbers: [],
          amount: amount,
        });
      } else {
        // Other bet types
        payload = placeRouletteBet({
          betFlag: betSelection.betFlag,
          betValue: betSelection.betValue,
          betNumbers: [], // Not used for simple bets
          amount: amount,
        });
      }

      const result = await signAndSubmitTransaction(payload);
      await aptosClient().waitForTransaction({ transactionHash: result.hash });

      toast({
        title: '🎲 Bet Placed!',
        description: `${formatAPT(amount)} APT bet placed. Spinning the wheel...`,
      });

      // Start spinning wheel and checking for result after 1 second delay (like SevenOut)
      setTimeout(() => {
        setIsSpinning(true); // Start wheel spinning after transaction confirmation
        
        // Start polling for result every 2 seconds (like SevenOut)
        const pollInterval = setInterval(() => {
          checkForResult().then(() => {
            // Stop polling once we have a result
            if (!waitingForNewResult) {
              clearInterval(pollInterval);
            }
          });
        }, 2000);
        
        // Cleanup after 60 seconds max
        setTimeout(() => {
          clearInterval(pollInterval);
          if (waitingForNewResult) {
            setWaitingForNewResult(false);
            setIsSpinning(false);
            toast({
              title: 'Result Timeout',
              description: 'Could not fetch the game result. Please check manually.',
              variant: 'destructive'
            });
          }
        }, 60000);
      }, 1000);
    } catch (error) {
      console.error('❌ Bet failed:', error);
      toast({
        title: 'Bet Failed',
        description: 'There was an error placing your bet. Please try again.',
        variant: 'destructive',
      });
      setIsSpinning(false);
      setWaitingForNewResult(false);
    }
  };

  // Check for result (handling error gracefully when result doesn't exist)
  const checkForResult = async () => {
    if (!account) return;
    
    try {
      console.log('🔍 Checking for result...');
      
      // Try to get result directly - will fail if doesn't exist
      const res = await aptosClient().view({
        payload: {
          function: `${GAMES_ADDRESS}::AptosRoulette::get_latest_result`,
          functionArguments: [account.address]
        }
      });

      const newResult = parseRouletteResult(res);
      console.log('🎯 Result found:', newResult);
      
      // Check if this is a valid result with actual data
      if (newResult && newResult.total_wagered > 0) {
        const resultHash = JSON.stringify(newResult);
        
        // If this is a new result (different hash), process it
        if (resultHash !== lastResultHash) {
          console.log(`🆕 New result found!`);
          
          setLastResult(newResult);
          setLastResultHash(resultHash);
          setWinningNumber(newResult.winning_number);
          setWaitingForNewResult(false);

          const color = getNumberColor(newResult.winning_number);
          const resultText = `${newResult.winning_number} ${color.toUpperCase()}`;
          setHistory(prev => [newResult.winning_number, ...prev.slice(0, 19)]);

          // Continue spinning for 2 more seconds like SevenOut
          setTimeout(() => {
            console.log('🛑 Stopping roulette wheel...');
            setIsSpinning(false);
            setBetSelection(null);
            setSelectedNumber(null);
            setBetAmount('');
            
            if (newResult.net_result) {
              toast({ 
                title: '🎉 Winner!', 
                description: `${resultText}! You won ${formatAPT(newResult.total_payout)} APT!`,
                variant: "default"
              });
            } else {
              toast({ 
                title: '💸 House Wins', 
                description: `${resultText}. Better luck next time!`,
                variant: 'destructive' 
              });
            }
          }, 2000);
        } else {
          console.log('📡 Same result, still waiting for new result...');
        }
      } else {
        console.log('📡 Result exists but no valid data yet...');
      }
    } catch (error) {
      // This is expected when no result exists yet - not an error
      console.log('📡 No result yet (expected while waiting)...');
    }
  };

  // Quick bet amounts
  const getQuickBetAmounts = () => {
    if (!gameConfig) return [];
    const max = gameConfig.max_bet / 100_000_000; // Convert to APT
    return [
      { label: '10%', value: max * 0.1 },
      { label: '25%', value: max * 0.25 },
      { label: '50%', value: max * 0.5 },
      { label: 'MAX', value: max },
    ].filter(bet => bet.value >= gameConfig.min_bet / 100_000_000);
  };

  const quickBet = (value: number) => {
    setBetAmount(value.toFixed(3).replace(/\.?0+$/, ''));
  };

  const selectBet = (bet: BetSelection) => {
    setBetSelection(bet);
    setSelectedNumber(null);
    setShowNumberGrid(false);
  };

  const handleNumberSelect = (num: number) => {
    setSelectedNumber(num);
    setBetSelection({
      type: 'straight',
      betFlag: 0,
      betValue: num,
      label: `Number ${num}`,
      payout: '35:1'
    });
    setShowNumberGrid(false);
  };

  // Clear current bet selection
  const clearBet = () => {
    setBetSelection(null);
    setSelectedNumber(null);
    setBetAmount('');
  };

  // Wallet connection guard
  if (!connected) {
    return (
      <div className="retro-body min-h-screen relative">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div className="container mx-auto px-4 py-8 relative z-10 flex items-center justify-center min-h-screen">
          <div className="retro-terminal max-w-md mx-auto animate-pulse">
            <div className="retro-terminal-header">/// WALLET CONNECTION REQUIRED ///</div>
                          <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">ROULETTE:&gt;</span>
                <span>Connect wallet to access European roulette</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">STATUS:&gt;</span>
                <span className="text-red-400">DISCONNECTED</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">ACTION:&gt;</span>
                <span className="text-cyan-400">Please connect your Aptos wallet</span>
              </div>
          </div>
        </div>
      </div>
    );
  }

  // Loading state
  if (isLoading) {
    return (
      <div className="retro-body min-h-screen relative">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div className="container mx-auto px-4 py-8 relative z-10 flex items-center justify-center min-h-screen">
          <div className="retro-terminal max-w-md mx-auto">
            <div className="retro-terminal-header">/// INITIALIZING ROULETTE TABLE ///</div>
                          <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">INIT:&gt;</span>
                <span className="animate-pulse">Loading European roulette configuration...</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">STATUS:&gt;</span>
                <span className="text-yellow-400 animate-pulse">CONNECTING TO CASINO NETWORK</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">PLEASE:&gt;</span>
                <span className="text-cyan-400">Wait for table initialization</span>
              </div>
          </div>
        </div>
      </div>
    );
  }

  // Error state
  if (configError || !isReady) {
    return (
      <div className="retro-body min-h-screen relative">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div className="container mx-auto px-4 py-8 relative z-10 flex items-center justify-center min-h-screen">
          <div className="retro-terminal max-w-lg mx-auto">
            <div className="retro-terminal-header">/// ROULETTE TABLE ERROR ///</div>
                          <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">ERROR:&gt;</span>
                <span className="text-red-400">Table initialization failed</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">REASON:&gt;</span>
                <span className="text-gray-300">{configError || 'Game not ready - check deployment'}</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">ACTION:&gt;</span>
                <span className="text-cyan-400">Contact casino administrator</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">STATUS:&gt;</span>
                <span className="text-red-400">OFFLINE</span>
              </div>
          </div>
        </div>
      </div>
    );
  }

  // Main game interface
  return (
    <div className="retro-body min-h-screen relative">
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      <div className="container mx-auto px-4 py-8 relative z-10">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-6xl font-bold text-transparent bg-gradient-to-r from-red-400 via-yellow-400 to-green-400 bg-clip-text mb-4 retro-pixel-font animate-pulse">
            🎯 EUROPEAN ROULETTE 🎯
          </h1>
          <p className="text-cyan-400 text-xl retro-terminal-font">
            {(gameConfig?.house_edge_bps || 270) / 100}% HOUSE EDGE • SINGLE ZERO • {payoutTable?.single || 35}:1 MAX PAYOUT
          </p>
        </div>

        {/* Status Bar */}
        <div className="bg-black/40 border border-cyan-400/30 rounded-lg p-3 mb-8">
          <div className="flex items-center justify-center gap-4 text-sm flex-wrap">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-green-400 font-bold">TABLE ACTIVE</span>
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-yellow-400">
              💰 Range: {formatAPT(gameConfig?.min_bet || 0)} - {formatAPT(gameConfig?.max_bet || 0)} APT
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-purple-400">
              📊 History: {history.length} spins
            </div>
            {lastResult && (
              <>
                <div className="text-gray-400">•</div>
                <div className={`font-bold ${getNumberColor(lastResult.winning_number) === 'red' ? 'text-red-400' : 
                  getNumberColor(lastResult.winning_number) === 'black' ? 'text-gray-300' : 'text-green-400'}`}>
                  Last: {lastResult.winning_number} {getNumberColor(lastResult.winning_number).toUpperCase()}
                </div>
              </>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-4 gap-6">
          {/* Left Column: Roulette Wheel */}
          <div className="xl:col-span-2">
            <RetroCard className="p-6" glowOnHover>
              <div className="text-center mb-4">
                <h3 className="text-2xl text-yellow-400 font-bold retro-terminal-font">
                  {waitingForNewResult ? '⏳ WAITING FOR RESULT...' : 
                   isSpinning ? '🌀 SPINNING...' : 
                   '🎲 PLACE YOUR BETS'}
                </h3>
              </div>
              
              <div className="flex justify-center items-center h-[400px] bg-black/30 border border-purple-400/30 rounded-lg overflow-hidden">
                {/* Roulette Wheel with error boundary */}
                <div className="w-full h-full flex items-center justify-center">
                  <RouletteWheel
                    start={isSpinning}
                    winningBet={winningNumber !== null ? String(winningNumber) : "0"}
                    onSpinningEnd={() => {
                      console.log('🎡 Wheel animation completed');
                    }}
                    withAnimation={true}
                    addRest={true}
                  />
                </div>
            </div>

              {/* Recent History */}
              <div className="mt-6">
                <h4 className="text-cyan-400 font-bold mb-3 retro-terminal-font">Recent Results</h4>
                <div className="flex gap-2 bg-black/50 border border-gray-600/30 p-3 rounded-md overflow-x-auto">
                  {history.length > 0 ? history.slice(0, 15).map((num, i) => {
                    const color = getNumberColor(num);
                    return (
                      <div key={i} className={`
                        min-w-[32px] h-8 flex items-center justify-center rounded-full text-white font-bold text-sm border-2
                        ${color === 'red' ? 'bg-red-600 border-red-400' : ''}
                        ${color === 'black' ? 'bg-gray-800 border-gray-600' : ''}
                        ${color === 'green' ? 'bg-green-600 border-green-400' : ''}
                        ${i === 0 ? 'ring-2 ring-yellow-400' : ''}
                      `}>
                        {num}
            </div>
                    );
                  }) : (
                    <span className="text-gray-500 italic">No recent spins - be the first to play!</span>
                  )}
            </div>
            </div>
            </RetroCard>
          </div>

          {/* Middle Column: Betting Interface */}
          <div className="xl:col-span-1">
            <RetroCard className="p-6" glowOnHover>
              <h3 className="text-2xl text-yellow-400 font-bold mb-4 retro-terminal-font">Place Your Bet</h3>
              
              {/* Current Bet Display */}
              {betSelection && (
                <div className="bg-purple-900/30 border border-purple-400/50 rounded-lg p-3 mb-4">
                  <div className="text-center">
                    <div className="text-lg font-bold text-yellow-400">{betSelection.label}</div>
                    <div className="text-cyan-400">Payout: {betSelection.payout}</div>
                    {betSelection.numbers && (
                      <div className="text-xs text-gray-400 mt-1">
                        Numbers: {betSelection.numbers.slice(0, 6).join(', ')}{betSelection.numbers.length > 6 ? '...' : ''}
                      </div>
                    )}
              </div>
            </div>
          )}
              
              {/* Bet Amount */}
              <div className="mb-6">
                <label className="text-cyan-400 block mb-2 font-bold">Amount (APT)</label>
                <Input
                  type="number"
                  step="0.001"
                  value={betAmount}
                  onChange={(e) => setBetAmount(e.target.value)}
                  placeholder={gameConfig ? `Min ${formatAPT(gameConfig.min_bet)}` : '0.001'}
                  className="bg-black/50 border-cyan-400/50 text-white placeholder-gray-500"
                  disabled={isSpinning || waitingForNewResult}
                />
                
                {/* Quick Bet Buttons */}
                <div className="flex gap-2 mt-3">
                  {getQuickBetAmounts().map(({ label, value }) => (
                    <Button
                      key={label}
                      onClick={() => quickBet(value)}
                      variant="outline"
                      size="sm"
                      className="flex-1 bg-black/30 border-cyan-400/50 text-cyan-400 hover:bg-cyan-400/20"
                      disabled={isSpinning || waitingForNewResult}
                    >
                      {label}
                    </Button>
                  ))}
                </div>
              </div>

              {/* Bet Type Selection */}
              <div className="space-y-4">
                {/* Even Money Bets */}
                <div>
                  <p className="text-cyan-400 font-bold mb-2">Even Money Bets (1:1)</p>
                  <div className="grid grid-cols-2 gap-2">
                    {BET_TYPES.filter(bet => bet.payout === '1:1').map((bet) => (
                      <Button
                        key={`${bet.type}-${bet.betValue}`}
                        onClick={() => selectBet(bet)}
                        variant={betSelection?.type === bet.type && betSelection?.betValue === bet.betValue ? "default" : "outline"}
                        className={`
                          text-sm py-2 transition-all duration-200
                          ${bet.type === 'red' ? 'bg-red-600/80 hover:bg-red-500 border-red-400' : ''}
                          ${bet.type === 'black' ? 'bg-gray-800/80 hover:bg-gray-700 border-gray-600' : ''}
                          ${betSelection?.type === bet.type && betSelection?.betValue === bet.betValue ? 'ring-2 ring-yellow-400' : ''}
                        `}
                        disabled={isSpinning || waitingForNewResult}
                      >
                        {bet.label}
                      </Button>
                    ))}
                  </div>
                </div>

                {/* Column and Dozen Bets */}
                <div>
                  <p className="text-cyan-400 font-bold mb-2">Column & Dozen Bets (2:1)</p>
                  <div className="grid grid-cols-3 gap-1">
                    {BET_TYPES.filter(bet => bet.payout === '2:1').map((bet) => (
                      <Button
                        key={`${bet.type}-${bet.betValue}`}
                        onClick={() => selectBet(bet)}
                        variant={betSelection?.type === bet.type && betSelection?.betValue === bet.betValue ? "default" : "outline"}
                        className={`
                          text-xs py-2 transition-all duration-200
                          ${betSelection?.type === bet.type && betSelection?.betValue === bet.betValue ? 'ring-2 ring-yellow-400 bg-purple-600' : 'bg-black/30 border-purple-400/50 text-purple-400 hover:bg-purple-400/20'}
                        `}
                        disabled={isSpinning || waitingForNewResult}
                      >
                        {bet.label}
                      </Button>
                    ))}
                  </div>
                </div>

                {/* Straight Number Bet */}
                <div>
                  <p className="text-cyan-400 font-bold mb-2">Straight Up Bet (35:1)</p>
                  <Button
                    onClick={() => setShowNumberGrid(!showNumberGrid)}
                    variant={showNumberGrid ? "default" : "outline"}
                    className={`
                      w-full py-2 transition-all duration-200
                      ${showNumberGrid ? 'ring-2 ring-yellow-400 bg-green-600' : 'bg-black/30 border-green-400/50 text-green-400 hover:bg-green-400/20'}
                    `}
                    disabled={isSpinning || waitingForNewResult}
                  >
                    {selectedNumber !== null ? `Number ${selectedNumber}` : 'Select Number'}
                  </Button>
                </div>
        </div>

              {/* Action Buttons */}
              <div className="mt-6 space-y-3">
                <Button
                  onClick={handlePlaceBet}
                  className="w-full text-xl py-4 bg-gradient-to-r from-green-600 to-green-500 hover:from-green-500 hover:to-green-400 border-2 border-green-400 text-white font-bold"
                  disabled={isSpinning || waitingForNewResult || !betSelection || !betAmount || parseFloat(betAmount) <= 0}
                >
                  {waitingForNewResult ? '⏳ WAITING FOR RESULT...' : 
                   isSpinning ? '🌀 SPINNING...' : 
                   '🎲 SPIN THE WHEEL'}
                </Button>

                {betSelection && (
                  <Button
                    onClick={clearBet}
                    variant="outline"
                    className="w-full bg-black/30 border-red-400/50 text-red-400 hover:bg-red-400/20"
                    disabled={isSpinning || waitingForNewResult}
                  >
                    Clear Bet
                  </Button>
                )}
              </div>
            </RetroCard>
          </div>

          {/* Right Column: Statistics */}
          <div className="xl:col-span-1">
            <GameStats 
              lastResult={lastResult}
              history={history}
              gameConfig={gameConfig}
            />
          </div>
        </div>

        {/* Number Grid Modal */}
        {showNumberGrid && (
          <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4">
            <div className="bg-black border-2 border-cyan-400 rounded-lg p-6 max-w-2xl w-full">
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-xl text-cyan-400 font-bold">Select Number</h3>
                <Button
                  onClick={() => setShowNumberGrid(false)}
                  variant="outline"
                  size="sm"
                  className="bg-black border-red-400 text-red-400 hover:bg-red-400/20"
                >
                  ✕
                </Button>
              </div>
              <NumberGrid
                selectedNumber={selectedNumber}
                onNumberSelect={handleNumberSelect}
                disabled={isSpinning}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AptosRoulette;
