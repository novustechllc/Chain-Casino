import React, { useState, useEffect } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useToast } from '@/components/ui/use-toast';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

import { aptosClient } from '@/utils/aptosClient';
import { 
  playSevenOut, 
  clearGameResult, 
  getViewFunctions,
  parseGameResult,
  parseGameConfig,
  GameResult,
  GameConfig 
} from '@/entry-functions/chaincasino';
import { formatAPT, GAMES_ADDRESS } from '@/constants/chaincasino';

const SevenOut: React.FC = () => {
  const { account, signAndSubmitTransaction } = useWallet();
  const { toast } = useToast();
  
  // Game state
  const [gameConfig, setGameConfig] = useState<GameConfig | null>(null);
  const [gameResult, setGameResult] = useState<GameResult | null>(null);
  const [betAmount, setBetAmount] = useState<string>('0.02');
  const [isLoading, setIsLoading] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);

  // Load game config and check for existing result
  useEffect(() => {
    if (account) {
      loadGameConfig();
      checkExistingResult();
    }
  }, [account]);

  const loadGameConfig = async () => {
    try {
      const configData = await aptosClient().view({
        payload: {
          function: getViewFunctions().getGameConfig,
          functionArguments: []
        }
      });
      const config = parseGameConfig(configData);
      setGameConfig(config);
    } catch (error) {
      console.error('Failed to load game config:', error);
    }
  };

  const checkExistingResult = async () => {
    if (!account?.address) return;
    
    try {
      const hasResult = await aptosClient().view({
        payload: {
          function: getViewFunctions().hasGameResult,
          functionArguments: [account.address.toString()]
        }
      });
      
      if (hasResult[0]) {
        const resultData = await aptosClient().view({
          payload: {
            function: getViewFunctions().getGameResult,  // Changed from getUserGameResult
            functionArguments: [account.address.toString()]
          }
        });
        
        console.log('Raw result data:', resultData);
        
        // Handle the result data properly
        if (resultData && Array.isArray(resultData) && resultData.length > 0) {
          const result = parseGameResult(resultData);
          setGameResult(result);
        }
      }
    } catch (error) {
      console.error('Failed to check existing result:', error);
    }
  };

  const playGame = async (betOver: boolean) => {
    if (!account || !gameConfig) return;
    
    const betAmountOctas = Math.floor(parseFloat(betAmount) * 100000000);
    
    if (betAmountOctas < gameConfig.min_bet || betAmountOctas > gameConfig.max_bet) {
      toast({
        title: "Invalid Bet Amount",
        description: `Bet must be between ${formatAPT(gameConfig.min_bet)} and ${formatAPT(gameConfig.max_bet)} APT`,
        variant: "destructive"
      });
      return;
    }

    setIsPlaying(true);
    setIsLoading(true);

    try {
      console.log('Creating transaction...');
      console.log('GAMES_ADDRESS:', GAMES_ADDRESS);
      console.log('betOver:', betOver, 'betAmount:', betAmountOctas);
      
      const transaction = playSevenOut({
        betOver,
        betAmount: betAmountOctas
      });
      
      console.log('Transaction created:', transaction);
      console.log('Transaction data:', JSON.stringify(transaction, null, 2));

      console.log('Signing transaction...');
      const response = await signAndSubmitTransaction(transaction);
      console.log('Transaction signed:', response);

      console.log('Waiting for transaction...');
      await aptosClient().waitForTransaction({ transactionHash: response.hash });
      console.log('Transaction completed');
      
      // Small delay before checking result
      setTimeout(() => {
        checkExistingResult();
      }, 1000);
      
      toast({
        title: "Game Played!",
        description: `Bet ${betOver ? 'Over' : 'Under'} 7 for ${betAmount} APT`,
        variant: "default"
      });
    } catch (error) {
      console.error('Game play failed:', error);
      console.error('Error details:', error.message, error.stack);
      toast({
        title: "Game Failed",
        description: error instanceof Error ? error.message : 'Transaction failed',
        variant: "destructive"
      });
    } finally {
      setIsLoading(false);
      setIsPlaying(false);
    }
  };

  const clearResult = async () => {
    if (!account) return;
    
    setIsLoading(true);
    try {
      const transaction = clearGameResult();
      const response = await signAndSubmitTransaction(transaction);
      await aptosClient().waitForTransaction({ transactionHash: response.hash });
      
      setGameResult(null);
      toast({
        title: "Result Cleared",
        description: "Ready for next game",
        variant: "default"
      });
    } catch (error) {
      console.error('Clear result failed:', error);
      toast({
        title: "Clear Failed",
        description: error instanceof Error ? error.message : 'Failed to clear result',
        variant: "destructive"
      });
    } finally {
      setIsLoading(false);
    }
  };

  const getOutcomeText = (outcome: number) => {
    switch (outcome) {
      case 0: return 'LOSE';
      case 1: return 'WIN';
      case 2: return 'PUSH';
      default: return 'UNKNOWN';
    }
  };

  const getOutcomeColor = (outcome: number) => {
    switch (outcome) {
      case 0: return 'text-red-400';
      case 1: return 'text-green-400';
      case 2: return 'text-yellow-400';
      default: return 'text-gray-400';
    }
  };

  if (!account) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 flex items-center justify-center p-4">
        <Card className="w-full max-w-md bg-gray-800 border-purple-500">
          <CardContent className="p-8 text-center">
            <div className="text-6xl mb-4">🎲</div>
            <h2 className="text-2xl font-bold text-purple-400 mb-4">SevenOut</h2>
            <p className="text-gray-300 mb-6">Connect your wallet to play</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 p-4">
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="text-8xl mb-4">🎲</div>
          <h1 className="text-4xl font-bold text-purple-400 mb-2">SevenOut</h1>
          <p className="text-gray-300">Bet Over or Under 7 • 2.78% House Edge • 1.933x Payout</p>
        </div>

        {/* Game Result Display */}
        {gameResult && (
          <Card className="mb-8 bg-gray-800 border-purple-500">
            <CardHeader>
              <CardTitle className="text-center text-purple-400">Last Game Result</CardTitle>
            </CardHeader>
            <CardContent className="text-center">
              <div className="flex justify-center items-center gap-4 mb-4">
                <div className="text-6xl border-2 border-purple-500 rounded-lg p-4 bg-purple-900/20">
                  {gameResult.die1}
                </div>
                <div className="text-2xl text-purple-400">+</div>
                <div className="text-6xl border-2 border-purple-500 rounded-lg p-4 bg-purple-900/20">
                  {gameResult.die2}
                </div>
                <div className="text-2xl text-purple-400">=</div>
                <div className="text-6xl border-2 border-purple-500 rounded-lg p-4 bg-purple-900/20">
                  {gameResult.dice_sum}
                </div>
              </div>
              
              <div className="grid grid-cols-2 gap-4 text-center mb-4">
                <div>
                  <p className="text-gray-400">Bet Type</p>
                  <span className="inline-block px-3 py-1 bg-purple-900/50 border border-purple-500 rounded text-sm">
                    {gameResult.bet_type === 1 ? 'Over 7' : 'Under 7'}
                  </span>
                </div>
                <div>
                  <p className="text-gray-400">Outcome</p>
                  <span className={`inline-block px-3 py-1 bg-purple-900/50 border border-purple-500 rounded text-sm ${getOutcomeColor(gameResult.outcome)}`}>
                    {getOutcomeText(gameResult.outcome)}
                  </span>
                </div>
              </div>
              
              <div className="grid grid-cols-2 gap-4 text-center">
                <div>
                  <p className="text-gray-400">Bet Amount</p>
                  <p className="text-xl font-bold text-purple-400">{formatAPT(gameResult.bet_amount)} APT</p>
                </div>
                <div>
                  <p className="text-gray-400">Payout</p>
                  <p className="text-xl font-bold text-green-400">{formatAPT(gameResult.payout)} APT</p>
                </div>
              </div>
              
              <Button 
                onClick={clearResult} 
                disabled={isLoading}
                className="mt-4 bg-purple-600 hover:bg-purple-700"
              >
                {isLoading ? 'Clearing...' : 'Clear Result'}
              </Button>
            </CardContent>
          </Card>
        )}

        {/* Betting Interface */}
        <Card className="bg-gray-800 border-purple-500">
          <CardHeader>
            <CardTitle className="text-center text-purple-400">Place Your Bet</CardTitle>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Bet Amount Input */}
            <div className="space-y-2">
              <label className="text-sm font-medium text-gray-300">Bet Amount (APT)</label>
              <Input
                type="number"
                value={betAmount}
                onChange={(e) => setBetAmount(e.target.value)}
                step="0.01"
                min={gameConfig ? formatAPT(gameConfig.min_bet) : '0.02'}
                max={gameConfig ? formatAPT(gameConfig.max_bet) : '0.4'}
                className="bg-gray-700 border-purple-500 text-white"
                placeholder="Enter bet amount"
              />
              {gameConfig && (
                <p className="text-xs text-gray-400">
                  Min: {formatAPT(gameConfig.min_bet)} APT • Max: {formatAPT(gameConfig.max_bet)} APT
                </p>
              )}
            </div>

            {/* Betting Buttons */}
            <div className="grid grid-cols-2 gap-4">
              <Button
                onClick={() => playGame(false)}
                disabled={isLoading || isPlaying || !!gameResult}
                className="h-20 text-xl bg-red-600 hover:bg-red-700 disabled:opacity-50"
              >
                <div className="text-center">
                  <div className="text-2xl mb-1">📉</div>
                  <div>BET UNDER 7</div>
                  <div className="text-sm opacity-75">41.67% chance</div>
                </div>
              </Button>
              
              <Button
                onClick={() => playGame(true)}
                disabled={isLoading || isPlaying || !!gameResult}
                className="h-20 text-xl bg-green-600 hover:bg-green-700 disabled:opacity-50"
              >
                <div className="text-center">
                  <div className="text-2xl mb-1">📈</div>
                  <div>BET OVER 7</div>
                  <div className="text-sm opacity-75">41.67% chance</div>
                </div>
              </Button>
            </div>

            {/* Game Rules */}
            <div className="bg-gray-700 rounded-lg p-4">
              <h3 className="font-bold text-purple-400 mb-2">Game Rules</h3>
              <ul className="text-sm text-gray-300 space-y-1">
                <li>• Roll two dice (1-6 each)</li>
                <li>• Bet if sum will be Over or Under 7</li>
                <li>• Exactly 7 = Push (bet returned)</li>
                <li>• Win pays 1.933x your bet</li>
                <li>• 15/36 ways to win each bet</li>
              </ul>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
};

export { SevenOut };
