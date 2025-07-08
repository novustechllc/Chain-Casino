import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useToast } from '@/components/ui/use-toast';
import { 
  GAMES_ADDRESS, 
  CASINO_HOUSE_ADDRESS, 
  formatAPT,
  APT_DECIMALS 
} from '@/constants/chaincasino';
import { aptosClient } from '@/utils/aptosClient';

interface GameData {
  objectAddress: string;
  name: string;
  version: string;
  moduleAddress: string;
  minBet: number;
  maxBet: number;
  houseEdge: number;
  maxPayout: number;
  capabilityClaimed: boolean;
  websiteUrl: string;
  iconUrl: string;
  description: string;
}

// Coin Image Component (matching InvestorPortal)
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

// Aptos Logo Component (matching InvestorPortal)
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

// Enhanced FloatingTitle component matching InvestorPortal proportions
const FloatingTitle = () => {
  const [glitchActive, setGlitchActive] = useState(false);
  
  useEffect(() => {
    const interval = setInterval(() => {
      setGlitchActive(true);
      setTimeout(() => setGlitchActive(false), 200);
    }, 4000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="relative mb-8">
      {/* Background glow effect */}
      <div className="absolute inset-0 bg-gradient-to-r from-cyan-400/20 via-purple-500/20 to-yellow-400/20 blur-3xl animate-pulse"></div>
      
      {/* Main title with matching proportions */}
      <h1 className={`
        relative z-10 text-center font-black text-5xl md:text-7xl lg:text-8xl
        bg-gradient-to-r from-cyan-400 via-purple-500 via-yellow-400 to-cyan-400
        bg-size-200 bg-pos-0 hover:bg-pos-100
        transition-all duration-1000 ease-in-out
        text-transparent bg-clip-text
        drop-shadow-[0_0_30px_rgba(0,255,255,0.7)]
        ${glitchActive ? 'animate-pulse scale-105' : 'scale-100'}
      `}>
        🎮 CHAINCASINO GAME HUB 🎮
      </h1>
      
      {/* Subtitle with enhanced branding */}
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
      
      {/* Animated decorative elements */}
      <div className="absolute -top-10 left-1/4 text-4xl animate-bounce animation-delay-300">🎯</div>
      <div className="absolute -top-8 right-1/4 text-3xl animate-bounce animation-delay-700">🎰</div>
      <div className="absolute -bottom-4 left-1/3 text-2xl animate-bounce animation-delay-500">🎲</div>
      <div className="absolute -bottom-6 right-1/3 text-2xl animate-bounce animation-delay-900">🃏</div>
    </div>
  );
};

// Enhanced RetroCard component
const RetroCard = ({ children, className = "", glowOnHover = false }) => {
  return (
    <div className={`
      bg-black/60 backdrop-blur-sm rounded-xl border-2 border-purple-400/40 
      p-6 transition-all duration-300 transform hover:scale-[1.02]
      ${glowOnHover ? 'hover:border-purple-400/70 hover:shadow-[0_0_30px_rgba(168,85,247,0.4)]' : ''}
      ${className}
    `}>
      {children}
    </div>
  );
};

// Enhanced ConnectWalletBlock component
const ConnectWalletBlock = () => {
  return (
    <RetroCard glowOnHover={true} className="mb-8 border-yellow-400/50">
      <div className="text-center py-8">
        <div className="text-6xl mb-4 animate-bounce">🔗</div>
        <h2 className="text-3xl font-bold text-yellow-400 mb-4 retro-pixel-font">
          WALLET CONNECTION REQUIRED
        </h2>
        <p className="text-gray-300 mb-6 text-lg">
          Connect your wallet to access the Game Hub 
        </p>
        <div className="flex justify-center items-center gap-4 text-sm text-gray-400">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-red-500 rounded-full animate-pulse"></div>
            <span>DISCONNECTED</span>
          </div>
          <div className="text-yellow-400">•</div>
          <div>Use wallet selector in top right</div>
        </div>
      </div>
    </RetroCard>
  );
};

export function GameHub() {
  const [games, setGames] = useState<GameData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();
  const { connected } = useWallet();
  const { toast } = useToast();

  const fetchRegisteredGames = async () => {
    try {
      setLoading(true);
      setError(null);
      console.log('Fetching registered games...');
      
      // Add delay to help with rate limiting
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Fetch registered game objects
      const gameObjectsResponse = await aptosClient().view({
        payload: {
          function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::get_registered_games`,
          functionArguments: []
        }
      });

      console.log('Game objects response:', gameObjectsResponse);
      const gameObjects = gameObjectsResponse[0] || [];
      console.log('Game objects:', gameObjects);
      
      if (!Array.isArray(gameObjects) || gameObjects.length === 0) {
        console.log('No games found or invalid response');
        setGames([]);
        setError(null);
        return;
      }

      const gamesData: GameData[] = [];

      // Fetch metadata for each game
      for (const gameObject of gameObjects) {
        try {
          // Extract address from object if needed
          const gameObjectAddr = typeof gameObject === 'object' && gameObject.inner 
            ? gameObject.inner 
            : typeof gameObject === 'string' 
            ? gameObject 
            : gameObject.toString();
            
          console.log('Fetching metadata for game address:', gameObjectAddr);
          
          // Add delay between requests to avoid rate limiting
          await new Promise(resolve => setTimeout(resolve, 500));
          
          const metadataResponse = await aptosClient().view({
            payload: {
              function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::get_game_metadata`,
              functionArguments: [gameObjectAddr]
            }
          });

          console.log('Metadata response for', gameObjectAddr, ':', metadataResponse);

          if (metadataResponse && metadataResponse.length >= 11) {
            const [name, version, moduleAddress, minBet, maxBet, houseEdgeBps, maxPayout, capabilityClaimed, websiteUrl, iconUrl, description] = metadataResponse;
            
            gamesData.push({
              objectAddress: gameObjectAddr,
              name: name.toString(),
              version: version.toString(),
              moduleAddress: moduleAddress.toString(),
              minBet: Number(minBet) / Math.pow(10, APT_DECIMALS),
              maxBet: Number(maxBet) / Math.pow(10, APT_DECIMALS),
              houseEdge: Number(houseEdgeBps) / 100,
              maxPayout: Number(maxPayout) / Math.pow(10, APT_DECIMALS),
              capabilityClaimed: Boolean(capabilityClaimed),
              websiteUrl: websiteUrl.toString(),
              iconUrl: iconUrl.toString(),
              description: description.toString()
            });
          } else {
            console.warn(`Invalid metadata response for game ${gameObjectAddr}:`, metadataResponse);
          }
        } catch (gameError) {
          console.warn(`Failed to fetch metadata for game:`, gameError);
        }
      }

      console.log('Final games data:', gamesData);
      setGames(gamesData);
      setError(null);
    } catch (err) {
      console.error('Error fetching games:', err);
      if (err.message?.includes('429') || err.message?.includes('rate')) {
        setError('Rate limited - will retry automatically');
      } else {
        setError(`Failed to load games: ${err.message || 'Unknown error'}`);
      }
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    // Initial fetch with delay
    setTimeout(() => fetchRegisteredGames(), 2000);
    
    // Refresh games list every 60 seconds to avoid rate limits
    const interval = 60000;

    return () => clearInterval(interval);
  }, []);

  const getGameIcon = (name: string, iconUrl: string) => {
    if (iconUrl && iconUrl !== '') return iconUrl;
    
    const iconMap: { [key: string]: string } = {
      'SevenOut': '🎲',
      'SlotMachine': '🎰',
      'Roulette': '🎯',
      'Blackjack': '🃏',
      'Dice': '🎲',
      'default': '🎮'
    };
    return iconMap[name] || iconMap.default;
  };

  if (loading) {
    return (
      <div className="retro-body min-h-screen relative">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        
        <div className="container mx-auto px-4 py-8 relative z-10">
          <FloatingTitle />
          
          <RetroCard className="text-center py-12">
            <div className="text-6xl mb-6 animate-bounce">🎮</div>
            <h2 className="text-2xl font-bold text-purple-400 mb-4 retro-pixel-font">
              INITIALIZING GAME HUB
            </h2>
            <div className="space-y-2 text-gray-300">
              <div className="flex items-center justify-center gap-2">
                <div className="w-2 h-2 bg-purple-400 rounded-full animate-pulse"></div>
                <span>Loading games...</span>
              </div>
              <div className="flex items-center justify-center gap-2">
                <div className="w-2 h-2 bg-cyan-400 rounded-full animate-pulse animation-delay-300"></div>
                <span>Connecting to ChainCasino network...</span>
              </div>
              <div className="flex items-center justify-center gap-2">
                <div className="w-2 h-2 bg-yellow-400 rounded-full animate-pulse animation-delay-600"></div>
                <span>Synchronizing blockchain data...</span>
              </div>
            </div>
          </RetroCard>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="retro-body min-h-screen relative">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        
        <div className="container mx-auto px-4 py-8 relative z-10">
          <FloatingTitle />
          
          <RetroCard className="border-red-400/50">
            <div className="text-center py-12">
              <div className="text-6xl mb-6">❌</div>
              <h2 className="text-2xl font-bold text-red-400 mb-4 retro-pixel-font">
                SYSTEM ERROR
              </h2>
              <p className="text-gray-300 mb-6">{error}</p>
              
              {error.includes('Rate limited') ? (
                <div className="text-yellow-400 text-sm mb-4">
                  ⏱️ Rate limited - please wait before retrying
                </div>
              ) : null}
              
              <button 
                onClick={fetchRegisteredGames}
                className="bg-red-500/20 hover:bg-red-500/30 border-2 border-red-400 text-red-400 px-6 py-3 rounded-lg font-bold transition-all duration-200 hover:scale-105"
                disabled={loading}
              >
                {loading ? 'RETRYING...' : 'RETRY CONNECTION'}
              </button>
            </div>
          </RetroCard>
        </div>
      </div>
    );
  }

  return (
    <div className="retro-body min-h-screen relative">
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      <div className="container mx-auto px-4 py-8 relative z-10">
        {/* Enhanced Floating Title */}
        <FloatingTitle />

        {/* Real-time Status Bar */}
        <div className="bg-black/40 border border-cyan-400/30 rounded-lg p-3 mb-8 text-center">
          <div className="flex items-center justify-center gap-4 text-sm flex-wrap">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-green-400">GAME HUB ACTIVE</span>
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-yellow-400">
              🎮 Games: {games.length} • 
            </div>
            <div className="text-gray-400">•</div>
            <div className="text-purple-400">
              ⚡ Real-time Updates
            </div>
          </div>
        </div>

        {/* Wallet Connection Block */}
        {!connected && <ConnectWalletBlock />}

        {/* Games Section */}
        <RetroCard glowOnHover={true} className="mb-8">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 bg-purple-400 animate-pulse rounded-full"></div>
              <h2 className="text-xl font-bold text-purple-300 retro-pixel-font">
                AVAILABLE GAMES ({games.length})
              </h2>
            </div>
            <div className="text-xs text-gray-400">
              🎲 GAMBLING ECOSYSTEM
            </div>
          </div>

          {games.length === 0 ? (
            <div className="text-center py-12">
              <div className="text-6xl mb-4 animate-bounce">🎮</div>
              <h3 className="text-2xl font-bold text-gray-400 mb-4">
                No Games Available
              </h3>
              <div className="text-gray-500 mb-6 space-y-2">
                <p>The gambling ecosystem is ready, but no games have been registered yet.</p>
                <div className="text-sm text-gray-400 bg-black/20 p-4 rounded-lg">
                  <div className="font-bold mb-2">🔍 Troubleshooting:</div>
                  <div className="space-y-1 text-left">
                    <div>• Check browser console for detailed logs</div>
                    <div>• Verify contract addresses in environment</div>
                    <div>• Ensure games are registered with CasinoHouse</div>
                    <div>• Contract: {CASINO_HOUSE_ADDRESS?.slice(0, 10)}...</div>
                  </div>
                </div>
              </div>
              <div className="flex justify-center items-center gap-4 text-sm text-gray-400">
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 bg-orange-400 rounded-full animate-pulse"></div>
                  <span>MONITORING BLOCKCHAIN</span>
                </div>
                <button 
                  onClick={fetchRegisteredGames}
                  className="px-4 py-2 bg-purple-500/20 text-purple-400 border border-purple-400/30 rounded-lg hover:bg-purple-500/30 transition-all"
                >
                  🔄 REFRESH
                </button>
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {games.map((game) => (
                <div
                  key={game.objectAddress}
                  className="bg-black/40 rounded-lg p-6 border border-purple-400/30 hover:border-purple-400/60 transition-all duration-300 hover:scale-105 group"
                >
                  {/* Game Header */}
                  <div className="flex items-start justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <div className="text-3xl">
                        {getGameIcon(game.name, game.iconUrl).startsWith('/') ? (
                          <img 
                            src={getGameIcon(game.name, game.iconUrl)} 
                            alt={game.name}
                            className="w-8 h-8 rounded"
                          />
                        ) : (
                          getGameIcon(game.name, game.iconUrl)
                        )}
                      </div>
                      <div>
                        <div className="font-bold text-white text-lg">{game.name}</div>
                        <div className="text-xs text-gray-400">v{game.version}</div>
                      </div>
                    </div>
                    <div className={`w-3 h-3 rounded-full ${
                      game.capabilityClaimed ? 'bg-green-400' : 'bg-red-400'
                    } animate-pulse`}></div>
                  </div>

                  {/* Game Stats */}
                  <div className="space-y-2 mb-4 text-sm">
                    <div className="flex justify-between">
                      <span className="text-gray-400">Status:</span>
                      <span className={`font-bold ${
                        game.capabilityClaimed ? 'text-green-400' : 'text-red-400'
                      }`}>
                        {game.capabilityClaimed ? 'ONLINE' : 'OFFLINE'}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-400">Min Bet:</span>
                      <span className="text-yellow-400">{game.minBet.toFixed(4)} APT</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-400">Max Bet:</span>
                      <span className="text-yellow-400">{game.maxBet.toFixed(4)} APT</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-400">House Edge:</span>
                      <span className="text-purple-400">{game.houseEdge.toFixed(2)}%</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-400">Max Payout:</span>
                      <span className="text-green-400">{game.maxPayout.toFixed(4)} APT</span>
                    </div>
                  </div>

                  {/* Game Description */}
                  {game.description && (
                    <div className="mb-4 p-3 bg-black/30 rounded border border-gray-600/30">
                      <p className="text-xs text-gray-300">{game.description}</p>
                    </div>
                  )}

                  {/* Action Buttons */}
                  <div className="space-y-2">
                    <button
                      onClick={() => {
                        if (game.capabilityClaimed && connected) {
                          // Navigate to game or handle game launch
                          console.log('Launching game:', game.name);
                          toast({
                            title: "Game Launch",
                            description: `Launching ${game.name}...`,
                          });
                        }
                      }}
                      disabled={!connected || !game.capabilityClaimed}
                      className={`w-full px-4 py-3 rounded-lg font-bold text-sm transition-all duration-200 ${
                        !connected ? 
                          'bg-gray-600 text-gray-400 cursor-not-allowed' :
                        !game.capabilityClaimed ? 
                          'bg-orange-500/20 text-orange-400 border border-orange-400/30' : 
                          'bg-purple-500/20 text-purple-400 border border-purple-400/30 hover:bg-purple-500/30 hover:scale-105'
                      }`}
                    >
                      {!connected ? '🔗 CONNECT WALLET' : 
                       !game.capabilityClaimed ? '⏳ GAME OFFLINE' : 
                       '🎮 PLAY NOW'}
                    </button>
                    
                    {game.websiteUrl && (
                      <button 
                        onClick={() => window.open(game.websiteUrl, '_blank')}
                        className="w-full px-4 py-2 bg-gray-600/20 text-gray-400 border border-gray-400/30 rounded-lg text-xs hover:bg-gray-600/30 transition-all duration-200"
                      >
                        ℹ️ GAME INFO
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </RetroCard>

        {/* Navigation */}
        <div className="text-center">
          <button 
            onClick={() => navigate('/')}
            className="group relative bg-gradient-to-r from-purple-500/20 to-cyan-500/20 
                     hover:from-purple-500/30 hover:to-cyan-500/30 
                     border-2 border-purple-400/40 hover:border-purple-400/60
                     text-white px-8 py-4 rounded-xl font-bold text-lg 
                     transition-all duration-300 hover:scale-105 
                     shadow-[0_0_20px_rgba(168,85,247,0.3)] hover:shadow-[0_0_30px_rgba(168,85,247,0.5)]
                     backdrop-blur-sm"
          >
            <div className="flex items-center gap-3">
              <CoinImage size={32} className="group-hover:animate-spin" />
              <span>INVESTOR PORTAL</span>
              <AptosLogo size={32} />
            </div>
          </button>
        </div>
      </div>
    </div>
  );
}
