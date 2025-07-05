import React, { useState, useEffect } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useToast } from '@/components/ui/use-toast';
import { aptosClient } from '@/utils/aptosClient';
import { 
  CASINO_HOUSE_ADDRESS, 
  INVESTOR_TOKEN_ADDRESS, 
  CCIT_DECIMALS,
  APT_DECIMALS,
  NAV_SCALE,
  ERROR_MESSAGES,
  SUCCESS_MESSAGES
} from '@/constants/chaincasino';

interface PortalData {
  // Portfolio data
  ccitBalance: number;
  nav: number;
  portfolioValue: number;
  
  // Treasury data
  centralTreasury: number;
  gameReserves: number;
  totalTreasury: number;
  totalSupply: number;
  
  // APT balance
  aptBalance: number;
  
  // Loading states
  loading: boolean;
  error: string | null;
}

const InvestorPortal: React.FC = () => {
  const { account, connected, signAndSubmitTransaction } = useWallet();
  const { toast } = useToast();
  
  const [data, setData] = useState<PortalData>({
    ccitBalance: 0,
    nav: 0,
    portfolioValue: 0,
    centralTreasury: 0,
    gameReserves: 0,
    totalTreasury: 0,
    totalSupply: 0,
    aptBalance: 0,
    loading: true,
    error: null
  });
  
  const [depositAmount, setDepositAmount] = useState<string>('');
  const [withdrawAmount, setWithdrawAmount] = useState<string>('');
  const [transactionLoading, setTransactionLoading] = useState(false);
  const [showDepositModal, setShowDepositModal] = useState(false);
  const [showWithdrawModal, setShowWithdrawModal] = useState(false);
  const [dataLoading, setDataLoading] = useState(false);

  // Format numbers for display
  const formatAPT = (amount: number): string => amount.toFixed(4);
  const formatCCIT = (amount: number): string => amount.toFixed(3);
  const formatPercentage = (value: number): string => `${value.toFixed(2)}%`;

  // Fetch portfolio data for connected user
  const fetchPortfolioData = async () => {
    if (!account || !connected) return;
    
    try {
      const userAddress = account.address.toStringLong();
      
      // Fetch CCIT balance
      const ccitBalanceResponse = await aptosClient().view({
        payload: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::user_balance`,
          functionArguments: [userAddress]
        }
      });
      
      // Fetch NAV
      const navResponse = await aptosClient().view({
        payload: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::nav`,
          functionArguments: []
        }
      });
      
      // Fetch APT balance
      const aptBalanceResponse = await aptosClient().getAccountAPTAmount({
        accountAddress: userAddress
      });
      
      // Convert from on-chain format - NAV is already scaled by NAV_SCALE
      const ccitBalance = Number(ccitBalanceResponse[0]) / Math.pow(10, CCIT_DECIMALS);
      const navRaw = Number(navResponse[0]);
      // NAV starts at 1,000,000 (which represents 1.0 when divided by NAV_SCALE)
      const nav = navRaw / NAV_SCALE;
      const portfolioValue = ccitBalance * nav;
      const aptBalance = Number(aptBalanceResponse) / Math.pow(10, APT_DECIMALS);
      
      setData(prev => ({
        ...prev,
        ccitBalance,
        nav,
        portfolioValue,
        aptBalance
      }));
      
    } catch (error) {
      console.error('Error fetching portfolio data:', error);
      setData(prev => ({
        ...prev,
        error: `Failed to fetch portfolio data: ${error}`
      }));
    }
  };

  // Fetch treasury data
  const fetchTreasuryData = async () => {
    try {
      // Fetch central treasury balance
      const centralTreasuryResponse = await aptosClient().view({
        payload: {
          function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::central_treasury_balance`,
          functionArguments: []
        }
      });
      
      // Fetch total treasury balance
      const totalTreasuryResponse = await aptosClient().view({
        payload: {
          function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::treasury_balance`,
          functionArguments: []
        }
      });
      
      // Fetch total supply
      const totalSupplyResponse = await aptosClient().view({
        payload: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::total_supply`,
          functionArguments: []
        }
      });
      
      // Calculate values
      const centralTreasury = Number(centralTreasuryResponse[0]) / Math.pow(10, APT_DECIMALS);
      const totalTreasury = Number(totalTreasuryResponse[0]) / Math.pow(10, APT_DECIMALS);
      const gameReserves = totalTreasury - centralTreasury;
      const totalSupply = Number(totalSupplyResponse[0]) / Math.pow(10, CCIT_DECIMALS);
      
      setData(prev => ({
        ...prev,
        centralTreasury,
        totalTreasury,
        gameReserves,
        totalSupply
      }));
      
    } catch (error) {
      console.error('Error fetching treasury data:', error);
      setData(prev => ({
        ...prev,
        error: `Failed to fetch treasury data: ${error}`
      }));
    }
  };

  // Fetch all data with better loading states
  const fetchAllData = async () => {
    setDataLoading(true);
    try {
      await Promise.all([
        fetchPortfolioData(),
        fetchTreasuryData()
      ]);
    } finally {
      setDataLoading(false);
    }
  };

  // Handle deposit
  const handleDeposit = async () => {
    if (!connected || !account) {
      toast({
        title: "Wallet not connected",
        description: ERROR_MESSAGES.WALLET_NOT_CONNECTED,
        variant: "destructive",
      });
      return;
    }

    const amount = parseFloat(depositAmount);
    if (isNaN(amount) || amount <= 0) {
      toast({
        title: "Invalid amount",
        description: ERROR_MESSAGES.INVALID_AMOUNT,
        variant: "destructive",
      });
      return;
    }

    if (amount > data.aptBalance) {
      toast({
        title: "Insufficient balance",
        description: ERROR_MESSAGES.INSUFFICIENT_BALANCE,
        variant: "destructive",
      });
      return;
    }

    setTransactionLoading(true);
    try {
      const amountInOctas = Math.floor(amount * Math.pow(10, APT_DECIMALS));
      
      const transaction = await signAndSubmitTransaction({
        data: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::deposit_and_mint`,
          functionArguments: [amountInOctas.toString()],
        },
      });

      await aptosClient().waitForTransaction({
        transactionHash: transaction.hash,
      });

      toast({
        title: "Success!",
        description: SUCCESS_MESSAGES.DEPOSIT_SUCCESS,
      });

      setDepositAmount('');
      setShowDepositModal(false);
      await fetchAllData();
    } catch (error) {
      console.error('Deposit error:', error);
      toast({
        title: "Transaction failed",
        description: ERROR_MESSAGES.TRANSACTION_FAILED,
        variant: "destructive",
      });
    } finally {
      setTransactionLoading(false);
    }
  };

  // Handle withdraw
  const handleWithdraw = async () => {
    if (!connected || !account) {
      toast({
        title: "Wallet not connected",
        description: ERROR_MESSAGES.WALLET_NOT_CONNECTED,
        variant: "destructive",
      });
      return;
    }

    const amount = parseFloat(withdrawAmount);
    if (isNaN(amount) || amount <= 0) {
      toast({
        title: "Invalid amount",
        description: ERROR_MESSAGES.INVALID_AMOUNT,
        variant: "destructive",
      });
      return;
    }

    if (amount > data.ccitBalance) {
      toast({
        title: "Insufficient balance",
        description: ERROR_MESSAGES.INSUFFICIENT_BALANCE,
        variant: "destructive",
      });
      return;
    }

    setTransactionLoading(true);
    try {
      const amountInCCIT = Math.floor(amount * Math.pow(10, CCIT_DECIMALS));
      
      const transaction = await signAndSubmitTransaction({
        data: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::redeem`,
          functionArguments: [amountInCCIT.toString()],
        },
      });

      await aptosClient().waitForTransaction({
        transactionHash: transaction.hash,
      });

      toast({
        title: "Success!",
        description: SUCCESS_MESSAGES.REDEEM_SUCCESS,
      });

      setWithdrawAmount('');
      setShowWithdrawModal(false);
      await fetchAllData();
    } catch (error) {
      console.error('Withdraw error:', error);
      toast({
        title: "Transaction failed",
        description: ERROR_MESSAGES.TRANSACTION_FAILED,
        variant: "destructive",
      });
    } finally {
      setTransactionLoading(false);
    }
  };

  // Auto-refresh data
  useEffect(() => {
    if (connected) {
      fetchAllData();
      const interval = setInterval(() => {
        // Don't show loading spinner for background refreshes
        setDataLoading(false);
        fetchAllData();
      }, 10000); // Refresh every 10 seconds
      return () => clearInterval(interval);
    }
  }, [connected]);

  // Initial loading state - only show if we haven't loaded any data yet
  if (!connected) {
    return (
      <div className="retro-body">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div className="retro-flex-center min-h-screen">
          <div className="retro-card">
            <div className="retro-terminal-header">/// WALLET CONNECTION REQUIRED ///</div>
            <div className="text-center">
              <div className="retro-neon-text text-2xl mb-4">🎰 CHAINCASINO</div>
              <p className="retro-text-primary mb-4">
                Please connect your wallet to access the investor portal
              </p>
              <p className="retro-text-muted">
                {ERROR_MESSAGES.WALLET_NOT_CONNECTED}
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Calculate 24h change (mock for now)
  const navChange = 3.2;
  const profitToday = data.totalTreasury * 0.02; // Mock 2% daily profit

  return (
    <div className="retro-body">
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      <div className="container mx-auto px-4 py-8">
        {/* Header */}
        <header className="text-center mb-8 p-6 border-b-4 border-yellow-400">
          <div className="retro-neon-text text-4xl mb-4">🎰 CHAINCASINO</div>
          <div className="retro-text-primary text-xl uppercase tracking-widest">
            INVESTOR TERMINAL
          </div>
          <div className="flex justify-center items-center gap-4 mt-4">
            <span className="retro-text-accent text-lg">🍒</span>
            <span className="retro-text-accent text-lg">💎</span>
            <span className="retro-text-accent text-lg">🎲</span>
            <span className="retro-text-accent text-lg">⭐</span>
            <span className="retro-text-accent text-lg">💰</span>
          </div>
          <p className="retro-text-muted mt-2">
            Connected: {account?.address?.toStringLong().slice(0, 6)}...{account?.address?.toStringLong().slice(-4)}
          </p>
        </header>

        {/* Main Grid */}
        <div className="retro-grid-2 mb-8">
          {/* Portfolio Panel */}
          <div className="retro-card">
            <div className="retro-pixel-font text-sm text-purple-300 mb-6 flex items-center gap-2">
              <div className="w-4 h-4 bg-purple-400"></div>
              PORTFOLIO & NAV
            </div>
            
            <div className="retro-display mb-4">
              <div className="retro-display-value">
                {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(data.portfolioValue)}`}
              </div>
              <div className="retro-display-label">PORTFOLIO VALUE</div>
            </div>

            <div className="retro-stats">
              <div className="retro-stat-line">
                <span className="retro-stat-name">CURRENT NAV:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : formatAPT(data.nav)}
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">24H CHANGE:</span>
                <span className="retro-stat-value text-green-400">+{formatPercentage(navChange)}</span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">CCIT BALANCE:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : formatCCIT(data.ccitBalance)}
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">APT BALANCE:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : formatAPT(data.aptBalance)}
                </span>
              </div>
            </div>
            
            <div className="flex gap-3 mt-6">
              <button 
                className="retro-button flex-1"
                onClick={() => setShowDepositModal(true)}
              >
                INSERT COIN
              </button>
              <button 
                className="retro-button-secondary flex-1"
                onClick={() => setShowWithdrawModal(true)}
              >
                CASH OUT
              </button>
            </div>
          </div>

          {/* Treasury Panel */}
          <div className="retro-card">
            <div className="retro-pixel-font text-sm text-cyan-300 mb-6 flex items-center gap-2">
              <div className="w-4 h-4 bg-cyan-400"></div>
              CASINO TREASURY
            </div>
            
            <div className="retro-pixel-chart mb-4">
              <div className="retro-chart-bar" style={{'--height': '70%', left: '20px'} as React.CSSProperties}></div>
              <div className="retro-chart-bar" style={{'--height': '50%', left: '50px'} as React.CSSProperties}></div>
              <div className="retro-chart-bar" style={{'--height': '85%', left: '80px'} as React.CSSProperties}></div>
              <div className="retro-chart-bar" style={{'--height': '40%', left: '110px'} as React.CSSProperties}></div>
              <div className="retro-chart-bar" style={{'--height': '60%', left: '140px'} as React.CSSProperties}></div>
              <div className="retro-chart-bar" style={{'--height': '75%', left: '170px'} as React.CSSProperties}></div>
            </div>

            <div className="retro-stats">
              <div className="retro-stat-line">
                <span className="retro-stat-name">CENTRAL VAULT:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(data.centralTreasury)} APT`}
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">GAME VAULTS:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(data.gameReserves)} APT`}
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">TOTAL TREASURY:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(data.totalTreasury)} APT`}
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">PROFIT TODAY:</span>
                <span className="retro-stat-value text-green-400">+{formatAPT(profitToday)} APT</span>
              </div>
            </div>
          </div>
        </div>

        {/* Deposit Modal */}
        {showDepositModal && (
          <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50">
            <div className="retro-card max-w-md w-full mx-4">
              <div className="retro-pixel-font text-sm text-green-300 mb-6 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-4 h-4 bg-green-400"></div>
                  INSERT COIN - DEPOSIT APT
                </div>
                <button 
                  onClick={() => setShowDepositModal(false)}
                  className="retro-text-primary text-xl"
                >
                  &times;
                </button>
              </div>
              
              <div className="space-y-4">
                <div>
                  <label className="retro-text-secondary text-sm block mb-2">Amount (APT)</label>
                  <div className="flex gap-2">
                    <input
                      type="number"
                      value={depositAmount}
                      onChange={(e) => setDepositAmount(e.target.value)}
                      placeholder="Enter APT amount"
                      className="retro-input flex-1"
                      step="0.0001"
                      min="0"
                    />
                    <button
                      onClick={() => setDepositAmount(data.aptBalance.toString())}
                      className="retro-button-secondary px-3 text-xs"
                    >
                      MAX
                    </button>
                  </div>
                </div>
                
                {depositAmount && (
                  <div className="retro-stats">
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">YOU WILL RECEIVE:</span>
                      <span className="retro-stat-value">
                        {formatCCIT(parseFloat(depositAmount) / data.nav)} CCIT
                      </span>
                    </div>
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">EXCHANGE RATE:</span>
                      <span className="retro-stat-value">1 APT = {formatCCIT(1 / data.nav)} CCIT</span>
                    </div>
                  </div>
                )}
                
                <div className="flex gap-3">
                  <button
                    onClick={() => setShowDepositModal(false)}
                    className="retro-button-secondary flex-1"
                  >
                    CANCEL
                  </button>
                  <button
                    onClick={handleDeposit}
                    disabled={transactionLoading || !depositAmount}
                    className="retro-button-success flex-1"
                  >
                    {transactionLoading ? (
                      <span className="flex items-center justify-center gap-2">
                        <span className="retro-loading"></span>
                        PROCESSING...
                      </span>
                    ) : (
                      '💰 DEPOSIT'
                    )}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Withdraw Modal */}
        {showWithdrawModal && (
          <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50">
            <div className="retro-card max-w-md w-full mx-4">
              <div className="retro-pixel-font text-sm text-red-300 mb-6 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-4 h-4 bg-red-400"></div>
                  CASH OUT - REDEEM CCIT
                </div>
                <button 
                  onClick={() => setShowWithdrawModal(false)}
                  className="retro-text-primary text-xl"
                >
                  &times;
                </button>
              </div>
              
              <div className="space-y-4">
                <div>
                  <label className="retro-text-secondary text-sm block mb-2">Amount (CCIT)</label>
                  <div className="flex gap-2">
                    <input
                      type="number"
                      value={withdrawAmount}
                      onChange={(e) => setWithdrawAmount(e.target.value)}
                      placeholder="Enter CCIT amount"
                      className="retro-input flex-1"
                      step="0.001"
                      min="0"
                    />
                    <button
                      onClick={() => setWithdrawAmount(data.ccitBalance.toString())}
                      className="retro-button-secondary px-3 text-xs"
                    >
                      MAX
                    </button>
                  </div>
                </div>
                
                {withdrawAmount && (
                  <div className="retro-stats">
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">YOU WILL RECEIVE:</span>
                      <span className="retro-stat-value">
                        {formatAPT(parseFloat(withdrawAmount) * data.nav)} APT
                      </span>
                    </div>
                    <div className="retro-stat-line">
                      <span className="retro-stat-name">EXCHANGE RATE:</span>
                      <span className="retro-stat-value">1 CCIT = {formatAPT(data.nav)} APT</span>
                    </div>
                  </div>
                )}
                
                <div className="flex gap-3">
                  <button
                    onClick={() => setShowWithdrawModal(false)}
                    className="retro-button-secondary flex-1"
                  >
                    CANCEL
                  </button>
                  <button
                    onClick={handleWithdraw}
                    disabled={transactionLoading || !withdrawAmount}
                    className="retro-button-danger flex-1"
                  >
                    {transactionLoading ? (
                      <span className="flex items-center justify-center gap-2">
                        <span className="retro-loading"></span>
                        PROCESSING...
                      </span>
                    ) : (
                      '💸 REDEEM'
                    )}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Terminal Status */}
        <div className="retro-terminal mb-8">
          <div className="retro-terminal-header">/// INVESTOR TERMINAL STATUS ///</div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span>TREASURY AUTO-REBALANCING: ACTIVE</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span>FUNGIBLE ASSET STANDARD: ONLINE</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span>TOTAL SUPPLY: {dataLoading ? <span className="retro-loading"></span> : `${formatCCIT(data.totalSupply)} CCIT`}</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span>LATEST: NAV APPRECIATION +{formatPercentage(navChange)} &rarr; INVESTORS</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span>SYSTEM OPERATIONAL - TREASURY GROWS</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span className="retro-terminal-cursor">█</span>
          </div>
        </div>

        {/* Footer */}
        <footer className="text-center p-6 border-t-4 border-yellow-400">
          <div className="retro-pixel-font text-sm text-cyan-400 leading-relaxed">
            🎰 CHAINCASINO.APT &times; INVESTOR TERMINAL 🎰<br />
            POWERED BY APTOS MOVE 2 • FUNGIBLE ASSET STANDARD<br />
            EST. 2024 • WHERE DEFI MEETS RETRO GAMING
          </div>
        </footer>
      </div>
    </div>
  );
};

export default InvestorPortal;
