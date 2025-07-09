// frontend/ccit-investor-portal/frontend/constants/chaincasino.ts

export const NETWORK = import.meta.env.VITE_APP_NETWORK ?? "testnet";

// ChainCasino Contract Addresses
export const CASINO_HOUSE_ADDRESS = import.meta.env.VITE_CASINO_HOUSE_ADDRESS;
export const INVESTOR_TOKEN_ADDRESS = import.meta.env.VITE_INVESTOR_TOKEN_ADDRESS;
export const GAMES_ADDRESS = import.meta.env.VITE_GAMES_ADDRESS;

// Legacy FA template constants (keep for compatibility)
export const MODULE_ADDRESS = import.meta.env.VITE_MODULE_ADDRESS;
export const CREATOR_ADDRESS = import.meta.env.VITE_FA_CREATOR_ADDRESS;
export const FA_ADDRESS = import.meta.env.VITE_FA_ADDRESS;

// Environment flags
export const IS_DEV = Boolean(import.meta.env.DEV);
export const IS_PROD = Boolean(import.meta.env.PROD);
export const APTOS_API_KEY = import.meta.env.VITE_APTOS_API_KEY;

// ChainCasino Specific Constants
export const CCIT_DECIMALS = 8;
export const NAV_SCALE = 1000000; // 10^6 for NAV calculations
export const APT_DECIMALS = 8;

// Game Constants
export const SEVEN_OUT_MIN_BET = 50000000; // 0.5 APT (50M octas)
export const SEVEN_OUT_MAX_BET = 4000000000; // 40 APT (4B octas)

// UI Constants
export const REFRESH_INTERVAL = 1000; // 10 seconds
export const ANIMATION_DURATION = 300; // 300ms

// Retro Arcade Theme
export const RETRO_COLORS = {
  neon: {
    primary: '#00c3ff',    // Bright cyan
    secondary: '#b76aff',  // Purple
    accent: '#ffcb05',     // Gold
    success: '#00ff41',    // Matrix green
    danger: '#ff0040',     // Red
    warning: '#ff8c00',    // Orange
  },
  background: {
    primary: '#0d0a1f',    // Dark purple
    secondary: '#1a1433',  // Medium purple
    card: '#281c4d',       // Light purple
    terminal: '#000000',   // Pure black
  },
  text: {
    primary: '#00c3ff',    // Cyan
    secondary: '#b76aff',  // Purple
    accent: '#ffcb05',     // Gold
    muted: '#666688',      // Muted purple
  }
};

// Retro Typography
export const RETRO_FONTS = {
  pixel: '"Press Start 2P", monospace',
  terminal: '"VT323", monospace',
  code: '"Courier New", monospace',
};

// Animation Classes
export const RETRO_ANIMATIONS = {
  neonGlow: 'animate-pulse drop-shadow-[0_0_15px_theme(colors.cyan.400)]',
  pixelFlicker: 'animate-pulse',
  terminalBlink: 'animate-blink',
  scanlines: 'bg-gradient-to-b from-transparent via-cyan-400/5 to-transparent',
};

// Sound Effects (URLs for retro sounds)
export const RETRO_SOUNDS = {
  buttonClick: '/sounds/button-click.mp3',
  coinInsert: '/sounds/coin-insert.mp3',
  jackpot: '/sounds/jackpot.mp3',
  error: '/sounds/error.mp3',
  success: '/sounds/success.mp3',
};

// Game Metadata
export const GAME_METADATA = {
  sevenOut: {
    name: 'SevenOut',
    icon: '🎲',
    description: 'Roll two dice and bet Over or Under 7',
    houseEdge: 278, // 2.78% in basis points
    payoutMultiplier: 2,
    minBet: SEVEN_OUT_MIN_BET,
    maxBet: SEVEN_OUT_MAX_BET,
  },
  // Future games can be added here
  slots: {
    name: 'Slots',
    icon: '🎰',
    description: 'Classic 3-reel slot machine',
    houseEdge: 1550, // 15.50% in basis points
    payoutMultiplier: 100,
    minBet: 10000000, // 0.1 APT
    maxBet: 1000000000, // 10 APT
  },
  roulette: {
    name: 'Roulette',
    icon: '🎯',
    description: 'European roulette wheel',
    houseEdge: 270, // 2.70% in basis points
    payoutMultiplier: 36,
    minBet: 10000000, // 0.1 APT
    maxBet: 500000000, // 5 APT
  },
};

// Utility Functions
export const formatAPT = (amount: number): string => {
  return (amount / 100000000).toFixed(2);
};

export const formatCCIT = (amount: number): string => {
  return (amount / 100000000).toFixed(3);
};

export const formatNAV = (nav: number): string => {
  return (nav / NAV_SCALE).toFixed(4);
};

export const formatPercentage = (value: number, decimals: number = 2): string => {
  return `${value.toFixed(decimals)}%`;
};

// Contract Function Names
export const CASINO_FUNCTIONS = {
  // CasinoHouse functions
  treasuryBalance: 'treasury_balance',
  gameTreasuryBalance: 'game_treasury_balance',
  centralTreasuryBalance: 'central_treasury_balance',
  
  // InvestorToken functions
  nav: 'nav',
  totalSupply: 'total_supply',
  userBalance: 'user_balance',
  depositAndMint: 'deposit_and_mint',
  redeem: 'redeem',
  
  // SevenOut functions
  playSevenOut: 'play_seven_out',
  getGameResult: 'get_game_result',
  hasGameResult: 'has_game_result',
  clearGameResult: 'clear_game_result',
  getGameConfig: 'get_game_config',
};

// Error Messages
export const ERROR_MESSAGES = {
  WALLET_NOT_CONNECTED: 'Please connect your wallet to continue',
  INSUFFICIENT_BALANCE: 'Insufficient balance for this transaction',
  INVALID_AMOUNT: 'Please enter a valid amount',
  TRANSACTION_FAILED: 'Transaction failed. Please try again.',
  CONTRACT_NOT_FOUND: 'Contract not found. Please check configuration.',
  NETWORK_ERROR: 'Network error. Please check your connection.',
  GAME_NOT_READY: 'Game is not ready. Please try again later.',
  BET_TOO_LOW: `Minimum bet is ${formatAPT(SEVEN_OUT_MIN_BET)} APT`,
  BET_TOO_HIGH: `Maximum bet is ${formatAPT(SEVEN_OUT_MAX_BET)} APT`,
};

// Success Messages
export const SUCCESS_MESSAGES = {
  DEPOSIT_SUCCESS: 'Successfully deposited and minted CCIT tokens!',
  REDEEM_SUCCESS: 'Successfully redeemed CCIT tokens for APT!',
  BET_SUCCESS: 'Bet placed successfully!',
  GAME_WIN: 'Congratulations! You won!',
  GAME_LOSS: 'Better luck next time!',
  GAME_PUSH: 'Push! Your bet has been returned.',
};
