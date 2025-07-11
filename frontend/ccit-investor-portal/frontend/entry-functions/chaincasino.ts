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

// AptosFortune game entry functions  
export const playAptosFortune = (args: { 
  betAmount: number 
}): InputTransactionData => {
  const { betAmount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosFortune::spin_reels`,
      typeArguments: [],
      functionArguments: [betAmount.toString()],
    },
  };
};

export const clearFortuneResult = (): InputTransactionData => {
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosFortune::clear_result`,
      typeArguments: [],
      functionArguments: [],
    },
  };
};

// AptosFortune view functions
export const getFortuneViewFunctions = () => ({
  gameConfig: `${GAMES_ADDRESS}::AptosFortune::get_game_config`,
  symbolProbabilities: `${GAMES_ADDRESS}::AptosFortune::get_symbol_probabilities`,
  payoutTable: `${GAMES_ADDRESS}::AptosFortune::get_payout_table`,
  isReady: `${GAMES_ADDRESS}::AptosFortune::is_ready`,
  hasResult: `${GAMES_ADDRESS}::AptosFortune::has_player_result`,
  getResult: `${GAMES_ADDRESS}::AptosFortune::get_player_result`,
  calculatePayout: `${GAMES_ADDRESS}::AptosFortune::calculate_potential_payout`,
});

// Type definitions for AptosFortune
export interface FortuneResult {
  reel1: number;
  reel2: number;
  reel3: number;
  match_type: number;     // 0=no match, 1=consolation, 2=partial, 3=jackpot
  matching_symbol: number;
  payout: number;
  session_id: number;
  bet_amount: number;
}

export interface FortuneConfig {
  min_bet: number;
  max_bet: number;
  house_edge: number;
  max_payout: number;
}

// AptosRoulette entry functions (simplified - single bet only)
export const placeRouletteBet = (args: {
  betFlag: number;
  betValue: number;
  betNumbers: number[];
  amount: number;
}): InputTransactionData => {
  const { betFlag, betValue, betNumbers, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::place_bet`,
      typeArguments: [],
      functionArguments: [
        betFlag,
        betValue,
        betNumbers,
        amount.toString()
      ],
    },
  };
};

// Convenience entry functions for specific bet types
export const betRouletteNumber = (args: {
  number: number;
  amount: number;
}): InputTransactionData => {
  const { number, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::bet_number`,
      typeArguments: [],
      functionArguments: [number, amount.toString()],
    },
  };
};

export const betRouletteRedBlack = (args: {
  isRed: boolean;
  amount: number;
}): InputTransactionData => {
  const { isRed, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::bet_red_black`,
      typeArguments: [],
      functionArguments: [isRed, amount.toString()],
    },
  };
};

export const betRouletteEvenOdd = (args: {
  isEven: boolean;
  amount: number;
}): InputTransactionData => {
  const { isEven, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::bet_even_odd`,
      typeArguments: [],
      functionArguments: [isEven, amount.toString()],
    },
  };
};

export const betRouletteHighLow = (args: {
  isHigh: boolean;
  amount: number;
}): InputTransactionData => {
  const { isHigh, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::bet_high_low`,
      typeArguments: [],
      functionArguments: [isHigh, amount.toString()],
    },
  };
};

export const betRouletteDozen = (args: {
  dozen: number;
  amount: number;
}): InputTransactionData => {
  const { dozen, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::bet_dozen`,
      typeArguments: [],
      functionArguments: [dozen, amount.toString()],
    },
  };
};

export const betRouletteColumn = (args: {
  column: number;
  amount: number;
}): InputTransactionData => {
  const { column, amount } = args;
  
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::bet_column`,
      typeArguments: [],
      functionArguments: [column, amount.toString()],
    },
  };
};

export const clearRouletteResult = (): InputTransactionData => {
  return {
    data: {
      function: `${GAMES_ADDRESS}::AptosRoulette::clear_game_result`,
      typeArguments: [],
      functionArguments: [],
    },
  };
};

// AptosRoulette view functions
export const getRouletteViewFunctions = () => ({
  getLatestResult: `${GAMES_ADDRESS}::AptosRoulette::get_latest_result`,
  gameConfig: `${GAMES_ADDRESS}::AptosRoulette::get_game_config`,
  payoutTable: `${GAMES_ADDRESS}::AptosRoulette::get_payout_table`,
  isReady: `${GAMES_ADDRESS}::AptosRoulette::is_ready`,
  isInitialized: `${GAMES_ADDRESS}::AptosRoulette::is_initialized`,
  isRegistered: `${GAMES_ADDRESS}::AptosRoulette::is_registered`,
});

// Parse roulette result from 11-tuple
export const parseRouletteResult = (data: any[]): RouletteResult => {
  const [winning_number, winning_color, is_even, is_high, dozen, column, total_wagered, total_payout, won, net_result, session_id] = data;
  return {
    winning_number: Number(winning_number),
    winning_color: String(winning_color),
    is_even: Boolean(is_even),
    is_high: Boolean(is_high),
    dozen: Number(dozen),
    column: Number(column),
    total_wagered: Number(total_wagered),
    total_payout: Number(total_payout),
    won: Boolean(won),
    net_result: Boolean(net_result),
    session_id: Number(session_id),
  };
};

// Parse roulette config from 4-tuple  
export const parseRouletteConfig = (data: any[]): RouletteConfig => {
  const [min_bet, max_bet, house_edge_bps, max_payout] = data;
  return {
    min_bet: Number(min_bet),
    max_bet: Number(max_bet),
    house_edge_bps: Number(house_edge_bps),
    max_payout: Number(max_payout),
  };
};

// Parse roulette payout table from 7-tuple
export const parseRoulettePayoutTable = (data: any[]): RoulettePayoutTable => {
  const [single, even_money, dozen_column, split, street, corner, line] = data;
  return {
    single: Number(single),
    even_money: Number(even_money),
    dozen_column: Number(dozen_column),
    split: Number(split),
    street: Number(street),
    corner: Number(corner),
    line: Number(line),
  };
};

// Bet flag constants (matching contract)
export const BET_FLAGS = {
  STRAIGHT_UP: 0,
  SPLIT: 1,
  STREET: 2,
  CORNER: 3,
  RED_BLACK: 4,
  EVEN_ODD: 5,
  HIGH_LOW: 6,
  DOZEN: 7,
  COLUMN: 8,
  LINE: 9,
} as const;

// AptosRoulette interfaces and functions
export interface RouletteResult {
  winning_number: number;
  winning_color: string;
  is_even: boolean;
  is_high: boolean;
  dozen: number;
  column: number;
  total_wagered: number;
  total_payout: number;
  won: boolean;
  net_result: boolean;
  session_id: number;
}

export interface RouletteConfig {
  min_bet: number;
  max_bet: number;
  house_edge_bps: number;
  max_payout: number;
}

export interface RoulettePayoutTable {
  single: number;
  even_money: number;
  dozen_column: number;
  split: number;
  street: number;
  corner: number;
  line: number;
}
