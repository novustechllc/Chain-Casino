import React, { useState, useEffect } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useToast } from '@/components/ui/use-toast';
import { aptosClient } from '@/utils/aptosClient';
import { 
  CASINO_HOUSE_ADDRESS, 
  INVESTOR_TOKEN_ADDRESS, 
  SEVEN_OUT_ADDRESS,
  CCIT_DECIMALS,
  APT_DECIMALS 
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
  
  // Game stats
  gamesToday: number;
  volumeToday: number;
  houseEdge: number;
  
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
    gamesToday: 0,
    volumeToday: 0,
    houseEdge: 2.8,
    loading: true,
    error: null
  });
  const [depositAmount, setDepositAmount] = useState<string>('');
  const [withdrawAmount, setWithdrawAmount] = useState<string>('');
  const [transactionLoading, setTransactionLoading] = useState(false);


const fetchPortfolioData = async () => {
  if (!account || !connected) return;
  
  try {
    const userAddress = account.address.toStringLong();
    console.log('Making API call with address:', userAddress);
    
    // ✅ FIXED: Use "functionArguments" instead of "arguments"
    const ccitBalanceResponse = await aptosClient().view({
      payload: {
        function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::user_balance`,
        functionArguments: [userAddress]  // ← CHANGED FROM "arguments"
      }
    });
    
    console.log('CCIT balance response:', ccitBalanceResponse);
    
    // ✅ FIXED: Use "functionArguments" instead of "arguments"
    const navResponse = await aptosClient().view({
      payload: {
        function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::nav`,
        functionArguments: []  // ← CHANGED FROM "arguments"
      }
    });
    
    console.log('NAV response:', navResponse);
    
    // ✅ FIXED: Use "functionArguments" instead of "arguments"
    const totalSupplyResponse = await aptosClient().view({
      payload: {
        function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::total_supply`,
        functionArguments: []  // ← CHANGED FROM "arguments"
      }
    });
    
    console.log('Total supply response:', totalSupplyResponse);
    
    // Convert from on-chain format
    const ccitBalance = Number(ccitBalanceResponse[0]) / Math.pow(10, CCIT_DECIMALS);
    const nav = Number(navResponse[0]) / Math.pow(10, APT_DECIMALS);
    const portfolioValue = ccitBalance * nav;
    
    console.log('Calculated values:', {
      ccitBalance,
      nav,
      portfolioValue
    });
    
    setData(prev => ({
      ...prev,
      ccitBalance,
      nav,
      portfolioValue,
      loading: false
    }));
    
  } catch (error) {
    console.error('Error fetching portfolio data:', error);
    setData(prev => ({
      ...prev,
      error: `Failed to fetch portfolio data: ${error}`,
      loading: false
    }));
  }
};

// Enhanced useEffect with additional debugging
useEffect(() => {
  console.log('useEffect triggered - connected:', connected, 'account:', account);
  
  if (connected && account) {
    console.log('Wallet connected, fetching data...');
    setData(prev => ({ ...prev, loading: true, error: null }));
    
    // Add small delay to ensure wallet is fully connected
    setTimeout(() => {
      fetchPortfolioData();
      fetchTreasuryData();
    }, 100);
  } else {
    console.log('Wallet not connected, clearing data');
    setData(prev => ({
      ...prev,
      ccitBalance: 0,
      nav: 0,
      portfolioValue: 0,
      loading: false,
      error: null
    }));
  }
}, [connected, account]);

// Add this debug function to help troubleshoot
const debugWalletState = () => {
  console.log('=== WALLET DEBUG INFO ===');
  console.log('Connected:', connected);
  console.log('Account:', account);
  console.log('Account address:', account?.address);
  console.log('Account address toString:', account?.address?.toString());
  console.log('Account address toStringLong:', account?.address?.toStringLong());
  console.log('========================');
};

// Add this button to your JSX for debugging (temporary)
{process.env.NODE_ENV === 'development' && (
  <Button onClick={debugWalletState} className="mb-4">
    Debug Wallet State
  </Button>
)}

  // Fetch treasury data with correct function signatures
const fetchTreasuryData = async () => {
  try {
    console.log('Fetching treasury data...');
    
    // ✅ FIXED: Use "functionArguments" instead of "arguments"
    const centralTreasuryResponse = await aptosClient().view({
      payload: {
        function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::central_treasury_balance`,
        functionArguments: []  // ← CHANGED FROM "arguments"
      }
    });
    
    console.log('Central treasury response:', centralTreasuryResponse);
    
    // ✅ FIXED: Use "functionArguments" instead of "arguments"
    const totalTreasuryResponse = await aptosClient().view({
      payload: {
        function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::treasury_balance`,
        functionArguments: []  // ← CHANGED FROM "arguments"
      }
    });
    
    console.log('Total treasury response:', totalTreasuryResponse);
    
    // Calculate game reserves as difference
    const centralTreasury = Number(centralTreasuryResponse[0]) / Math.pow(10, APT_DECIMALS);
    const totalTreasury = Number(totalTreasuryResponse[0]) / Math.pow(10, APT_DECIMALS);
    const gameReserves = totalTreasury - centralTreasury;
    
    console.log('Treasury calculation:', {
      central: centralTreasury,
      total: totalTreasury,
      games: gameReserves
    });
    
    setData(prev => ({
      ...prev,
      centralTreasury,
      gameReserves,
      totalTreasury
    }));
    
  } catch (error) {
    console.error('Error fetching treasury data:', error);
    setData(prev => ({
      ...prev,
      error: `Failed to fetch treasury data: ${error}`
    }));
  }
};

  // Fetch all data on component mount and wallet connection
  useEffect(() => {
    if (connected && account) {
      setData(prev => ({ ...prev, loading: true, error: null }));
      fetchPortfolioData();
      fetchTreasuryData();
    }
  }, [connected, account]);

  // Handle deposit
  const handleDeposit = async () => {
    if (!depositAmount || !account) return;
    
    setTransactionLoading(true);
    try {
      const amount = parseFloat(depositAmount);
      if (isNaN(amount) || amount <= 0) {
        throw new Error('Invalid deposit amount');
      }
      
      // Convert to on-chain format (APT has 8 decimals)
      const amountInOctas = Math.floor(amount * Math.pow(10, APT_DECIMALS));
      
      const transaction = {
        data: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::deposit_and_mint`,
          arguments: [amountInOctas.toString()]
        }
      };
      
      console.log('Submitting deposit transaction:', transaction);
      
      const response = await signAndSubmitTransaction(transaction);
      console.log('Transaction submitted:', response);
      
      // Wait for transaction to be confirmed
      await aptosClient().waitForTransaction({
        transactionHash: response.hash
      });
      
      toast({
        title: "Success",
        description: `Deposited ${amount} APT successfully!`
      });
      
      setDepositAmount('');
      // Refresh data
      fetchPortfolioData();
      fetchTreasuryData();
      
    } catch (error) {
      console.error('Deposit error:', error);
      toast({
        variant: "destructive",
        title: "Error",
        description: `Deposit failed: ${error}`
      });
    } finally {
      setTransactionLoading(false);
    }
  };

  // Handle withdraw
  const handleWithdraw = async () => {
    if (!withdrawAmount || !account) return;
    
    setTransactionLoading(true);
    try {
      const amount = parseFloat(withdrawAmount);
      if (isNaN(amount) || amount <= 0) {
        throw new Error('Invalid withdraw amount');
      }
      
      // Convert to on-chain format (CCIT has 8 decimals)
      const amountInTokens = Math.floor(amount * Math.pow(10, CCIT_DECIMALS));
      
      const transaction = {
        data: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::redeem`,
          arguments: [amountInTokens.toString()]
        }
      };
      
      console.log('Submitting withdraw transaction:', transaction);
      
      const response = await signAndSubmitTransaction(transaction);
      console.log('Transaction submitted:', response);
      
      // Wait for transaction to be confirmed
      await aptosClient().waitForTransaction({
        transactionHash: response.hash
      });
      
      toast({
        title: "Success",
        description: `Withdrew ${amount} CCIT successfully!`
      });
      
      setWithdrawAmount('');
      // Refresh data
      fetchPortfolioData();
      fetchTreasuryData();
      
    } catch (error) {
      console.error('Withdraw error:', error);
      toast({
        variant: "destructive",
        title: "Error",
        description: `Withdraw failed: ${error}`
      });
    } finally {
      setTransactionLoading(false);
    }
  };

  if (!connected) {
    return (
      <div className="min-h-screen bg-gray-900 flex items-center justify-center p-4">
        <Card className="max-w-md mx-auto">
          <CardHeader>
            <CardTitle className="text-center text-white">
              🎰 ChainCasino CCIT Portal
            </CardTitle>
          </CardHeader>
          <CardContent className="text-center">
            <p className="text-gray-300 mb-4">
              Connect your wallet to access the investor portal
            </p>
            <p className="text-sm text-gray-400">
              Use the wallet button in the top right corner
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 p-4">
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-white mb-4">
            🎰 ChainCasino CCIT
          </h1>
          <p className="text-xl text-gray-300">
            Investor Portal - Welcome back, Player!
          </p>
          <p className="text-sm text-gray-400 mt-2">
            Connected: {account?.address.toString().slice(0, 8)}...{account?.address.toString().slice(-6)}
          </p>
          {data.loading && (
            <p className="text-blue-400 mt-2">Loading portfolio data...</p>
          )}
          {data.error && (
            <p className="text-red-400 mt-2 text-sm">{data.error}</p>
          )}
        </div>

        {/* Main Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {/* Portfolio Overview */}
          <Card className="bg-gray-800 border-gray-700">
            <CardHeader>
              <CardTitle className="text-blue-400">💰 Portfolio</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-center mb-4">
                <div className="text-3xl font-bold text-white mb-2">
                  {data.ccitBalance.toFixed(2)}
                </div>
                <div className="text-sm text-gray-400">CCIT TOKENS</div>
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-400">NAV:</span>
                  <span className="text-white">{data.nav.toFixed(4)} APT</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Total Value:</span>
                  <span className="text-white">{data.portfolioValue.toFixed(2)} APT</span>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Deposit/Withdraw */}
          <Card className="bg-gray-800 border-gray-700">
            <CardHeader>
              <CardTitle className="text-purple-400">💸 Deposit/Withdraw</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                <div>
                  <label className="text-sm text-gray-400 mb-2 block">
                    Deposit Amount (APT)
                  </label>
                  <Input 
                    type="number" 
                    placeholder="0.00" 
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    className="bg-gray-700 border-gray-600 text-white"
                  />
                </div>
                <Button 
                  onClick={handleDeposit}
                  className="w-full bg-green-600 hover:bg-green-700"
                  disabled={transactionLoading || !depositAmount}
                >
                  {transactionLoading ? 'Processing...' : 'DEPOSIT & MINT'}
                </Button>
                
                <div>
                  <label className="text-sm text-gray-400 mb-2 block">
                    Withdraw Amount (CCIT)
                  </label>
                  <Input 
                    type="number" 
                    placeholder="0.00" 
                    value={withdrawAmount}
                    onChange={(e) => setWithdrawAmount(e.target.value)}
                    className="bg-gray-700 border-gray-600 text-white"
                  />
                </div>
                <Button 
                  onClick={handleWithdraw}
                  className="w-full bg-red-600 hover:bg-red-700"
                  disabled={transactionLoading || !withdrawAmount}
                >
                  {transactionLoading ? 'Processing...' : 'REDEEM'}
                </Button>
              </div>
            </CardContent>
          </Card>

          {/* Treasury Overview */}
          <Card className="bg-gray-800 border-gray-700">
            <CardHeader>
              <CardTitle className="text-yellow-400">🏦 Treasury</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div className="text-center">
                  <div className="text-2xl font-bold text-white">
                    {data.totalTreasury.toFixed(2)}
                  </div>
                  <div className="text-sm text-gray-400">TOTAL APT</div>
                </div>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-400">Central:</span>
                    <span className="text-white">{data.centralTreasury.toFixed(2)} APT</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">Games:</span>
                    <span className="text-white">{data.gameReserves.toFixed(2)} APT</span>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Game Stats */}
          <Card className="bg-gray-800 border-gray-700 md:col-span-2">
            <CardHeader>
              <CardTitle className="text-green-400">🎲 Game Stats</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-3 gap-4 text-center">
                <div>
                  <div className="text-xl font-bold text-white">{data.gamesToday}</div>
                  <div className="text-sm text-gray-400">Games Today</div>
                </div>
                <div>
                  <div className="text-xl font-bold text-white">{data.volumeToday.toFixed(1)} APT</div>
                  <div className="text-sm text-gray-400">Volume Today</div>
                </div>
                <div>
                  <div className="text-xl font-bold text-white">{data.houseEdge}%</div>
                  <div className="text-sm text-gray-400">House Edge</div>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Quick Actions */}
          <Card className="bg-gray-800 border-gray-700">
            <CardHeader>
              <CardTitle className="text-cyan-400">⚡ Quick Actions</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <Button 
                  className="w-full bg-blue-600 hover:bg-blue-700"
                  onClick={() => window.open('/seven-out', '_blank')}
                >
                  🎲 PLAY SEVEN OUT
                </Button>
                <Button 
                  className="w-full bg-gray-600 hover:bg-gray-700"
                  onClick={() => {
                    fetchPortfolioData();
                    fetchTreasuryData();
                  }}
                >
                  🔄 REFRESH DATA
                </Button>
                <Button 
                  className="w-full bg-gray-600 hover:bg-gray-700"
                  onClick={() => toast({
                    title: "Coming Soon",
                    description: "Analytics dashboard coming soon!"
                  })}
                >
                  📊 VIEW ANALYTICS
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Footer */}
        <div className="text-center mt-8 text-gray-400">
          <p>ChainCasino CCIT • Built on Aptos • {new Date().getFullYear()}</p>
          <p className="text-sm mt-2">
            Contracts: House({CASINO_HOUSE_ADDRESS.slice(0, 6)}...) • 
            Token({INVESTOR_TOKEN_ADDRESS.slice(0, 6)}...) • 
            Game({SEVEN_OUT_ADDRESS.slice(0, 6)}...)
          </p>
        </div>
      </div>
    </div>
  );
};

export default InvestorPortal;
