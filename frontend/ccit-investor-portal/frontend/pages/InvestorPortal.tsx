import React, { useState, useEffect } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/components/ui/use-toast';
import { aptosClient } from '@/utils/aptosClient';
import { 
  CASINO_HOUSE_ADDRESS, 
  INVESTOR_TOKEN_ADDRESS, 
  CCIT_DECIMALS,
  APT_DECIMALS,
  NAV_SCALE,
  formatAPT,
  formatCCIT,
  formatNAV,
  formatPercentage,
  ERROR_MESSAGES,
  SUCCESS_MESSAGES
} from '@/constants/chaincasino';
// Remove this import since we'll create transactions directly

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

  // Fetch portfolio data for connected user
  const fetchPortfolioData = async () => {
    if (!account || !connected) return;
    
    try {
      const userAddress = account.address.toStringLong();
      console.log('Fetching portfolio data for address:', userAddress);
      
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
      
      // Convert from on-chain format
      const ccitBalance = Number(ccitBalanceResponse[0]) / Math.pow(10, CCIT_DECIMALS);
      const navRaw = Number(navResponse[0]);
      const navScale = Math.pow(10, 8); // NAV_SCALE is 10^8
      const nav = navRaw / navScale; // NAV is scaled by NAV_SCALE
      const portfolioValue = ccitBalance * nav;
      const aptBalance = Number(aptBalanceResponse) / Math.pow(10, APT_DECIMALS);
      
      console.log('Portfolio data:', {
        ccitBalance,
        navRaw,
        navScale,
        nav,
        portfolioValue,
        aptBalance
      });
      
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
      console.log('Fetching treasury data...');
      
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
      
      console.log('Treasury data:', {
        centralTreasury,
        totalTreasury,
        gameReserves,
        totalSupply
      });
      
      setData(prev => ({
        ...prev,
        centralTreasury,
        gameReserves,
        totalTreasury,
        totalSupply,
        loading: false
      }));
      
    } catch (error) {
      console.error('Error fetching treasury data:', error);
      setData(prev => ({
        ...prev,
        error: `Failed to fetch treasury data: ${error}`,
        loading: false
      }));
    }
  };

  // Fetch all data when wallet connects
  useEffect(() => {
    if (connected && account) {
      console.log('Wallet connected, fetching data...');
      setData(prev => ({ ...prev, loading: true, error: null }));
      
      // Fetch data with small delay to ensure wallet is ready
      const timer = setTimeout(() => {
        fetchPortfolioData();
        fetchTreasuryData();
      }, 100);
      
      return () => clearTimeout(timer);
    } else {
      // Reset data when wallet disconnects
      setData(prev => ({
        ...prev,
        ccitBalance: 0,
        nav: 0,
        portfolioValue: 0,
        aptBalance: 0,
        loading: false,
        error: null
      }));
    }
  }, [connected, account]);

  // Handle deposit and mint
  const handleDeposit = async () => {
    if (!depositAmount || !account) return;
    
    setTransactionLoading(true);
    try {
      const amount = parseFloat(depositAmount);
      if (isNaN(amount) || amount <= 0) {
        throw new Error(ERROR_MESSAGES.INVALID_AMOUNT);
      }
      
      if (amount > data.aptBalance) {
        throw new Error(ERROR_MESSAGES.INSUFFICIENT_BALANCE);
      }
      
      // Convert to on-chain format (APT has 8 decimals)
      const amountInOctas = Math.floor(amount * Math.pow(10, APT_DECIMALS));
      
      console.log('Submitting deposit transaction:', {
        amount,
        amountInOctas
      });
      
      const transaction = {
        data: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::deposit_and_mint`,
          functionArguments: [amountInOctas.toString()]
        }
      };
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Transaction submitted:', response);
      
      // Wait for transaction confirmation
      await aptosClient().waitForTransaction({
        transactionHash: response.hash
      });
      
      toast({
        title: "Success",
        description: SUCCESS_MESSAGES.DEPOSIT_SUCCESS
      });
      
      setDepositAmount('');
      
      // Refresh data
      await fetchPortfolioData();
      await fetchTreasuryData();
      
    } catch (error: any) {
      console.error('Deposit error:', error);
      toast({
        variant: "destructive",
        title: "Error",
        description: error.message || ERROR_MESSAGES.TRANSACTION_FAILED
      });
    } finally {
      setTransactionLoading(false);
    }
  };

  // Handle redeem
  const handleRedeem = async () => {
    if (!withdrawAmount || !account) return;
    
    setTransactionLoading(true);
    try {
      const amount = parseFloat(withdrawAmount);
      if (isNaN(amount) || amount <= 0) {
        throw new Error(ERROR_MESSAGES.INVALID_AMOUNT);
      }
      
      if (amount > data.ccitBalance) {
        throw new Error(ERROR_MESSAGES.INSUFFICIENT_BALANCE);
      }
      
      // Convert to on-chain format (CCIT has 8 decimals)
      const amountInTokens = Math.floor(amount * Math.pow(10, CCIT_DECIMALS));
      
      console.log('Submitting redeem transaction:', {
        amount,
        amountInTokens
      });
      
      const transaction = {
        data: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::redeem`,
          functionArguments: [amountInTokens.toString()]
        }
      };
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Transaction submitted:', response);
      
      // Wait for transaction confirmation
      await aptosClient().waitForTransaction({
        transactionHash: response.hash
      });
      
      toast({
        title: "Success",
        description: SUCCESS_MESSAGES.REDEEM_SUCCESS
      });
      
      setWithdrawAmount('');
      
      // Refresh data
      await fetchPortfolioData();
      await fetchTreasuryData();
      
    } catch (error: any) {
      console.error('Redeem error:', error);
      toast({
        variant: "destructive",
        title: "Error",
        description: error.message || ERROR_MESSAGES.TRANSACTION_FAILED
      });
    } finally {
      setTransactionLoading(false);
    }
  };

  // Render loading state
  if (data.loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 flex items-center justify-center">
        <Card className="w-full max-w-md">
          <CardContent className="p-8 text-center">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white mx-auto mb-4"></div>
            <p className="text-lg">Loading investor data...</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  // Render error state
  if (data.error) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 flex items-center justify-center">
        <Card className="w-full max-w-md">
          <CardContent className="p-8 text-center">
            <div className="text-red-500 mb-4">
              <svg className="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
              </svg>
            </div>
            <p className="text-lg mb-4">Error loading data</p>
            <p className="text-sm text-gray-400 mb-4">{data.error}</p>
            <Button onClick={() => window.location.reload()}>
              Retry
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  // Render wallet connection prompt
  if (!connected) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 flex items-center justify-center">
        <Card className="w-full max-w-md">
          <CardContent className="p-8 text-center">
            <div className="text-purple-400 mb-4">
              <svg className="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <h2 className="text-2xl font-bold mb-4 text-white">🎰 ChainCasino Investor Portal</h2>
            <p className="text-gray-300 mb-6">
              Connect your wallet to start investing in the casino treasury and earn yield through rising NAV.
            </p>
            <p className="text-sm text-gray-400">
              {ERROR_MESSAGES.WALLET_NOT_CONNECTED}
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  // Debug logging
  console.log('Current data state:', data);
  
  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 p-4">
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-white mb-2">🎰 ChainCasino Investor Portal</h1>
          <p className="text-xl text-gray-300">
            Invest in the casino treasury and earn yield through rising NAV
          </p>
          <p className="text-sm text-gray-400 mt-2">
            Connected: {account?.address?.toStringLong().slice(0, 6)}...{account?.address?.toStringLong().slice(-4)}
          </p>
        </div>

        {/* Portfolio Overview */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <Card className="bg-gradient-to-r from-green-600 to-green-700 text-white">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Portfolio Value</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{data.portfolioValue.toFixed(4)} APT</div>
              <p className="text-xs text-green-100">
                {data.ccitBalance.toFixed(3)} CCIT × {data.nav.toFixed(4)} NAV
              </p>
            </CardContent>
          </Card>

          <Card className="bg-gradient-to-r from-blue-600 to-blue-700 text-white">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Current NAV</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{data.nav.toFixed(4)} APT</div>
              <p className="text-xs text-blue-100">
                Per CCIT Token
              </p>
            </CardContent>
          </Card>

          <Card className="bg-gradient-to-r from-purple-600 to-purple-700 text-white">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">APT Balance</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{data.aptBalance.toFixed(2)} APT</div>
              <p className="text-xs text-purple-100">
                Available for investment
              </p>
            </CardContent>
          </Card>
        </div>

        {/* Treasury Statistics */}
        <Card className="mb-8">
          <CardHeader>
            <CardTitle className="text-xl">🏦 Treasury Overview</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div className="text-center">
                <div className="text-2xl font-bold text-blue-600">
                  {data.totalTreasury.toFixed(2)} APT
                </div>
                <p className="text-sm text-gray-600">Total Treasury</p>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-green-600">
                  {data.centralTreasury.toFixed(2)} APT
                </div>
                <p className="text-sm text-gray-600">Central Treasury</p>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-purple-600">
                  {data.gameReserves.toFixed(2)} APT
                </div>
                <p className="text-sm text-gray-600">Game Reserves</p>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-orange-600">
                  {data.totalSupply.toFixed(2)} CCIT
                </div>
                <p className="text-sm text-gray-600">Total Supply</p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Investment Actions */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Deposit & Mint */}
          <Card>
            <CardHeader>
              <CardTitle className="text-xl text-green-600">💰 Deposit & Mint CCIT</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label htmlFor="deposit-amount" className="text-sm font-medium">
                  Deposit Amount (APT)
                </Label>
                <Input
                  id="deposit-amount"
                  type="number"
                  placeholder="0.00"
                  value={depositAmount}
                  onChange={(e) => setDepositAmount(e.target.value)}
                  className="mt-1"
                  min="0"
                  step="0.01"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Available: {data.aptBalance.toFixed(2)} APT
                </p>
              </div>
              
              {depositAmount && (
                <div className="bg-green-50 p-3 rounded-md">
                  <p className="text-sm text-green-800">
                    You will receive: ~{(parseFloat(depositAmount) / data.nav).toFixed(3)} CCIT
                  </p>
                </div>
              )}
              
              <Button
                onClick={handleDeposit}
                disabled={!depositAmount || transactionLoading || parseFloat(depositAmount) <= 0}
                className="w-full bg-green-600 hover:bg-green-700"
              >
                {transactionLoading ? 'Processing...' : 'Deposit APT & Mint CCIT'}
              </Button>
            </CardContent>
          </Card>

          {/* Redeem */}
          <Card>
            <CardHeader>
              <CardTitle className="text-xl text-red-600">🔄 Redeem CCIT</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label htmlFor="withdraw-amount" className="text-sm font-medium">
                  Redeem Amount (CCIT)
                </Label>
                <Input
                  id="withdraw-amount"
                  type="number"
                  placeholder="0.00"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  className="mt-1"
                  min="0"
                  step="0.01"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Available: {data.ccitBalance.toFixed(3)} CCIT
                </p>
              </div>
              
              {withdrawAmount && (
                <div className="bg-red-50 p-3 rounded-md">
                  <p className="text-sm text-red-800">
                    You will receive: ~{(parseFloat(withdrawAmount) * data.nav).toFixed(4)} APT
                  </p>
                </div>
              )}
              
              <Button
                onClick={handleRedeem}
                disabled={!withdrawAmount || transactionLoading || parseFloat(withdrawAmount) <= 0}
                className="w-full bg-red-600 hover:bg-red-700"
                variant="destructive"
              >
                {transactionLoading ? 'Processing...' : 'Redeem CCIT for APT'}
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default InvestorPortal;
