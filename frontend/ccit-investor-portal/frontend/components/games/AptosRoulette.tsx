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

// Simple Result Display Component
const SimpleResultDisplay = ({ 
  isProcessing, 
  winningNumber 
}: { 
  isProcessing: boolean; 
  winningNumber: number | null; 
}) => {
  return (
    <div className="flex flex-col items-center justify-center h-[400px] space-y-8">
      {/* Processing State */}
      {isProcessing && (
        <div className="text-center">
          <div className="text-3xl font-bold text-cyan-400 mb-4">
            ⚡ Processing Bet on Blockchain
          </div>
          <div className="text-lg text-gray-400">
            Waiting for transaction result...
          </div>
        </div>
      )}

      {/* Result Display */}
      {!isProcessing && winningNumber !== null && (
        <div className="text-center">
          <div className="mb-6">
            <div className="text-5xl font-bold text-yellow-400 mb-2">
              WINNING NUMBER
            </div>
          </div>
          <div className={`
            inline-block px-12 py-8 rounded-2xl border-4 font-bold shadow-2xl transition-all duration-300
            ${getNumberColor(winningNumber) === 'red' ? 'bg-red-600 border-red-400 text-white' : 
              getNumberColor(winningNumber) === 'black' ? 'bg-gray-800 border-gray-400 text-white' : 
              'bg-green-600 border-green-400 text-white'}
          `}>
            <div className="text-8xl mb-4 font-black">{winningNumber}</div>
            <div className="text-2xl uppercase tracking-widest font-bold">
              {getNumberColor(winningNumber)}
            </div>
          </div>
        </div>
      )}

      {/* Idle State */}
      {!isProcessing && winningNumber === null && (
        <div className="text-center">
          <div className="text-4xl font-bold text-purple-400 mb-4">
            European Roulette
          </div>
          <div className="text-lg text-gray-400">
            Place your bet to see the blockchain result
          </div>
        </div>
      )}
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
  const [showNumberGrid, setShowNumberGrid] = useState(false);

  // Blockchain state  
  const [winningNumber, setWinningNumber] = useState<number | null>(null);
  const [isPolling, setIsPolling] = useState(false);
  
  // Polling refs
  const pollingIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const lastResultHashRef = useRef<string>('');

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
            function: getRouletteViewFunctions().isReady as `${string}::${string}::${string}`,
            functionArguments: []
          }
        });
        
        const gameIsReady = Boolean(readyResponse[0]);
        setIsReady(gameIsReady);
        
        if (!gameIsReady) {
          setConfigError('Game is not ready. Please ensure AptosRoulette is properly initialized.');
          setIsLoading(false);
          return;
        }
        
        // Load game config
        const configResponse = await aptosClient().view({
          payload: {
            function: getRouletteViewFunctions().gameConfig as `${string}::${string}::${string}`,
            functionArguments: []
          }
        });
        
        const config = parseRouletteConfig(configResponse);
        setGameConfig(config);
        
        // Load payout table
        const payoutResponse = await aptosClient().view({
          payload: {
            function: getRouletteViewFunctions().payoutTable as `${string}::${string}::${string}`,
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

  // Load existing result on mount
  useEffect(() => {
    const loadExistingResult = async () => {
      if (!connected || !account) return;
      
      try {
        const res = await aptosClient().view({
          payload: {
            function: `${GAMES_ADDRESS}::AptosRoulette::get_latest_result` as `${string}::${string}::${string}`,
            functionArguments: [account.address.toString()]
          },
        });

        const result = parseRouletteResult(res);
        if (result && result.total_wagered > 0) {
          setLastResult(result);
          setWinningNumber(result.winning_number);
          // Create unique hash for this result
          const resultHash = `${result.winning_number}-${result.total_wagered}-${result.total_payout}`;
          lastResultHashRef.current = resultHash;
        }
      } catch (error) {
        console.log('ℹ️ No existing results found');
      }
    };

    loadExistingResult();
  }, [connected, account]);

  // Cleanup polling on unmount
  useEffect(() => {
    return () => {
      if (pollingIntervalRef.current) {
        clearInterval(pollingIntervalRef.current);
      }
    };
  }, []);

  // Polling function to check for new results
  const startPollingForResult = () => {
    if (pollingIntervalRef.current) {
      clearInterval(pollingIntervalRef.current);
    }

    setIsPolling(true);
    
    pollingIntervalRef.current = setInterval(async () => {
      if (!account?.address) return;
      
      try {
        const res = await aptosClient().view({
          payload: {
            function: `${GAMES_ADDRESS}::AptosRoulette::get_latest_result` as `${string}::${string}::${string}`,
            functionArguments: [account.address.toString()]
          }
        });

        const newResult = parseRouletteResult(res);
        if (newResult && newResult.total_wagered > 0) {
          // Create hash for this result
          const newResultHash = `${newResult.winning_number}-${newResult.total_wagered}-${newResult.total_payout}`;
          
          // Check if this is a new result by comparing hashes
          if (newResultHash !== lastResultHashRef.current) {
            // Found new result!
            
            // Stop polling
            if (pollingIntervalRef.current) {
              clearInterval(pollingIntervalRef.current);
              pollingIntervalRef.current = null;
            }
            
            // Update state
            setLastResult(newResult);
            setWinningNumber(newResult.winning_number);
            setIsPolling(false);
            lastResultHashRef.current = newResultHash;

            // Clean up form after showing result
            setTimeout(() => {
              cleanupAfterResult();
            }, 3000);
          }
        }
      } catch (error) {
        // Still waiting for result
      }
    }, 2000); // Poll every 2 seconds

    // Safety timeout after 30 seconds
    setTimeout(() => {
      if (pollingIntervalRef.current) {
        clearInterval(pollingIntervalRef.current);
        pollingIntervalRef.current = null;
        setIsPolling(false);
        
        toast({
          title: 'Timeout',
          description: 'Result polling timed out. Please check manually.',
          variant: 'destructive'
        });
      }
    }, 30000);
  };

  // Clean up after result is found
  const cleanupAfterResult = () => {
    setIsPolling(false);
    setBetSelection(null);
    setSelectedNumber(null);
    setBetAmount('');
  };

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

    setWinningNumber(null); // Clear previous winning number

    try {
      let payload;
      
      if (betSelection.type === 'straight' && selectedNumber !== null) {
        payload = placeRouletteBet({
          betFlag: 0,
          betValue: selectedNumber,
          betNumbers: [],
          amount: amount,
        });
      } else {
        payload = placeRouletteBet({
          betFlag: betSelection.betFlag,
          betValue: betSelection.betValue,
          betNumbers: [],
          amount: amount,
        });
      }

      const result = await signAndSubmitTransaction(payload);
      await aptosClient().waitForTransaction({ transactionHash: result.hash });
      
      // Start automatic polling for result
      startPollingForResult();
      
    } catch (error) {
      toast({
        title: 'Bet Failed',
        description: 'There was an error placing your bet. Please try again.',
        variant: 'destructive',
      });
    }
  };

  // Clear table function - resets all state for clean demo
  const clearTable = () => {
    // Stop any active polling
    if (pollingIntervalRef.current) {
      clearInterval(pollingIntervalRef.current);
      pollingIntervalRef.current = null;
    }
    
    // Clear all state
    setWinningNumber(null);
    setLastResult(null);
    setBetSelection(null);
    setSelectedNumber(null);
    setBetAmount('');
    setIsPolling(false);
    lastResultHashRef.current = '';
    
    toast({
      title: '🧹 Table Cleared',
      description: 'Ready for next demonstration',
      variant: 'default'
    });
  };

  // Quick bet amounts
  const getQuickBetAmounts = () => {
    if (!gameConfig) return [];
    const max = gameConfig.max_bet / 100_000_000;
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
            EUROPEAN ROULETTE
          </h1>
          <p className="text-cyan-400 text-xl retro-terminal-font">
            {(gameConfig?.house_edge_bps || 270) / 100}% HOUSE EDGE • SINGLE ZERO • {payoutTable?.single || 35}:1 MAX PAYOUT
          </p>
        </div>

        {/* Status Bar */}
        <div className="bg-black/40 border border-cyan-400/30 rounded-lg p-3 mb-8">
          <div className="flex items-center justify-center gap-4 text-sm flex-wrap">
            <div className="flex items-center gap-2">
              <div className={`w-2 h-2 rounded-full animate-pulse ${isPolling ? 'bg-yellow-400' : 'bg-green-400'}`}></div>
              <span className={`font-bold ${isPolling ? 'text-yellow-400' : 'text-green-400'}`}>
                {isPolling ? 'PROCESSING ON BLOCKCHAIN' : 'READY FOR BETS'}
              </span>
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-yellow-400">
              💰 Range: {formatAPT(gameConfig?.min_bet || 0)} - {formatAPT(gameConfig?.max_bet || 0)} APT
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

                <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          {/* Left Column: Roulette Wheel */}
          <div className="xl:col-span-2">
            <RetroCard className="p-6" glowOnHover>
              <div className="text-center mb-4">
                <h3 className="text-2xl text-yellow-400 font-bold retro-terminal-font">
                  EUROPEAN ROULETTE
                </h3>
              </div>
              
              <div className="bg-black/30 border border-purple-400/30 rounded-lg">
                <SimpleResultDisplay
                  isProcessing={isPolling}
                  winningNumber={winningNumber}
                />
              </div>

              {/* Clear Table Button - for clean demos */}
              {(winningNumber !== null || lastResult !== null) && !isPolling && (
                <div className="mt-4 text-center">
                  <Button
                    onClick={clearTable}
                    className="bg-red-600 hover:bg-red-500 border-2 border-red-400 text-white font-bold"
                  >
                    🧹 Clear Table
                  </Button>
                </div>
              )}

 
            </RetroCard>
          </div>

          {/* Right Column: Betting Interface */}
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
                  disabled={isPolling}
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
                      disabled={isPolling}
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
                        disabled={isPolling}
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
                        disabled={isPolling}
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
                    disabled={isPolling}
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
                  disabled={isPolling || !betSelection || !betAmount || parseFloat(betAmount) <= 0}
                >
                  {isPolling ? '⏳ PROCESSING...' : 'PLACE BET'}
                </Button>

                {betSelection && !isPolling && (
                  <Button
                    onClick={clearBet}
                    variant="outline"
                    className="w-full bg-black/30 border-red-400/50 text-red-400 hover:bg-red-400/20"
                  >
                    Clear Bet
                  </Button>
                )}
              </div>
            </RetroCard>
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
                disabled={isPolling}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AptosRoulette;
