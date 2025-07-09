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

// AptosFortune constants - will be overridden by contract values
const FORTUNE_SYMBOLS = {
  1: { name: 'Cherry', emoji: '🍒', weight: 35 },
  2: { name: 'Bell', emoji: '🔔', weight: 30 },
  3: { name: 'ChainCasino', logo: true, weight: 25 }, // ChainCasino logo
  4: { name: 'Star', emoji: '⭐', weight: 8 },
  5: { name: 'Aptos', aptosLogo: true, weight: 2 } // Aptos logo
};

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

// 2D Slot Machine Reels Component
const SlotMachineReels = ({ reel1, reel2, reel3, isSpinning }) => {
  // Render symbol function
  const renderSymbol = (symbolNumber) => {
    const symbol = FORTUNE_SYMBOLS[symbolNumber];
    if (symbol?.logo) {
      return (
        <img
          src="/chaincasino-coin.png"
          alt="ChainCasino"
          className="w-16 h-16 mx-auto"
          style={{
            filter: 'drop-shadow(0 0 8px rgba(255, 215, 0, 0.6))',
          }}
        />
      );
    }
    if (symbol?.aptosLogo) {
      return (
        <div className="flex justify-center">
          <AptosLogo size={64} />
        </div>
      );
    }
    return (
      <div className="text-4xl" style={{ lineHeight: '1' }}>
        {symbol?.emoji || '?'}
      </div>
    );
  };

  // Create spinning symbols array for animation
  const getSpinningSymbols = () => {
    const symbols = [];
    for (let i = 1; i <= 5; i++) {
      symbols.push(i);
    }
    return [...symbols, ...symbols, ...symbols]; // Triple for smooth animation
  };

  const spinningSymbols = getSpinningSymbols();

  return (
    <div className="flex justify-center">
      <div className="bg-gradient-to-br from-yellow-900/40 to-orange-900/40 border-4 border-yellow-500/50 rounded-xl p-6 backdrop-blur-sm">
        {/* Slot Machine Frame */}
        <div className="bg-black/60 border-2 border-yellow-400/30 rounded-lg p-4 mb-4">
          <div className="grid grid-cols-3 gap-4">
            {/* Reel 1 */}
            <div className="relative bg-white/10 border-2 border-gray-400 rounded-lg h-24 w-20 overflow-hidden">
              <div className="absolute inset-0 flex items-center justify-center">
                {isSpinning ? (
                  <div className="animate-bounce">
                    {renderSymbol(Math.floor(Math.random() * 5) + 1)}
                  </div>
                ) : (
                  renderSymbol(reel1)
                )}
              </div>
            </div>

            {/* Reel 2 */}
            <div className="relative bg-white/10 border-2 border-gray-400 rounded-lg h-24 w-20 overflow-hidden">
              <div className="absolute inset-0 flex items-center justify-center">
                {isSpinning ? (
                  <div className="animate-pulse">
                    {renderSymbol(Math.floor(Math.random() * 5) + 1)}
                  </div>
                ) : (
                  renderSymbol(reel2)
                )}
              </div>
            </div>

            {/* Reel 3 */}
            <div className="relative bg-white/10 border-2 border-gray-400 rounded-lg h-24 w-20 overflow-hidden">
              <div className="absolute inset-0 flex items-center justify-center">
                {isSpinning ? (
                  <div className="animate-spin">
                    {renderSymbol(Math.floor(Math.random() * 5) + 1)}
                  </div>
                ) : (
                  renderSymbol(reel3)
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Slot Machine Title */}
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
  const [winStreak, setWinStreak] = useState(0);
  const [totalWinnings, setTotalWinnings] = useState(0);
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

        // Check for win and update streaks
        if (gameResult && gameResult.payout > 0) {
          setWinStreak(prev => prev + 1);
          setTotalWinnings(prev => prev + gameResult.payout);
          
          const matchTypeText = gameResult.match_type === 3 ? 'JACKPOT!' :
                               gameResult.match_type === 2 ? 'PARTIAL WIN!' :
                               'CONSOLATION!';
          
          toast({
            title: `🎰 ${matchTypeText}`,
            description: `Won ${formatAPT(gameResult.payout)} APT!`,
            variant: "default"
          });
        } else {
          setWinStreak(0);
          toast({
            title: "No Win",
            description: "Better luck next spin!",
            variant: "destructive"
          });
        }
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
          <p className="text-yellow-400 text-xl retro-terminal-font">
            PREMIUM SLOT MACHINE • {gameConfig ? `${gameConfig.house_edge/100}%` : '22%'} HOUSE EDGE • 2X MAX PAYOUT
          </p>
        </div>

        {/* Status Bar */}
        <div className="bg-black/40 border border-yellow-400/30 rounded-lg p-3 mb-8 text-center">
          <div className="flex items-center justify-center gap-4 text-sm flex-wrap">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-green-400">MACHINE ACTIVE</span>
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-yellow-400">🎯 Win Streak: {winStreak}</div>
            <div className="text-gray-400">•</div>
            <div className="text-orange-400">💰 Total Won: {formatAPT(totalWinnings)} APT</div>
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

              {/* Last Result Display */}
              {gameResult && (
                <div className="bg-black/40 border border-yellow-400/30 rounded-lg p-4 mb-6">
                  <div className="text-yellow-400 font-bold mb-2">Last Spin Result:</div>
                  <div className="grid grid-cols-3 gap-4 text-center mb-4">
                    {[gameResult.reel1, gameResult.reel2, gameResult.reel3].map((reel, i) => (
                      <div key={i} className="bg-black/60 border border-gray-600 rounded-lg p-3">
                        <div className="text-2xl mb-1">{FORTUNE_SYMBOLS[reel]?.emoji}</div>
                        <div className="text-xs text-gray-400">{FORTUNE_SYMBOLS[reel]?.name}</div>
                      </div>
                    ))}
                  </div>
                  
                  <div className="flex justify-between items-center text-sm">
                    <span className="text-gray-400">
                      Match Type: {gameResult.match_type === 3 ? 'Jackpot' :
                                  gameResult.match_type === 2 ? 'Partial' :
                                  gameResult.match_type === 1 ? 'Consolation' : 'No Match'}
                    </span>
                    <span className={gameResult.payout > 0 ? 'text-green-400' : 'text-red-400'}>
                      {gameResult.payout > 0 ? '+' : ''}{formatAPT(gameResult.payout)} APT
                    </span>
                  </div>
                </div>
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
                  <div className="space-y-1 text-sm">
                  <div>🏛️ Aptos: 20x</div>
                  <div>⭐ Star: 12x</div>
                  <div>🏆 ChainCasino: 6x</div>
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
