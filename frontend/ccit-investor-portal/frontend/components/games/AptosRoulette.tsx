import React, { useState, useEffect, useRef } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useToast } from '@/components/ui/use-toast';
import { useDocumentTitle } from '../../hooks/useDocumentTitle';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { aptosClient } from '@/utils/aptosClient';
import { 
  getRouletteViewFunctions,
  parseRouletteConfig,
  parseRoulettePayoutTable,
  placeRouletteBet,
  betRouletteNumber,
  betRouletteRedBlack,
  betRouletteEvenOdd,
  betRouletteHighLow,
  betRouletteDozen,
  betRouletteColumn,
  clearRouletteResult,
  parseRouletteResult,
  RouletteResult,
  RouletteConfig,
  RoulettePayoutTable,
} from '@/entry-functions/chaincasino';
import { formatAPT, GAMES_ADDRESS } from '@/constants/chaincasino';

// Add CSS for pixelated images
const pixelatedStyle = `
  .pixelated {
    image-rendering: -moz-crisp-edges;
    image-rendering: -webkit-crisp-edges;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
  }
`;

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
          <div className="flex items-center justify-center gap-3 mb-4">
            <div className="text-3xl font-bold text-cyan-400">
              ⚡ Processing Bet on Blockchain
            </div>
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
            <div className="flex items-center justify-center gap-3 mb-2">
              <div className="text-5xl font-bold text-yellow-400">
                WINNING NUMBER
              </div>
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
          <div className="flex items-center justify-center gap-3 mb-4">
            <div className="text-4xl font-bold text-purple-400">
              Aptos Roulette
            </div>
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
  // Real European roulette table layout - 0 in left column, middle row
  const getNumberLayout = () => {
    const layout = [];
    
    // Create the three rows
    const topRow = [];    // 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36
    const middleRow = []; // 2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35
    const bottomRow = []; // 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34
    
    // Fill the rows with numbers 1-36
    for (let col = 0; col < 12; col++) {
      topRow.push(col * 3 + 3);    // 3, 6, 9, ...
      middleRow.push(col * 3 + 2); // 2, 5, 8, ...
      bottomRow.push(col * 3 + 1); // 1, 4, 7, ...
    }
    
    // Create layout with 0 positioned in middle row
    layout.push(topRow);           // Top row: no 0
    layout.push([0, ...middleRow]); // Middle row: 0 + numbers
    layout.push(bottomRow);        // Bottom row: no 0
    
    return layout;
  };

  const layout = getNumberLayout();

  return (
    <div className="bg-black/40 border border-cyan-400/30 rounded-lg p-4">
      <h4 className="text-cyan-400 font-bold mb-3 retro-terminal-font">Straight Up Bets (35:1)</h4>
      <div className="flex flex-col gap-1 justify-center">
        {layout.map((row, rowIndex) => (
          <div key={rowIndex} className="flex gap-1 justify-center">
            {/* Add spacing for top and bottom rows to align with middle row that has 0 */}
            {rowIndex !== 1 && <div className="w-10 mr-1"></div>}
            {row.map(num => {
              const color = getNumberColor(num);
              const isSelected = selectedNumber === num;
              
              return (
                <Button
                  key={num}
                  onClick={() => onNumberSelect(num)}
                  disabled={disabled}
                  className={`
                    w-10 h-12 text-sm font-bold transition-all duration-200
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
        ))}
      </div>
    </div>
  );
};

// Coin Image Component  
const CoinImage = ({ size = 64, className = "", spinning = false }) => (
  <img
    src="/chaincasino-coin.png"
    alt="ChainCasino Coin"
    className={`${className} ${spinning ? 'animate-spin' : ''}`}
    style={{ 
      width: size, 
      height: size,
      filter: 'drop-shadow(0 0 10px rgba(255, 215, 0, 0.5))',
      animation: spinning ? 'spin 3s linear infinite' : 'none'
    }}
  />
);

// Aptos Logo Component
const AptosLogo = ({ size = 32, className = "" }) => (
  <div className="relative">
    <img
      src="/aptos-logo.png"
      alt="Aptos"
      className={`${className}`}
      style={{ 
        width: size, 
        height: size,
        filter: 'drop-shadow(0 0 8px rgba(0, 195, 255, 0.5))'
      }}
      onError={(e) => {
        // Fallback to CSS version if image not found
        const target = e.target as HTMLImageElement;
        target.style.display = 'none';
        const nextSibling = target.nextSibling as HTMLElement;
        if (nextSibling) {
          nextSibling.style.display = 'flex';
        }
      }}
    />
    {/* Fallback CSS logo */}
    <div 
      className={`${className} flex items-center justify-center hidden`}
      style={{ width: size, height: size }}
    >
      <div className="relative">
        <div className="w-8 h-8 bg-gradient-to-br from-cyan-400 to-blue-600 rounded-full flex items-center justify-center text-white font-bold text-xs">
          A
        </div>
        <div className="absolute -top-1 -right-1 w-3 h-3 bg-green-400 rounded-full animate-pulse"></div>
      </div>
    </div>
  </div>
);

const AptosRoulette = () => {
  const { account, connected, signAndSubmitTransaction } = useWallet();
  const { toast } = useToast();

  // Set page title and favicon
  useDocumentTitle({ 
    title: 'AptosRoulette - ChainCasino', 
    favicon: '/icons/aptos-roulette.png' 
  });
  
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

  // Polling state - matching SevenOut pattern exactly
  const [winningNumber, setWinningNumber] = useState<number | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [waitingForNewResult, setWaitingForNewResult] = useState(false);
  const [lastSessionId, setLastSessionId] = useState(0);
  const [isClearingTable, setIsClearingTable] = useState(false);

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

  // Load existing result on mount and set up polling - matching SevenOut pattern
  useEffect(() => {
    if (account) {
      checkExistingResult();
    }
  }, [account]);

  // Result checking function - adapted for AptosRoulette (no hasResult function)
  const checkExistingResult = async () => {
    if (!account) return;
    
    try {
      // Directly try to get result - AptosRoulette doesn't have hasResult function
      const result = await aptosClient().view({
        payload: {
          function: getRouletteViewFunctions().getLatestResult as `${string}::${string}::${string}`,
          functionArguments: [account.address.toString()]
        }
      });

      // Parse the 11-tuple result: (winning_number, winning_color, is_even, is_high, dozen, column, total_wagered, total_payout, won, net_result, session_id)
      const newResult = parseRouletteResult(result);

      // If this is a new result (different session ID), stop spinning - like SevenOut
      if (newResult.session_id !== lastSessionId) {
        setIsPlaying(false);
        setLastSessionId(newResult.session_id);
        setWaitingForNewResult(false);
      }
      
      setLastResult(newResult);
      setWinningNumber(newResult.winning_number);
    } catch (error) {
      // No result exists yet - this is expected behavior
    }
  };

  // Cleanup polling on unmount - matching SevenOut
  useEffect(() => {
    return () => {
      // No explicit cleanup needed with SevenOut pattern
    };
  }, []);

  // Handle bet placement using SevenOut pattern exactly
  const handlePlaceBet = async () => {
    if (!betSelection || !betAmount || !gameConfig || !account) {
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
    setIsPlaying(true);
    setWaitingForNewResult(true);

    try {
      let payload;
      
      // Use convenience functions for common bets, fallback to generic for complex bets
      if (betSelection.type === 'straight' && selectedNumber !== null) {
        payload = betRouletteNumber({
          number: selectedNumber,
          amount: amount,
        });
      } else if (betSelection.type === 'red' || betSelection.type === 'black') {
        payload = betRouletteRedBlack({
          isRed: betSelection.type === 'red',
          amount: amount,
        });
      } else if (betSelection.type === 'even' || betSelection.type === 'odd') {
        payload = betRouletteEvenOdd({
          isEven: betSelection.type === 'even',
          amount: amount,
        });
      } else if (betSelection.type === 'high' || betSelection.type === 'low') {
        payload = betRouletteHighLow({
          isHigh: betSelection.type === 'high',
          amount: amount,
        });
      } else if (betSelection.type === 'dozen') {
        payload = betRouletteDozen({
          dozen: betSelection.betValue,
          amount: amount,
        });
      } else if (betSelection.type === 'column') {
        payload = betRouletteColumn({
          column: betSelection.betValue,
          amount: amount,
        });
      } else {
        // Fallback to generic place_bet for complex bets
        payload = placeRouletteBet({
          betFlag: betSelection.betFlag,
          betValue: betSelection.betValue,
          betNumbers: [],
          amount: amount,
        });
      }

      const result = await signAndSubmitTransaction(payload);
      await aptosClient().waitForTransaction({ transactionHash: result.hash });
      
      // Start checking for result after 1 second - exactly like SevenOut
      setTimeout(() => {
        checkExistingResult();
      }, 1000);
    } catch (error) {
      console.error('Game play failed:', error);
      setWaitingForNewResult(false);
      toast({
        title: 'Bet Failed',
        description: error instanceof Error ? error.message : 'There was an error placing your bet. Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsPlaying(false);
    }
  };

  // Clear table function - matching SevenOut pattern exactly
  const clearTable = async () => {
    if (!account) return;
    
    setIsClearingTable(true);
    try {
      const transaction = clearRouletteResult();
      const response = await signAndSubmitTransaction(transaction);
      await aptosClient().waitForTransaction({ transactionHash: response.hash });
      
      // Clear all state - matching SevenOut
      setWinningNumber(null);
      setLastResult(null);
      setBetSelection(null);
      setSelectedNumber(null);
      setBetAmount('');
      setIsPlaying(false);
      setWaitingForNewResult(false);
      setLastSessionId(0);
    } catch (error) {
      console.error('Clear table failed:', error);
      toast({
        title: "Clear Failed",
        description: error instanceof Error ? error.message : 'Failed to clear table',
        variant: "destructive"
      });
    } finally {
      setIsClearingTable(false);
    }
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
              <span>Connect wallet to access Aptos roulette</span>
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
            <div className="retro-terminal-header">/// INITIALIZING APTOS ROULETTE TABLE ///</div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">INIT:&gt;</span>
              <span className="animate-pulse">Loading Aptos roulette configuration...</span>
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
            <div className="retro-terminal-header">/// APTOS ROULETTE TABLE ERROR ///</div>
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
      <style>{pixelatedStyle}</style>
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      <div className="container mx-auto px-4 py-8 relative z-10">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="flex items-center justify-center gap-4 mb-4">
            <img 
              src="/roulette-8bit-emoji.png" 
              alt="Roulette" 
              className="w-16 h-16 pixelated animate-pulse"
            />
            <h1 className="text-6xl font-bold text-transparent bg-gradient-to-r from-red-400 via-yellow-400 to-green-400 bg-clip-text retro-pixel-font animate-pulse">
              APTOS ROULETTE
            </h1>
            <img 
              src="/roulette-8bit-emoji.png" 
              alt="Roulette" 
              className="w-16 h-16 pixelated animate-pulse"
            />
          </div>
          
          {/* ChainCasino x Aptos Branding */}
          <div className="text-center mt-4 flex items-center justify-center gap-6 flex-wrap">
            <div className="flex items-center gap-2">
              <CoinImage size={40} spinning={false} />
              <span className="text-yellow-400 font-bold text-lg tracking-wider">
                CHAINCASINO
              </span>
            </div>
            
            <div className="text-cyan-400 text-2xl font-black">×</div>
            
            <div className="flex items-center gap-2">
              <AptosLogo size={40} />
              <span className="text-cyan-400 font-bold text-lg tracking-wider">
                APTOS
              </span>
            </div>
          </div>
          
          <p className="text-cyan-400 text-xl retro-terminal-font mt-4">
            {(gameConfig?.house_edge_bps || 270) / 100}% HOUSE EDGE • SINGLE ZERO • {payoutTable?.single || 35}:1 MAX PAYOUT
          </p>
        </div>

        {/* Status Bar */}
        <div className="bg-black/40 border border-cyan-400/30 rounded-lg p-3 mb-8">
          <div className="flex items-center justify-center gap-4 text-sm flex-wrap">
            <div className="flex items-center gap-2">
              <div className={`w-2 h-2 rounded-full animate-pulse ${isPlaying || waitingForNewResult ? 'bg-yellow-400' : 'bg-green-400'}`}></div>
              <span className={`font-bold ${isPlaying || waitingForNewResult ? 'text-yellow-400' : 'text-green-400'}`}>
                {isPlaying || waitingForNewResult ? 'PROCESSING ON BLOCKCHAIN' : 'READY FOR BETS'}
              </span>
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-yellow-400">
              Range: {formatAPT(gameConfig?.min_bet || 0)} - {formatAPT(gameConfig?.max_bet || 0)} APT
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          {/* Left Column: Roulette Wheel */}
          <div className="xl:col-span-2">
            <RetroCard className="p-6" glowOnHover>
              <div className="retro-pixel-font text-base text-yellow-400 mb-6 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-4 h-4 bg-red-400 animate-pulse rounded-full"></div>
                  APTOS ROULETTE
                </div>
                <div className="text-sm text-gray-400">
                  SPIN THE WHEEL
                </div>
              </div>
              
              <div className="bg-black/30 border border-purple-400/30 rounded-lg">
                <SimpleResultDisplay
                  isProcessing={isPlaying || waitingForNewResult}
                  winningNumber={winningNumber}
                />
              </div>

              {/* Clear Table Button - for clean demos */}
              {(winningNumber !== null || lastResult !== null) && !isPlaying && !waitingForNewResult && !isClearingTable && (
                <div className="mt-4 text-center">
                  <Button
                    onClick={clearTable}
                    disabled={isClearingTable}
                    className="bg-red-600 hover:bg-red-500 border-2 border-red-400 text-white font-bold"
                  >
                    {isClearingTable ? '🧹 CLEARING...' : '🧹 Clear Table'}
                  </Button>
                </div>
              )}
            </RetroCard>
          </div>

          {/* Right Column: Betting Interface */}
          <div className="xl:col-span-1">
            <RetroCard className="p-6" glowOnHover>
              <div className="flex items-center gap-2 mb-6">
                <h3 className="text-xl text-yellow-400 font-bold retro-terminal-font">Place Your Bet</h3>
              </div>
              
              {/* Current Bet Display */}
              {betSelection && (
                <div className="bg-purple-900/30 border border-purple-400/50 rounded-lg p-3 mb-4">
                  <div className="text-center">
                    <div className="flex items-center justify-center gap-2 mb-1">
                      <div className="text-lg font-bold text-yellow-400">{betSelection.label}</div>
                    </div>
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
                <label className="text-cyan-400 block mb-2 font-bold flex items-center gap-2">
                  <AptosLogo size={20} />
                  Amount (APT)
                </label>
                <Input
                  type="number"
                  step="0.001"
                  value={betAmount}
                  onChange={(e) => setBetAmount(e.target.value)}
                  placeholder={gameConfig ? `Min ${formatAPT(gameConfig.min_bet)}` : '0.001'}
                  className="bg-black/50 border-cyan-400/50 text-white placeholder-gray-500"
                  disabled={isPlaying || waitingForNewResult}
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
                      disabled={isPlaying || waitingForNewResult}
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
                          text-sm font-bold py-2 transition-all duration-200
                          ${bet.type === 'red' ? 'bg-red-600/80 hover:bg-red-500 border-red-400' : ''}
                          ${bet.type === 'black' ? 'bg-gray-800/80 hover:bg-gray-700 border-gray-600' : ''}
                          ${betSelection?.type === bet.type && betSelection?.betValue === bet.betValue ? 'ring-2 ring-yellow-400' : ''}
                        `}
                        disabled={isPlaying || waitingForNewResult}
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
                          text-sm font-bold py-2 transition-all duration-200
                          ${betSelection?.type === bet.type && betSelection?.betValue === bet.betValue ? 'ring-2 ring-yellow-400 bg-purple-600' : 'bg-black/30 border-purple-400/50 text-purple-400 hover:bg-purple-400/20'}
                        `}
                        disabled={isPlaying || waitingForNewResult}
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
                    disabled={isPlaying || waitingForNewResult}
                  >
                    {selectedNumber !== null ? `Number ${selectedNumber}` : 'Select Number'}
                  </Button>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="mt-6 space-y-3">
                <Button
                  onClick={handlePlaceBet}
                  className="w-full text-base py-4 bg-gradient-to-r from-green-600 to-green-500 hover:from-green-500 hover:to-green-400 border-2 border-green-400 text-white font-bold"
                  disabled={isPlaying || waitingForNewResult || !betSelection || !betAmount || parseFloat(betAmount) <= 0}
                >
                  {isPlaying || waitingForNewResult ? '⏳ PROCESSING...' : 'PLACE BET'}
                </Button>

                {betSelection && !isPlaying && !waitingForNewResult && (
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
                disabled={isPlaying || waitingForNewResult}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AptosRoulette;