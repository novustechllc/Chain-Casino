import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { 
  GAME_ADDRESS, 
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

export function GameHub() {
  const [games, setGames] = useState<GameData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();
  const { connected } = useWallet();

  const fetchRegisteredGames = async () => {
    try {
      setLoading(true);
      setError(null);

      const response = await aptosClient().view({
        payload: {
          function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::get_registered_games`,
          functionArguments: []
        }
      });

      if (!response || !Array.isArray(response) || response.length === 0) {
        setGames([]);
        return;
      }

      const gameObjects = response[0];
      const gamesData: GameData[] = [];

      for (const gameObject of gameObjects) {
        try {
          const gameObjectAddr = typeof gameObject === 'object' && gameObject.inner 
            ? gameObject.inner 
            : typeof gameObject === 'string' 
            ? gameObject 
            : gameObject.toString();

          await new Promise(resolve => setTimeout(resolve, 500));
          
          const metadataResponse = await aptosClient().view({
            payload: {
              function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::get_game_metadata`,
              functionArguments: [gameObjectAddr]
            }
          });

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
          }
        } catch (gameError) {
          console.warn(`Failed to fetch metadata for game:`, gameError);
        }
      }

      setGames(gamesData);
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
    fetchRegisteredGames();
  }, []);

  const getGameIcon = (name: string, iconUrl: string) => {
    if (iconUrl && iconUrl !== '') return iconUrl;
    
    const iconMap = {
      'SevenOut': '/icons/seven-out.png',
      'AptosRoulette': '/icons/aptos-roulette.png', 
      'AptosFortune': '/icons/aptos-fortune.png',
      'default': '🎮'
    };
    return iconMap[name] || iconMap.default;
  };

  const getGameRoute = (name: string) => {
    const gameRoutes = {
      'SevenOut': '/game-hub/seven-out',
      'AptosRoulette': '/game-hub/roulette',
      'AptosFortune': '/game-hub/fortune'
    };
    return gameRoutes[name] || '/game-hub';
  };

  if (loading) {
    return (
      <div className="retro-body">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div style={{ padding: '2rem', maxWidth: '1200px', margin: '0 auto' }}>
          <div className="retro-terminal">
            <div className="retro-terminal-header">INITIALIZING GAME HUB</div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">&gt;</span>
              <span>Loading games...</span>
              <span className="retro-terminal-cursor">_</span>
            </div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">&gt;</span>
              <span>Connecting to ChainCasino network...</span>
            </div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">&gt;</span>
              <span>Synchronizing blockchain data...</span>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="retro-body">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div style={{ padding: '2rem', maxWidth: '1200px', margin: '0 auto' }}>
          <div className="retro-terminal">
            <div className="retro-terminal-header">SYSTEM ERROR</div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">&gt;</span>
              <span style={{ color: 'var(--retro-danger)' }}>ERROR: {error}</span>
            </div>
            {error.includes('Rate limited') ? (
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">&gt;</span>
                <span style={{ color: 'var(--retro-warning)' }}>RATE LIMITED - PLEASE WAIT</span>
              </div>
            ) : (
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">&gt;</span>
                <button 
                  onClick={fetchRegisteredGames}
                  className="retro-button retro-button-secondary"
                  disabled={loading}
                  style={{ marginTop: '10px' }}
                >
                  {loading ? 'RETRYING...' : 'RETRY CONNECTION'}
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="retro-body">
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      <div style={{ padding: '2rem', maxWidth: '1200px', margin: '0 auto' }}>
        
        {/* Header */}
        <div className="retro-display" style={{ marginBottom: '2rem' }}>
          <div className="retro-display-value retro-neon-text">
            🎮 GAME HUB 🎮
          </div>
          <div className="retro-display-label">
            CHAINCASINO ARCADE SYSTEM
          </div>
        </div>

        {/* Wallet Status */}
        {!connected && (
          <div className="retro-terminal" style={{ marginBottom: '2rem', border: '3px solid var(--retro-warning)' }}>
            <div className="retro-terminal-header">⚠️ WALLET CONNECTION REQUIRED</div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">&gt;</span>
              <span style={{ color: 'var(--retro-warning)' }}>CONNECT WALLET TO ACCESS GAMES</span>
            </div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">&gt;</span>
              <span>USE WALLET SELECTOR IN TOP RIGHT</span>
            </div>
          </div>
        )}

        {/* Games Section */}
        <div className="retro-card">
          <div className="retro-terminal-header" style={{ marginBottom: '2rem' }}>
            🎲 AVAILABLE GAMES ({games.length}) 🎲
          </div>

          {games.length === 0 ? (
            <div className="retro-terminal">
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">&gt;</span>
                <span>NO GAMES REGISTERED</span>
              </div>
              <div className="retro-terminal-line">
                <span className="retro-terminal-prompt">&gt;</span>
                <span>WAITING FOR GAME DEPLOYMENT...</span>
              </div>
            </div>
          ) : (
            <div className="retro-grid-3">
              {games.map((game) => (
                <div key={game.objectAddress} className="retro-slot-machine">
                  <div className="retro-machine-screen">
                    <div style={{ fontSize: '2rem', marginBottom: '10px' }}>
                      {getGameIcon(game.name, game.iconUrl).startsWith('/') ? (
                        <img 
                          src={getGameIcon(game.name, game.iconUrl)} 
                          alt={game.name}
                          style={{ width: '2rem', height: '2rem' }}
                        />
                      ) : (
                        getGameIcon(game.name, game.iconUrl)
                      )}
                    </div>
                    <div className="retro-neon-primary" style={{ fontSize: '1rem', fontWeight: 'bold' }}>
                      {game.name}
                    </div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--retro-text-muted)' }}>
                      v{game.version}
                    </div>
                  </div>
                  
                  <div className="retro-stats">
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">STATUS:</span>
                      <span className={`retro-stat-value ${game.capabilityClaimed ? 'retro-neon-primary' : ''}`} 
                            style={{ color: game.capabilityClaimed ? 'var(--retro-success)' : 'var(--retro-danger)' }}>
                        {game.capabilityClaimed ? 'ONLINE' : 'OFFLINE'}
                      </span>
                    </div>
                    
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">MIN BET:</span>
                      <span className="retro-stat-value">
                        {formatAPT(game.minBet * Math.pow(10, APT_DECIMALS))} APT
                      </span>
                    </div>
                    
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">MAX BET:</span>
                      <span className="retro-stat-value">
                        {formatAPT(game.maxBet * Math.pow(10, APT_DECIMALS))} APT
                      </span>
                    </div>
                    
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">HOUSE EDGE:</span>
                      <span className="retro-stat-value" style={{ color: 'var(--retro-secondary)' }}>
                        {game.houseEdge.toFixed(2)}%
                      </span>
                    </div>
                    
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">MAX PAYOUT:</span>
                      <span className="retro-stat-value" style={{ color: 'var(--retro-success)' }}>
                        {formatAPT(game.maxPayout * Math.pow(10, APT_DECIMALS))} APT
                      </span>
                    </div>
                  </div>
                  
                  <div style={{ marginTop: '1rem', textAlign: 'center' }}>
                    <button 
                      onClick={() => navigate(getGameRoute(game.name))}
                      disabled={!connected || !game.capabilityClaimed}
                      className={`retro-button ${!connected || !game.capabilityClaimed ? 'retro-button-secondary' : 'retro-button-success'}`}
                      style={{ width: '100%', marginBottom: '10px' }}
                    >
                      {!connected ? '🔗 CONNECT WALLET' : 
                       !game.capabilityClaimed ? '⏳ GAME OFFLINE' : 
                       '🎮 PLAY NOW'}
                    </button>
                    
                    <button 
                      onClick={() => window.open(game.websiteUrl, '_blank')}
                      className="retro-button-secondary"
                      style={{ width: '100%', fontSize: '0.5rem' }}
                    >
                      ℹ️ INFO
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Navigation */}
        <div style={{ textAlign: 'center', marginTop: '2rem' }}>
          <button 
            onClick={() => navigate('/investor-portal')}
            className="retro-button retro-button-secondary"
          >
            📊 INVESTOR PORTAL
          </button>
        </div>
      </div>
    </div>
  );
}
