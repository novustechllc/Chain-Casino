import React, { useState, useEffect, useRef } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useToast } from '@/components/ui/use-toast';
import { 
  GAMES_ADDRESS,
  formatAPT
} from '@/constants/chaincasino';
import { aptosClient } from '@/utils/aptosClient';
import { 
  playAptosFortune,
  clearFortuneResult,
  getFortuneViewFunctions,
  FortuneResult,
  FortuneConfig 
} from '@/entry-functions/chaincasino';

// AptosFortune constants - updated to match contract values
const FORTUNE_SYMBOLS = {
  1: { name: 'Cherry', emoji: '🍒', weight: 35 },
  2: { name: 'Bell', emoji: '🔔', weight: 30 },
  3: { name: 'Coin', logo: true, weight: 25 }, // ChainCasino logo
  4: { name: 'Star', emoji: '⭐', weight: 8 },
  5: { name: 'Diamond', aptosLogo: true, weight: 2 } // Aptos logo
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

// Aptos Logo Component (from InvestorPortal.tsx)
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
        e.target.style.display = 'none';
        e.target.nextSibling.style.display = 'flex';
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

// Enhanced RetroCard component matching GameHub/InvestorPortal patterns
const RetroCard = ({ children, className = "", glowOnHover = false }) => {
  const [isHovered, setIsHovered] = useState(false);
  
  return (
    <div 
      className={`retro-card transition-all duration-300 ${glowOnHover ? 'hover:shadow-[0_0_30px_rgba(255,215,0,0.4)]' : ''} ${className}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      style={{
        transform: isHovered && glowOnHover ? 'translateY(-2px) scale(1.02)' : 'translateY(0) scale(1)',
        background: isHovered && glowOnHover 
          ? 'linear-gradient(135deg, rgba(255,215,0,0.1) 0%, rgba(255,165,0,0.05) 100%)'
          : ''
      }}
    >
      {children}
    </div>
  );
};

// Slot Machine Reels Component - Real Casino Style
const SlotMachineReels = ({ reel1, reel2, reel3, isSpinning }) => {
  const [spinning, setSpinning] = useState(false);
  const [finalResult, setFinalResult] = useState({ reel1, reel2, reel3 });
  const intervalRef = useRef();
  
  const renderSymbol = (symbolNumber) => {
    const symbol = FORTUNE_SYMBOLS[symbolNumber];
    if (symbol?.logo) {
      return <CoinImage size={56} />;
    }
    if (symbol?.aptosLogo) {
      return <AptosLogo size={56} />;
    }
    return <div className="text-4xl">{symbol?.emoji || '?'}</div>;
  };

  const Reel = ({ finalSymbol }) => {
    const [currentSymbol, setCurrentSymbol] = useState(finalSymbol);
    
    useEffect(() => {
      if (spinning) {
        const interval = setInterval(() => {
          setCurrentSymbol(Math.floor(Math.random() * 5) + 1);
        }, 150);
        return () => clearInterval(interval);
      } else {
        setCurrentSymbol(finalSymbol);
      }
    }, [spinning, finalSymbol]);

    return (
      <div className="relative bg-white/10 border-2 border-gray-400 rounded-lg h-24 w-20 overflow-hidden">
        <div className="absolute inset-0 flex items-center justify-center">
          {renderSymbol(currentSymbol)}
        </div>
        <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/40 pointer-events-none" />
      </div>
    );
  };

  useEffect(() => {
    if (isSpinning && !spinning) {
      setSpinning(true);
      
      // Check for new result every 500ms
      intervalRef.current = setInterval(() => {
        // Check if we have a new result (compare with previous)
        if (reel1 !== finalResult.reel1 || reel2 !== finalResult.reel2 || reel3 !== finalResult.reel3) {
          clearInterval(intervalRef.current);
          setFinalResult({ reel1, reel2, reel3 });
          
          // Spin for 2 more seconds then stop
          setTimeout(() => {
            setSpinning(false);
          }, 2000);
        }
      }, 500);
    }
    
    return () => clearInterval(intervalRef.current);
  }, [isSpinning, reel1, reel2, reel3, finalResult, spinning]);

  // Reset when not spinning
  useEffect(() => {
    if (!isSpinning) {
      setSpinning(false);
      setFinalResult({ reel1, reel2, reel3 });
      clearInterval(intervalRef.current);
    }
  }, [isSpinning, reel1, reel2, reel3]);

  return (
    <div className="flex justify-center">
      <div className="bg-gradient-to-br from-yellow-900/40 to-orange-900/40 border-4 border-yellow-500/50 rounded-xl p-6 backdrop-blur-sm">
        <div className="bg-black/60 border-2 border-yellow-400/30 rounded-lg p-4 mb-4">
          <div className="grid grid-cols-3 gap-4">
            <Reel finalSymbol={finalResult.reel1} />
            <Reel finalSymbol={finalResult.reel2} />
            <Reel finalSymbol={finalResult.reel3} />
          </div>
        </div>

        <div className="text-center">
          <div className="text-yellow-400 font-bold text-lg retro-pixel-font">
            🎰 APTOS FORTUNE 🎰
          </div>
          <div className="text-yellow-400/70 text-sm mt-1">
            PREMIUM SLOT MACHINE
          </div>
        </div>
      </div>
    </div>
  );
};

export const AptosFortune: React.FC = () => {
  const { account, signAndSubmitTransaction } = useWallet();
  const { toast } = useToast();

  const [betAmount, setBetAmount] = useState('');
  const [gameResult, setGameResult] = useState<FortuneResult | null>(null);
  const [gameConfig, setGameConfig] = useState<FortuneConfig | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isSpinning, setIsSpinning] = useState(false);
  const [lastSessionId, setLastSessionId] = useState(0);

  // Quick bet amounts - use contract values
  const quickBets = gameConfig ? [
    { label: 'MIN', amount: gameConfig.min_bet },
    { label: '2x', amount: gameConfig.min_bet * 2 },
    { label: '5x', amount: gameConfig.min_bet * 5 },
    { label: 'MAX', amount: gameConfig.max_bet }
  ] : [
    { label: 'MIN', amount: 1000000 },
    { label: '2x', amount: 2000000 },
    { label: '5x', amount: 5000000 },
    { label: 'MAX', amount: 10000000 }
  ];

  // Load game configuration and result on mount
  useEffect(() => {
    loadGameData();
  }, [account]);

  const loadGameData = async () => {
    if (!account) return;

    try {
      // Load game config
      const configResponse = await aptosClient().view({
        payload: {
          function: getFortuneViewFunctions().gameConfig,
          functionArguments: []
        }
      });

      if (configResponse) {
        setGameConfig({
          min_bet: Number(configResponse[0]),
          max_bet: Number(configResponse[1]), 
          house_edge: Number(configResponse[2]),
          max_payout: Number(configResponse[3])
        });
      }

      // Load existing result if any
      await loadPlayerResult();
    } catch (error) {
      console.error('Error loading game data:', error);
    }
  };

  const loadPlayerResult = async () => {
    if (!account) return;

    try {
      const resultResponse = await aptosClient().view({
        payload: {
          function: getFortuneViewFunctions().getResult,
          functionArguments: [account.address.toString()]
        }
      });

      if (resultResponse && resultResponse.length >= 8) {
        const [reel1, reel2, reel3, match_type, matching_symbol, payout, session_id, bet_amount] = resultResponse;
        
        // Check if result is all zeros (no actual result)
        if (Number(reel1) === 0 && Number(reel2) === 0 && Number(reel3) === 0 && Number(payout) === 0) {
          setGameResult(null);
          return;
        }
        
        const result: FortuneResult = {
          reel1: Number(reel1),
          reel2: Number(reel2),
          reel3: Number(reel3),
          match_type: Number(match_type),
          matching_symbol: Number(matching_symbol),
          payout: Number(payout),
          session_id: Number(session_id),
          bet_amount: Number(bet_amount)
        };
        setGameResult(result);
        setLastSessionId(result.session_id);
      }
    } catch (error) {
      console.error('Error loading player result:', error);
    }
  };

  const spinReels = async () => {
    if (!account || !gameConfig) {
      toast({
        title: "Wallet Required",
        description: "Please connect your wallet to play",
        variant: "destructive"
      });
      return;
    }

    const betAmountNum = parseFloat(betAmount) * 100000000; // Convert to octas

    if (!betAmount || betAmountNum < gameConfig.min_bet) {
      toast({
        title: "Invalid Bet",
        description: `Minimum bet is ${formatAPT(gameConfig.min_bet)} APT`,
        variant: "destructive"
      });
      return;
    }

    if (betAmountNum > gameConfig.max_bet) {
      toast({
        title: "Invalid Bet", 
        description: `Maximum bet is ${formatAPT(gameConfig.max_bet)} APT`,
        variant: "destructive"
      });
      return;
    }

    setIsLoading(true);
    setIsSpinning(true);

    try {
      const transaction = playAptosFortune({ betAmount: betAmountNum });
      
      const response = await signAndSubmitTransaction(transaction);
      await aptosClient().waitForTransaction({ transactionHash: response.hash });

      // Simulate spinning animation for 2 seconds
      setTimeout(async () => {
        setIsSpinning(false);
        await loadPlayerResult();
        setIsLoading(false);
      }, 2000);

    } catch (error) {
      setIsSpinning(false);
      setIsLoading(false);
      console.error('Spin error:', error);
      toast({
        title: "Spin Failed",
        description: "Transaction failed. Please try again.",
        variant: "destructive"
      });
    }
  };

  const clearResult = async () => {
    if (!account) return;

    try {
      const transaction = clearFortuneResult();
      const response = await signAndSubmitTransaction(transaction);
      await aptosClient().waitForTransaction({ transactionHash: response.hash });
      
      setGameResult(null);
      toast({
        title: "Result Cleared",
        description: "Ready for next spin!",
        variant: "default"
      });
    } catch (error) {
      console.error('Clear result error:', error);
    }
  };

  // Connection guard
  if (!account) {
    return (
      <div className="retro-body min-h-screen relative">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        
        <div className="container mx-auto px-4 py-8 relative z-10">
          <div className="text-center">
            <h1 className="text-6xl font-bold text-transparent bg-gradient-to-r from-yellow-400 via-orange-400 to-red-400 bg-clip-text mb-8 retro-pixel-font">
              🎰 APTOS FORTUNE 🎰
            </h1>
            <RetroCard className="max-w-md mx-auto bg-black/60 backdrop-blur-sm border-yellow-500/50">
              <div className="text-center py-8">
                <div className="text-6xl mb-4 animate-bounce">🔗</div>
                <h2 className="text-2xl font-bold text-yellow-400 mb-4">
                  WALLET REQUIRED
                </h2>
                <p className="text-gray-300">
                  Connect your wallet to spin the reels!
                </p>
              </div>
            </RetroCard>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="retro-body min-h-screen relative">
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      <div className="container mx-auto px-4 py-8 relative z-10">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-6xl font-bold text-transparent bg-gradient-to-r from-yellow-400 via-orange-400 to-red-400 bg-clip-text mb-4 retro-pixel-font animate-pulse">
            🎰 APTOS FORTUNE 🎰
          </h1>
          
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
          
          <p className="text-yellow-400 text-xl retro-terminal-font mt-4">
            PREMIUM SLOT MACHINE • {gameConfig ? `${gameConfig.house_edge/100}%` : '22%'} HOUSE EDGE • 20X MAX PAYOUT
          </p>
        </div>

        {/* Status Bar */}
        <div className="bg-black/40 border border-yellow-400/30 rounded-lg p-3 mb-8 text-center">
          <div className="flex items-center justify-center gap-4 text-sm flex-wrap">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-green-400">MACHINE ACTIVE</span>
            </div>
          </div>
        </div>

        <div className="max-w-6xl mx-auto">
          {/* Main Game Interface */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            
            {/* Left Column - Slot Machine */}
            <RetroCard glowOnHover={true} className="bg-black/60 backdrop-blur-sm">
              <div className="retro-pixel-font text-sm text-yellow-300 mb-6 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-4 h-4 bg-orange-400 animate-pulse rounded-full"></div>
                  SLOT MACHINE
                </div>
                <div className="text-xs text-gray-400">
                  🎰 SPIN TO WIN
                </div>
              </div>

              {/* Slot Machine Display */}
              <div className="mb-6">
                <SlotMachineReels 
                  reel1={gameResult?.reel1 || 1}
                  reel2={gameResult?.reel2 || 2} 
                  reel3={gameResult?.reel3 || 3}
                  isSpinning={isSpinning}
                />
              </div>

              {/* Game Result Display with Effects for 3-match and 2-match */}
              {gameResult && (
                <RetroCard className={`mt-6 text-center transition-all duration-500 ${
                  gameResult.match_type === 3 
                    ? 'bg-gradient-to-br from-yellow-900/60 to-orange-900/60 border-yellow-400 shadow-[0_0_40px_rgba(255,215,0,0.6)] animate-pulse' 
                    : gameResult.match_type === 2 
                    ? 'bg-gradient-to-br from-green-900/50 to-blue-900/50 border-green-400 shadow-[0_0_25px_rgba(34,197,94,0.5)]'
                    : 'bg-black/60 backdrop-blur-sm'
                }`}>
                  
                  {/* Jackpot Effects (3-match) */}
                  {gameResult.match_type === 3 && (
                    <div className="absolute inset-0 pointer-events-none">
                      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-yellow-400/10 to-transparent animate-pulse"></div>
                    </div>
                  )}

                  {/* Partial Match Effects (2-match) */}
                  {gameResult.match_type === 2 && (
                    <div className="absolute inset-0 pointer-events-none">
                      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-green-400/5 to-transparent animate-pulse"></div>
                    </div>
                  )}

                  <div className="relative z-10 p-6">
                    <div className={`text-3xl font-bold mb-4 retro-pixel-font ${
                      gameResult.match_type === 3 
                        ? 'text-yellow-400 animate-pulse' 
                        : gameResult.match_type === 2 
                        ? 'text-green-400'
                        : 'text-white'
                    }`}>
                      {gameResult.match_type === 3 ? '🎉 JACKPOT! 🎉' : 
                       gameResult.match_type === 2 ? '🎯 PARTIAL MATCH!' :
                       gameResult.match_type === 1 ? '🎁 CONSOLATION' : '😔 No Match'}
                    </div>

                    <div className={`text-2xl font-bold mb-2 ${
                      gameResult.match_type === 3 
                        ? 'text-yellow-400 animate-pulse' 
                        : gameResult.match_type === 2 
                        ? 'text-green-400'
                        : gameResult.payout > 0 ? 'text-green-400' : 'text-gray-400'
                    }`}>
                      {gameResult.payout > 0 ? 
                        `+${formatAPT(gameResult.payout)} APT` : 
                        'No Payout'
                      }
                    </div>

                    <div className="text-sm text-gray-400 space-y-1">
                      <div>Bet: {formatAPT(gameResult.bet_amount)} APT</div>
                      <div>Match Type: {
                        gameResult.match_type === 3 ? 'Jackpot (3 symbols)' :
                        gameResult.match_type === 2 ? 'Partial (2 symbols)' :
                        gameResult.match_type === 1 ? 'Consolation (1 symbol)' : 'No match'
                      }</div>
                    </div>
                  </div>
                </RetroCard>
              )}

            </RetroCard>

            {/* Right Column - Betting Interface */}
            <RetroCard glowOnHover={true} className="bg-black/60 backdrop-blur-sm">
              <div className="retro-pixel-font text-sm text-yellow-300 mb-6 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-4 h-4 bg-green-400 animate-pulse rounded-full"></div>
                  PLACE YOUR BET
                </div>
                <div className="text-xs text-gray-400">
                  💰 BET CONTROLS
                </div>
              </div>

              {/* Bet Amount Input */}
              <div className="space-y-4 mb-6">
                <label className="retro-terminal-font text-yellow-300 font-bold">Bet Amount (APT)</label>
                <input
                  type="number"
                  value={betAmount}
                  onChange={(e) => setBetAmount(e.target.value)}
                  step="0.01"
                  min={gameConfig ? formatAPT(gameConfig.min_bet) : "0.01"}
                  max={gameConfig ? formatAPT(gameConfig.max_bet) : "0.1"}
                  className="w-full bg-black/60 border border-yellow-400/50 rounded-lg px-4 py-3 text-yellow-400 text-lg font-mono focus:border-yellow-400 focus:ring-2 focus:ring-yellow-400/20"
                  placeholder="Enter bet amount"
                />
                
                {gameConfig && (
                  <div className="text-xs text-gray-400">
                    Min: {formatAPT(gameConfig.min_bet)} APT • Max: {formatAPT(gameConfig.max_bet)} APT
                  </div>
                )}
              </div>

              {/* Quick Bet Buttons */}
              <div className="grid grid-cols-4 gap-2 mb-6">
                {quickBets.map((bet) => (
                  <button
                    key={bet.label}
                    onClick={() => setBetAmount(formatAPT(bet.amount))}
                    className="bg-yellow-600/20 hover:bg-yellow-600/40 border border-yellow-400/50 rounded-lg px-3 py-2 text-yellow-400 text-sm font-bold transition-all"
                  >
                    {bet.label}
                  </button>
                ))}
              </div>

              {/* Spin Button */}
              <button
                onClick={spinReels}
                disabled={isLoading || isSpinning || !betAmount}
                className={`w-full py-4 rounded-lg font-bold text-lg transition-all duration-300 ${
                  isLoading || isSpinning || !betAmount
                    ? 'bg-gray-600/50 text-gray-400 cursor-not-allowed'
                    : 'bg-gradient-to-r from-yellow-600 to-orange-600 hover:from-yellow-500 hover:to-orange-500 text-white shadow-lg hover:shadow-xl transform hover:scale-105'
                }`}
              >
                {isSpinning ? '🎰 SPINNING...' : isLoading ? 'PROCESSING...' : '🎰 SPIN REELS'}
              </button>

              {/* Clear Result Button */}
              {gameResult && (
                <button
                  onClick={clearResult}
                  className="w-full mt-3 py-2 bg-gray-700/50 hover:bg-gray-700/70 border border-gray-500 rounded-lg text-gray-300 text-sm transition-all"
                >
                  🧹 Clear Machine
                </button>
              )}
            </RetroCard>
          </div>

          {/* Payout Table */}
          <RetroCard className="mt-8 bg-black/60 backdrop-blur-sm">
            <div className="retro-pixel-font text-sm text-yellow-300 mb-4 flex items-center gap-2">
              <div className="w-4 h-4 bg-blue-400 animate-pulse rounded-full"></div>
              PAYOUT TABLE
            </div>
            
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="bg-black/40 border border-green-400/30 rounded-lg p-4">
                <h3 className="text-green-400 font-bold mb-2">🏆 JACKPOT (3 Match)</h3>
                <div className="space-y-2 text-sm">
                  <div className="flex items-center gap-2">
                    <AptosLogo size={20} />
                    <span>Diamond: 20x</span>
                  </div>
                  <div>⭐ Star: 12x</div>
                  <div className="flex items-center gap-2">
                    <CoinImage size={20} />
                    <span>Coin: 6x</span>
                  </div>
                  <div>🔔 Bell: 4x</div>
                  <div>🍒 Cherry: 3x</div>
                </div>
              </div>
              
              <div className="bg-black/40 border border-yellow-400/30 rounded-lg p-4">
                <h3 className="text-yellow-400 font-bold mb-2">🎯 PARTIAL (2 Match)</h3>
                <div className="text-sm">
                  Any 2 matching symbols: 0.5x
                </div>
              </div>
              
              <div className="bg-black/40 border border-orange-400/30 rounded-lg p-4">
                <h3 className="text-orange-400 font-bold mb-2">🎁 CONSOLATION (1 Match)</h3>
                <div className="text-sm">
                  Any 1 matching symbol: 0.1x
                </div>
              </div>
            </div>
          </RetroCard>
        </div>
      </div>
    </div>
  );
};
