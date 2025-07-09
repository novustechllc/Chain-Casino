import { InputTransactionData } from '@aptos-labs/wallet-adapter-react';
import { CASINO_HOUSE_ADDRESS, INVESTOR_TOKEN_ADDRESS, GAMES_ADDRESS } from '@/constants/chaincasino';

// InvestorToken entry functions
export const depositAndMint = (args: { amount: number }): InputTransactionData => {
  const { amount } = args;
  
  return {
    data: {
      function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::deposit_and_mint`,
      arguments: [amount.toString()],
    },
  };
};

export const redeem = (args: { tokens: number }): InputTransactionData => {
  const { tokens } = args;
  
  return {
    data: {
      function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::redeem`,
      arguments: [tokens.toString()],
    },
  };
};

// SevenOut game entry functions
export const playSevenOut = (args: { 
  betOver: boolean; 
  betAmount: number 
}): InputTransactionData => {
  const { betOver, betAmount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::SevenOut::play_seven_out`,
      typeArguments: [],
      functionArguments: [betOver, betAmount.toString()],
    },
  };
};

export const clearGameResult = (): InputTransactionData => {
  return {
    data: {
      function: `${GAMES_ADDRESS}::SevenOut::clear_game_result`,
      typeArguments: [],
      functionArguments: [],
    },
  };
};

// CasinoHouse view functions (used for queries, not transactions)
export const getViewFunctions = () => ({
  // Treasury functions
  treasuryBalance: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::treasury_balance`,
  centralTreasuryBalance: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::central_treasury_balance`,
  gameTreasuryBalance: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::game_treasury_balance`,
  
  // InvestorToken functions
  nav: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::nav`,
  totalSupply: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::total_supply`,
  userBalance: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::user_balance`,
  treasuryComposition: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::treasury_composition`,
  
  // SevenOut functions
  getGameResult: `${GAMES_ADDRESS}::SevenOut::get_user_game_result`,
  hasGameResult: `${GAMES_ADDRESS}::SevenOut::has_game_result`,
  getGameConfig: `${GAMES_ADDRESS}::SevenOut::get_game_config`,
  getGameOdds: `${GAMES_ADDRESS}::SevenOut::get_game_odds`,
  isReady: `${GAMES_ADDRESS}::SevenOut::is_ready`,
  getSessionInfo: `${GAMES_ADDRESS}::SevenOut::get_session_info`,
  canHandlePayout: `${GAMES_ADDRESS}::SevenOut::can_handle_payout`,
});

// Type definitions for responses
export interface GameResult {
  die1: number;
  die2: number;
  dice_sum: number;
  bet_type: number; // 0 = Under, 1 = Over
  bet_amount: number;
  payout: number;
  timestamp: number;
  session_id: number;
  outcome: number; // 0 = Loss, 1 = Win, 2 = Push
}

export interface GameConfig {
  min_bet: number;
  max_bet: number;
  payout_multiplier: number;
  house_edge_bps: number;
}

export interface GameOdds {
  over_ways: number;
  under_ways: number;
  push_ways: number;
}

export interface TreasuryComposition {
  central_treasury: number;
  game_treasuries: number;
  total_treasury: number;
}

export interface SessionInfo {
  session_id: number;
  timestamp: number;
}

// Helper function to format contract addresses for display
export const formatContractAddress = (address: string): string => {
  return address.slice(0, 6) + '...' + address.slice(-4);
};

// Helper function to convert Move struct to TypeScript interface
export const parseGameResult = (moveResult: any[]): GameResult => {
  return {
    die1: Number(moveResult[0]),
    die2: Number(moveResult[1]),
    dice_sum: Number(moveResult[2]),
    bet_type: Number(moveResult[3]),
    bet_amount: Number(moveResult[4]),
    payout: Number(moveResult[5]),
    timestamp: Number(moveResult[6]),
    session_id: Number(moveResult[7]),
    outcome: Number(moveResult[8]),
  };
};

export const parseGameConfig = (moveResult: any[]): GameConfig => {
  return {
    min_bet: Number(moveResult[0]),
    max_bet: Number(moveResult[1]),
    payout_multiplier: Number(moveResult[2]),
    house_edge_bps: Number(moveResult[3]),
  };
};

export const parseGameOdds = (moveResult: any[]): GameOdds => {
  return {
    over_ways: Number(moveResult[0]),
    under_ways: Number(moveResult[1]),
    push_ways: Number(moveResult[2]),
  };
};

export const parseTreasuryComposition = (moveResult: any[]): TreasuryComposition => {
  return {
    central_treasury: Number(moveResult[0]),
    game_treasuries: Number(moveResult[1]),
    total_treasury: Number(moveResult[2]),
  };
};

export const parseSessionInfo = (moveResult: any[]): SessionInfo => {
  return {
    session_id: Number(moveResult[0]),
    timestamp: Number(moveResult[1]),
  };
};
