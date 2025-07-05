import React, { useState, useEffect, useRef } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useToast } from '../components/ui/use-toast';
import { aptosClient } from '../utils/aptosClient';
import { 
  CASINO_HOUSE_ADDRESS, 
  INVESTOR_TOKEN_ADDRESS,
  CCIT_DECIMALS, 
  NAV_SCALE, 
  APT_DECIMALS 
} from '../constants/chaincasino';

// Coin Image Component
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

// Error and success messages
const ERROR_MESSAGES = {
  WALLET_NOT_CONNECTED: "Please connect your wallet to continue",
  INVALID_AMOUNT: "Please enter a valid amount",
  INSUFFICIENT_BALANCE: "Insufficient balance for this transaction",
  TRANSACTION_FAILED: "Transaction failed. Please try again.",
};

const SUCCESS_MESSAGES = {
  DEPOSIT_SUCCESS: "Deposit completed successfully!",
  REDEEM_SUCCESS: "Withdrawal completed successfully!",
};

// Enhanced Animated Counter Hook
const useCountUp = (end: number, duration: number = 1000, decimals: number = 2) => {
  const [count, setCount] = useState(end);
  const [isAnimating, setIsAnimating] = useState(false);
  const prevEndRef = useRef(end);

  useEffect(() => {
    if (Math.abs(prevEndRef.current - end) > 0.001) {
      setIsAnimating(true);
      const startValue = prevEndRef.current;
      const difference = end - startValue;
      const steps = Math.min(Math.abs(difference) * 10, 60); // More steps for smoother animation
      const increment = difference / steps;
      let currentValue = startValue;
      let stepCount = 0;
      
      const timer = setInterval(() => {
        stepCount++;
        currentValue += increment;
        
        if (stepCount >= steps) {
          currentValue = end;
          setCount(end);
          setIsAnimating(false);
          clearInterval(timer);
        } else {
          setCount(currentValue);
        }
      }, duration / steps);

      prevEndRef.current = end;
      return () => clearInterval(timer);
    }
  }, [end, duration]);

  return { count, isAnimating };
};

// Enhanced Value Change Indicator Component
const ValueChangeIndicator = ({ value, prevValue, children, className = "" }) => {
  const [changeType, setChangeType] = useState<'increase' | 'decrease' | 'none'>('none');
  const [showSparkle, setShowSparkle] = useState(false);
  
  useEffect(() => {
    if (prevValue !== undefined && Math.abs(value - prevValue) > 0.001) {
      if (value > prevValue) {
        setChangeType('increase');
        setShowSparkle(true);
        setTimeout(() => setShowSparkle(false), 1000);
      } else if (value < prevValue) {
        setChangeType('decrease');
      }
      
      const timer = setTimeout(() => setChangeType('none'), 3000);
      return () => clearTimeout(timer);
    }
  }, [value, prevValue]);

  const getChangeClass = () => {
    switch (changeType) {
      case 'increase':
        return 'animate-pulse text-green-400 drop-shadow-[0_0_12px_rgba(34,197,94,0.9)] scale-105';
      case 'decrease':
        return 'animate-pulse text-red-400 drop-shadow-[0_0_12px_rgba(239,68,68,0.9)] scale-95';
      default:
        return 'scale-100';
    }
  };

  return (
    <div className={`transition-all duration-500 ${getChangeClass()} ${className} relative`}>
      {children}
      {showSparkle && (
        <div className="absolute inset-0 pointer-events-none">
          <div className="absolute top-0 right-0 text-yellow-400 animate-ping">✨</div>
          <div className="absolute bottom-0 left-0 text-yellow-400 animate-ping animation-delay-300">✨</div>
        </div>
      )}
    </div>
  );
};

// Enhanced Button Component with more effects
const EnhancedButton = ({ 
  children, 
  onClick, 
  disabled = false, 
  loading = false, 
  variant = 'primary',
  className = '',
  size = 'default',
  ...props 
}) => {
  const [isPressed, setIsPressed] = useState(false);
  const [isHovered, setIsHovered] = useState(false);
  const [ripples, setRipples] = useState([]);

  const handleClick = (e) => {
    if (disabled || loading) return;
    
    // Create ripple effect
    const rect = e.currentTarget.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const x = e.clientX - rect.left - size / 2;
    const y = e.clientY - rect.top - size / 2;
    
    const newRipple = {
      x,
      y,
      size,
      id: Date.now(),
    };
    
    setRipples(prev => [...prev, newRipple]);
    
    // Remove ripple after animation
    setTimeout(() => {
      setRipples(prev => prev.filter(ripple => ripple.id !== newRipple.id));
    }, 800);
    
    onClick?.(e);
  };

  const baseClasses = "relative overflow-hidden retro-button transition-all duration-300 transform select-none";
  const variantClasses = {
    primary: "retro-button",
    secondary: "retro-button-secondary",
    success: "retro-button-success",
    danger: "retro-button-danger"
  };

  const sizeClasses = {
    small: "px-3 py-2 text-xs",
    default: "px-6 py-3 text-sm",
    large: "px-8 py-4 text-base"
  };
  
  const disabledClasses = disabled 
    ? "opacity-50 cursor-not-allowed transform-none" 
    : "hover:scale-105 active:scale-95 cursor-pointer";

  return (
    <button
      className={`${baseClasses} ${variantClasses[variant]} ${sizeClasses[size]} ${disabledClasses} ${className}`}
      onMouseDown={() => setIsPressed(true)}
      onMouseUp={() => setIsPressed(false)}
      onMouseLeave={() => {
        setIsPressed(false);
        setIsHovered(false);
      }}
      onMouseEnter={() => setIsHovered(true)}
      onClick={handleClick}
      disabled={disabled || loading}
      {...props}
    >
      {/* Ripple Effects */}
      {ripples.map((ripple) => (
        <span
          key={ripple.id}
          className="absolute rounded-full bg-white opacity-40 animate-ping"
          style={{
            left: ripple.x,
            top: ripple.y,
            width: ripple.size,
            height: ripple.size,
            animationDuration: '800ms',
          }}
        />
      ))}
      
      {/* Hover Gradient */}
      {isHovered && !disabled && (
        <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent animate-pulse" />
      )}
      
      {/* Button Content */}
      <span className={`relative z-10 transition-all duration-200 ${isPressed ? 'scale-95' : 'scale-100'}`}>
        {loading ? (
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
            <span className="tracking-wider">PROCESSING...</span>
          </div>
        ) : (
          children
        )}
      </span>
    </button>
  );
};

// Enhanced Card Component
const RetroCard = ({ children, className = "", glowOnHover = false }) => {
  const [isHovered, setIsHovered] = useState(false);
  
  return (
    <div 
      className={`retro-card transition-all duration-300 ${glowOnHover ? 'hover:shadow-[0_0_30px_rgba(0,195,255,0.4)]' : ''} ${className}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      style={{
        transform: isHovered && glowOnHover ? 'translateY(-5px)' : 'translateY(0)',
      }}
    >
      {children}
    </div>
  );
};

// Progress Bar Component
const ProgressBar = ({ value, max, label, color = 'primary' }) => {
  const percentage = (value / max) * 100;
  const colorClasses = {
    primary: 'bg-cyan-400',
    success: 'bg-green-400',
    warning: 'bg-yellow-400',
    danger: 'bg-red-400'
  };
  
  return (
    <div className="mb-4">
      <div className="flex justify-between text-sm mb-1">
        <span>{label}</span>
        <span>{percentage.toFixed(1)}%</span>
      </div>
      <div className="w-full bg-gray-700 rounded-full h-2 overflow-hidden">
        <div 
          className={`h-full ${colorClasses[color]} transition-all duration-1000 ease-out`}
          style={{ width: `${Math.min(percentage, 100)}%` }}
        />
      </div>
    </div>
  );
};

// NAV Chart Component
const NAVChart = ({ currentNAV, className = "" }) => {
  const [navHistory, setNavHistory] = useState([]);
  const [maxDataPoints] = useState(20);
  
  useEffect(() => {
    if (currentNAV > 0) {
      setNavHistory(prev => {
        const newHistory = [...prev, {
          value: currentNAV,
          timestamp: Date.now()
        }];
        
        // Keep only last 20 data points
        if (newHistory.length > maxDataPoints) {
          return newHistory.slice(-maxDataPoints);
        }
        return newHistory;
      });
    }
  }, [currentNAV, maxDataPoints]);

  const getChartPath = () => {
    if (navHistory.length < 2) return "";
    
    const width = 300;
    const height = 100;
    const minValue = Math.min(...navHistory.map(h => h.value)) * 0.995;
    const maxValue = Math.max(...navHistory.map(h => h.value)) * 1.005;
    const valueRange = maxValue - minValue;
    
    const points = navHistory.map((point, index) => {
      const x = (index / (navHistory.length - 1)) * width;
      const y = height - ((point.value - minValue) / valueRange) * height;
      return `${x},${y}`;
    });
    
    return `M ${points.join(' L ')}`;
  };

  const isUpTrend = navHistory.length >= 2 && 
    navHistory[navHistory.length - 1].value > navHistory[navHistory.length - 2].value;

  return (
    <div className={`bg-black/40 rounded-lg p-4 border border-cyan-400/30 ${className}`}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-cyan-400 font-bold">NAV LIVE CHART</span>
        <span className={`text-xs ${isUpTrend ? 'text-green-400' : 'text-red-400'}`}>
          {isUpTrend ? '📈 UP' : '📉 DOWN'}
        </span>
      </div>
      
      <div className="relative">
        <svg width="300" height="100" className="w-full">
          {/* Grid lines */}
          <defs>
            <pattern id="grid" width="20" height="10" patternUnits="userSpaceOnUse">
              <path d="M 20 0 L 0 0 0 10" fill="none" stroke="rgba(0,195,255,0.1)" strokeWidth="1"/>
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#grid)" />
          
          {/* NAV line */}
          {navHistory.length >= 2 && (
            <>
              <path
                d={getChartPath()}
                fill="none"
                stroke={isUpTrend ? "#10b981" : "#ef4444"}
                strokeWidth="2"
                className="drop-shadow-[0_0_5px_currentColor]"
              />
              {/* Glow effect */}
              <path
                d={getChartPath()}
                fill="none"
                stroke={isUpTrend ? "#10b981" : "#ef4444"}
                strokeWidth="4"
                opacity="0.3"
                className="animate-pulse"
              />
            </>
          )}
          
          {/* Data points */}
          {navHistory.map((point, index) => {
            const x = (index / (navHistory.length - 1)) * 300;
            const minValue = Math.min(...navHistory.map(h => h.value)) * 0.995;
            const maxValue = Math.max(...navHistory.map(h => h.value)) * 1.005;
            const valueRange = maxValue - minValue;
            const y = 100 - ((point.value - minValue) / valueRange) * 100;
            
            return (
              <circle
                key={index}
                cx={x}
                cy={y}
                r="2"
                fill={isUpTrend ? "#10b981" : "#ef4444"}
                className="animate-pulse"
              />
            );
          })}
        </svg>
        
        {/* Current NAV overlay */}
        <div className="absolute top-2 right-2 bg-black/70 px-2 py-1 rounded text-xs">
          <span className="text-cyan-400">Current: </span>
          <span className="text-white font-bold">${currentNAV.toFixed(4)}</span>
        </div>
      </div>
      
      <div className="flex justify-between text-xs text-gray-400 mt-2">
        <span>📊 {navHistory.length} points</span>
        <span>⏱️ Live tracking</span>
      </div>
    </div>
  );
};

// Performance Indicator Component
const PerformanceIndicator = ({ value, label, trend = 'neutral' }) => {
  const trendIcons = {
    up: '📈',
    down: '📉',
    neutral: '➡️'
  };
  
  const trendColors = {
    up: 'text-green-400',
    down: 'text-red-400',
    neutral: 'text-gray-400'
  };
  
  return (
    <div className="flex items-center gap-2 p-2 bg-black/30 rounded border border-cyan-400/30">
      <span className="text-lg">{trendIcons[trend]}</span>
      <div>
        <div className="text-xs text-gray-400">{label}</div>
        <div className={`text-sm font-bold ${trendColors[trend]}`}>{value}</div>
      </div>
    </div>
  );
};

// Spectacular Insert Coin Button
const InsertCoinButton = ({ onClick, disabled, loading, className = "" }) => {
  const [isGlowing, setIsGlowing] = useState(false);
  
  useEffect(() => {
    const interval = setInterval(() => {
      setIsGlowing(prev => !prev);
    }, 2000);
    return () => clearInterval(interval);
  }, []);

  return (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      className={`
        group relative overflow-hidden
        bg-gradient-to-r from-yellow-400 via-yellow-500 to-yellow-600
        hover:from-yellow-300 hover:via-yellow-400 hover:to-yellow-500
        text-black font-black text-lg
        px-8 py-4 rounded-xl
        border-4 border-yellow-200
        shadow-[0_0_20px_rgba(255,215,0,0.8)]
        hover:shadow-[0_0_30px_rgba(255,215,0,1)]
        transition-all duration-300
        transform hover:scale-110 active:scale-95
        disabled:opacity-50 disabled:cursor-not-allowed
        ${isGlowing ? 'shadow-[0_0_40px_rgba(255,215,0,1)]' : ''}
        ${className}
      `}
      style={{
        textShadow: '2px 2px 4px rgba(0,0,0,0.3)',
        animation: isGlowing ? 'pulse 1s ease-in-out' : 'none'
      }}
    >
      {/* Shine effect */}
      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent -skew-x-12 -translate-x-full group-hover:translate-x-full transition-transform duration-1000" />
      
      {/* Coin rain effect on hover */}
      <div className="absolute inset-0 pointer-events-none">
        {[...Array(6)].map((_, i) => (
          <div
            key={i}
            className="absolute text-yellow-200 opacity-0 group-hover:opacity-100 group-hover:animate-bounce"
            style={{
              left: `${20 + i * 10}%`,
              top: `${10 + (i % 2) * 20}%`,
              animationDelay: `${i * 0.1}s`,
              animationDuration: '2s'
            }}
          >
            💰
          </div>
        ))}
      </div>
      
      {/* Button content */}
      <div className="relative z-10 flex items-center gap-3">
        {loading ? (
          <>
            <div className="w-6 h-6 border-3 border-black border-t-transparent rounded-full animate-spin" />
            <span className="tracking-wider">PROCESSING...</span>
          </>
        ) : (
          <>
            <CoinImage size={24} className="group-hover:animate-spin" />
            <span className="tracking-wider font-black">INSERT COIN</span>
            <div className="text-2xl group-hover:animate-pulse">🎰</div>
          </>
        )}
      </div>
    </button>
  );
};

// Spectacular Cashout Button
const CashoutButton = ({ onClick, disabled, loading, amount, className = "" }) => {
  const [isGlowing, setIsGlowing] = useState(false);
  
  useEffect(() => {
    const interval = setInterval(() => {
      setIsGlowing(prev => !prev);
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  return (
    <button
      onClick={onClick}
      disabled={disabled || amount === 0 || loading}
      className={`
        group relative overflow-hidden
        bg-gradient-to-r from-emerald-500 via-green-500 to-emerald-600
        hover:from-emerald-400 hover:via-green-400 hover:to-emerald-500
        text-white font-black text-lg
        px-8 py-4 rounded-xl
        border-4 border-emerald-200
        shadow-[0_0_20px_rgba(16,185,129,0.8)]
        hover:shadow-[0_0_30px_rgba(16,185,129,1)]
        transition-all duration-300
        transform hover:scale-110 active:scale-95
        disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none
        ${isGlowing && !disabled ? 'shadow-[0_0_40px_rgba(16,185,129,1)]' : ''}
        ${className}
      `}
      style={{
        textShadow: '2px 2px 4px rgba(0,0,0,0.3)',
        animation: isGlowing && !disabled ? 'pulse 1s ease-in-out' : 'none'
      }}
    >
      {/* Money shower effect */}
      <div className="absolute inset-0 pointer-events-none">
        {[...Array(8)].map((_, i) => (
          <div
            key={i}
            className="absolute text-green-200 opacity-0 group-hover:opacity-100 group-hover:animate-bounce"
            style={{
              left: `${10 + i * 12}%`,
              top: `${5 + (i % 3) * 15}%`,
              animationDelay: `${i * 0.15}s`,
              animationDuration: '2.5s'
            }}
          >
            💸
          </div>
        ))}
      </div>
      
      {/* Lightning bolts for excitement */}
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute top-1 right-2 text-yellow-300 opacity-0 group-hover:opacity-100 group-hover:animate-ping">⚡</div>
        <div className="absolute bottom-1 left-2 text-yellow-300 opacity-0 group-hover:opacity-100 group-hover:animate-ping animation-delay-500">⚡</div>
      </div>
      
      {/* Shine effect */}
      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent -skew-x-12 -translate-x-full group-hover:translate-x-full transition-transform duration-1000" />
      
      {/* Button content */}
      <div className="relative z-10 flex items-center gap-3">
        {loading ? (
          <>
            <div className="w-6 h-6 border-3 border-white border-t-transparent rounded-full animate-spin" />
            <span className="tracking-wider">PROCESSING...</span>
          </>
        ) : (
          <>
            <CoinImage size={24} className="group-hover:animate-bounce" />
            <span className="tracking-wider font-black">CASH OUT</span>
            <div className="text-2xl group-hover:animate-pulse">💰</div>
          </>
        )}
      </div>
    </button>
  );
};

// Quick Amount Selector
const QuickAmountSelector = ({ amounts, onSelect, symbol = "APT", disabled = false }) => (
  <div className="grid grid-cols-4 gap-2 mb-4">
    {amounts.map((amount, index) => (
      <button
        key={index}
        onClick={() => onSelect(amount.toString())}
        disabled={disabled}
        className="retro-button-secondary text-xs py-2 px-1 hover:bg-cyan-400/20 transition-colors disabled:opacity-50"
      >
        {amount === 'MAX' ? '💎 MAX' : `💰 ${amount}`}
      </button>
    ))}
  </div>
);

interface PortalData {
  ccitBalance: number;
  nav: number;
  portfolioValue: number;
  centralTreasury: number;
  gameReserves: number;
  totalTreasury: number;
  totalSupply: number;
  aptBalance: number;
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
  
  const [prevData, setPrevData] = useState<PortalData>(data);
  const [depositAmount, setDepositAmount] = useState<string>('');
  const [withdrawAmount, setWithdrawAmount] = useState<string>('');
  const [transactionLoading, setTransactionLoading] = useState(false);
  const [showDepositModal, setShowDepositModal] = useState(false);
  const [showWithdrawModal, setShowWithdrawModal] = useState(false);
  const [dataLoading, setDataLoading] = useState(false);
  const [lastUpdateTime, setLastUpdateTime] = useState(Date.now());
  const [showSuccessAnimation, setShowSuccessAnimation] = useState(false);

  // Animated values
  const portfolioCounter = useCountUp(data.portfolioValue, 1200, 4);
  const navCounter = useCountUp(data.nav, 1000, 4);
  const ccitCounter = useCountUp(data.ccitBalance, 800, 3);
  const aptCounter = useCountUp(data.aptBalance, 800, 4);
  const centralTreasuryCounter = useCountUp(data.centralTreasury, 1400, 4);
  const totalSupplyCounter = useCountUp(data.totalSupply, 1000, 3);

  // ORIGINAL FORMAT FUNCTIONS - PRESERVED
  const formatAPT = (amount: number): string => amount.toFixed(4);
  const formatCCIT = (amount: number): string => amount.toFixed(3);
  const formatPercentage = (value: number): string => `${value.toFixed(2)}%`;

  // ORIGINAL DATA FETCHING LOGIC - PRESERVED
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
        error: 'Failed to fetch portfolio data'
      }));
    }
  };

  const fetchTreasuryData = async () => {
    try {
      // Fetch central treasury balance
      const centralResponse = await aptosClient().view({
        payload: {
          function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::central_treasury_balance`,
          functionArguments: []
        }
      });
      
      // Fetch total treasury balance (separate call)
      const totalTreasuryResponse = await aptosClient().view({
        payload: {
          function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::total_treasury_balance`,
          functionArguments: []
        }
      });
      
      // Fetch total supply
      const supplyResponse = await aptosClient().view({
        payload: {
          function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::total_supply`,
          functionArguments: []
        }
      });
      
      const centralTreasury = Number(centralResponse[0]) / Math.pow(10, APT_DECIMALS);
      const totalTreasury = Number(totalTreasuryResponse[0]) / Math.pow(10, APT_DECIMALS);
      const totalSupply = Number(supplyResponse[0]) / Math.pow(10, CCIT_DECIMALS);
      const gameReserves = totalTreasury - centralTreasury; // Calculate game reserves as difference
      
      setData(prev => ({
        ...prev,
        centralTreasury,
        totalTreasury,
        gameReserves,
        totalSupply,
        loading: false
      }));
      
    } catch (error) {
      console.error('Error fetching treasury data:', error);
      // Fallback to central treasury if total treasury call fails
      try {
        const centralResponse = await aptosClient().view({
          payload: {
            function: `${CASINO_HOUSE_ADDRESS}::CasinoHouse::central_treasury_balance`,
            functionArguments: []
          }
        });
        
        const supplyResponse = await aptosClient().view({
          payload: {
            function: `${INVESTOR_TOKEN_ADDRESS}::InvestorToken::total_supply`,
            functionArguments: []
          }
        });
        
        const centralTreasury = Number(centralResponse[0]) / Math.pow(10, APT_DECIMALS);
        const totalSupply = Number(supplyResponse[0]) / Math.pow(10, CCIT_DECIMALS);
        
        setData(prev => ({
          ...prev,
          centralTreasury,
          totalSupply,
          totalTreasury: centralTreasury * 1.2, // Estimate if total treasury call fails
          gameReserves: centralTreasury * 0.2,
          loading: false,
          error: `Treasury data partially loaded: ${error}`
        }));
      } catch (fallbackError) {
        setData(prev => ({
          ...prev,
          error: `Failed to fetch treasury data: ${fallbackError}`
        }));
      }
    }
  };

  // Fetch all data with better loading states
  const fetchAllData = async () => {
    setDataLoading(true);
    setPrevData(data); // Store previous data for animations
    try {
      await Promise.all([
        fetchPortfolioData(),
        fetchTreasuryData()
      ]);
      setLastUpdateTime(Date.now()); // Update timestamp
    } finally {
      setDataLoading(false);
    }
  };

  // ORIGINAL TRANSACTION HANDLERS - PRESERVED
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

      // Success animation
      setShowSuccessAnimation(true);
      setTimeout(() => setShowSuccessAnimation(false), 3000);

      toast({
        title: "Success! 🎉",
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

      // Success animation
      setShowSuccessAnimation(true);
      setTimeout(() => setShowSuccessAnimation(false), 3000);

      toast({
        title: "Success! 💰",
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

  // ORIGINAL USEEFFECT LOGIC - PRESERVED
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

  // Calculate time since last update
  const timeSinceUpdate = Math.floor((Date.now() - lastUpdateTime) / 1000);
  const navChange = 2.34; // Mock nav change - replace with actual calculation
  const profitLoss = data.portfolioValue - (data.ccitBalance * 1.0); // Assuming initial NAV of 1.0
  const profitLossPercentage = data.ccitBalance > 0 ? (profitLoss / (data.ccitBalance * 1.0)) * 100 : 0;

  if (!connected) {
    return (
      <div className="retro-body min-h-screen flex items-center justify-center">
        <div className="retro-scanlines"></div>
        <div className="retro-pixel-grid"></div>
        <div className="container mx-auto px-4">
          <div className="retro-terminal max-w-md mx-auto animate-pulse">
            <div className="retro-terminal-header">/// WALLET CONNECTION REQUIRED ///</div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">SYSTEM:\&gt;</span>
              <span>Please connect wallet to access investor portal</span>
            </div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">SYSTEM:\&gt;</span>
              <span>Initializing secure connection...</span>
            </div>
            <div className="retro-terminal-line">
              <span className="retro-terminal-prompt">SYSTEM:\&gt;</span>
              <span className="retro-terminal-cursor">█</span>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="retro-body min-h-screen relative">
      <div className="retro-scanlines"></div>
      <div className="retro-pixel-grid"></div>
      
      {/* Success Animation Overlay */}
      {showSuccessAnimation && (
        <div className="fixed inset-0 pointer-events-none z-50 flex items-center justify-center">
          <div className="text-6xl animate-bounce">🎉</div>
        </div>
      )}
      
      <div className="container mx-auto px-4 py-8 relative z-10">
        {/* Enhanced Header */}
        <div className="text-center mb-8">
          <h1 className="retro-pixel-font text-4xl md:text-6xl text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-purple-500 to-yellow-400 mb-4 animate-pulse">
            CCIT INVESTOR PORTAL
          </h1>
          <div className="retro-neon-text text-lg mb-4">
            CHAINCASINO INVESTMENT TOKEN
          </div>
          
          {/* Performance Indicators */}
          <div className="flex justify-center gap-4 mb-4 flex-wrap">
            <PerformanceIndicator 
              value={`$${formatAPT(data.portfolioValue)}`}
              label="Portfolio Value"
              trend={profitLoss > 0 ? 'up' : profitLoss < 0 ? 'down' : 'neutral'}
            />
            <PerformanceIndicator 
              value={`${profitLossPercentage >= 0 ? '+' : ''}${profitLossPercentage.toFixed(2)}%`}
              label="P&L"
              trend={profitLoss > 0 ? 'up' : profitLoss < 0 ? 'down' : 'neutral'}
            />
            <PerformanceIndicator 
              value={`+${formatPercentage(navChange)}`}
              label="24h NAV"
              trend="up"
            />
          </div>
          
          <div className="text-sm text-gray-400 flex items-center justify-center gap-2">
            <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
            Last updated: {timeSinceUpdate}s ago
            {dataLoading && <span className="ml-2 retro-loading inline-block"></span>}
          </div>
        </div>

        {/* Main Content Grid */}
        <div className="retro-grid-2 max-w-6xl mx-auto gap-8">
          {/* Portfolio Panel */}
          <RetroCard glowOnHover={true}>
            <div className="retro-pixel-font text-sm text-cyan-300 mb-6 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 bg-cyan-400 animate-pulse rounded-full"></div>
                YOUR PORTFOLIO
              </div>
              <div className="text-xs text-gray-400">
                💎 HODL STRONG
              </div>
            </div>
            
            <ValueChangeIndicator 
              value={portfolioCounter.count} 
              prevValue={prevData.portfolioValue}
              className="retro-display mb-6"
            >
              <div className="retro-display-value text-5xl">
                {dataLoading ? <span className="retro-loading"></span> : `$${formatAPT(portfolioCounter.count)}`}
              </div>
              <div className="retro-display-label">PORTFOLIO VALUE</div>
            </ValueChangeIndicator>

            {/* NAV Chart */}
            <NAVChart currentNAV={navCounter.count} className="mb-6" />

            {/* Progress towards next milestone */}
            <div className="mb-6">
              <div className="flex justify-between text-sm mb-1">
                <span>Progress to next $1K milestone</span>
                <span>{((data.portfolioValue % 1000) / 1000 * 100).toFixed(1)}%</span>
              </div>
              <div className="w-full bg-gray-700 rounded-full h-2 overflow-hidden">
                <div 
                  className="h-full bg-green-400 transition-all duration-1000 ease-out animate-pulse"
                  style={{ width: `${Math.min((data.portfolioValue % 1000) / 1000 * 100, 100)}%` }}
                />
              </div>
            </div>

            <div className="retro-stats mb-6">
              <div className="retro-stat-line">
                <span className="retro-stat-name">CURRENT NAV:</span>
                <ValueChangeIndicator 
                  value={navCounter.count} 
                  prevValue={prevData.nav}
                  className="retro-stat-value"
                >
                  {dataLoading ? <span className="retro-loading"></span> : `$${formatAPT(navCounter.count)}`}
                </ValueChangeIndicator>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">24H CHANGE:</span>
                <span className="retro-stat-value text-green-400 animate-pulse font-bold">
                  +{formatPercentage(navChange)} 📈
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">CCIT BALANCE:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : `${formatCCIT(ccitCounter.count)} CCIT`}
                </span>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">APT BALANCE:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(aptCounter.count)} APT`}
                </span>
              </div>
            </div>
            
            <div className="flex gap-4">
              <InsertCoinButton
                onClick={() => setShowDepositModal(true)}
                disabled={transactionLoading}
                loading={transactionLoading}
                className="flex-1"
              />
              
              <CashoutButton
                onClick={() => setShowWithdrawModal(true)}
                disabled={data.ccitBalance === 0 || transactionLoading}
                loading={transactionLoading}
                amount={data.ccitBalance}
                className="flex-1"
              />
            </div>
          </RetroCard>

          {/* Treasury Panel */}
          <RetroCard glowOnHover={true}>
            <div className="retro-pixel-font text-sm text-cyan-300 mb-6 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 bg-yellow-400 animate-pulse rounded-full"></div>
                CASINO TREASURY
              </div>
              <div className="text-xs text-gray-400">
                🏦 GROWING STRONG
              </div>
            </div>
            
            <div className="retro-pixel-chart mb-6 relative">
              <div className="retro-chart-bar animate-pulse" style={{'--height': '70%', left: '20px'} as React.CSSProperties}></div>
              <div className="retro-chart-bar animate-pulse" style={{'--height': '50%', left: '50px', animationDelay: '0.2s'} as React.CSSProperties}></div>
              <div className="retro-chart-bar animate-pulse" style={{'--height': '85%', left: '80px', animationDelay: '0.4s'} as React.CSSProperties}></div>
              <div className="retro-chart-bar animate-pulse" style={{'--height': '40%', left: '110px', animationDelay: '0.6s'} as React.CSSProperties}></div>
              <div className="retro-chart-bar animate-pulse" style={{'--height': '60%', left: '140px', animationDelay: '0.8s'} as React.CSSProperties}></div>
              <div className="retro-chart-bar animate-pulse" style={{'--height': '75%', left: '170px', animationDelay: '1s'} as React.CSSProperties}></div>
              <div className="absolute top-2 right-2 text-xs text-green-400 animate-pulse">↗ TRENDING UP</div>
            </div>

            <div className="retro-stats">
              <div className="retro-stat-line">
                <span className="retro-stat-name">CENTRAL VAULT:</span>
                <ValueChangeIndicator 
                  value={centralTreasuryCounter.count} 
                  prevValue={prevData.centralTreasury}
                  className="retro-stat-value"
                >
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(centralTreasuryCounter.count)} APT`}
                </ValueChangeIndicator>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">GAME VAULTS:</span>
                <ValueChangeIndicator 
                  value={data.gameReserves} 
                  prevValue={prevData.gameReserves}
                  className="retro-stat-value"
                >
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(data.gameReserves)} APT`}
                </ValueChangeIndicator>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">TOTAL TREASURY:</span>
                <ValueChangeIndicator 
                  value={data.totalTreasury} 
                  prevValue={prevData.totalTreasury}
                  className="retro-stat-value text-yellow-400 font-bold"
                >
                  {dataLoading ? <span className="retro-loading"></span> : `${formatAPT(data.totalTreasury)} APT`}
                </ValueChangeIndicator>
              </div>
              <div className="retro-stat-line">
                <span className="retro-stat-name">TOTAL SUPPLY:</span>
                <span className="retro-stat-value">
                  {dataLoading ? <span className="retro-loading"></span> : `${formatCCIT(totalSupplyCounter.count)} CCIT`}
                </span>
              </div>
            </div>
          </RetroCard>
        </div>

        {/* Enhanced Terminal Status */}
        <div className="retro-terminal max-w-4xl mx-auto mt-8">
          <div className="retro-terminal-header">
            ⚡ SYSTEM STATUS ⚡
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span>NAV: ${formatAPT(navCounter.count)} | SUPPLY: {formatCCIT(totalSupplyCounter.count)} CCIT</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span className="text-green-400">LATEST: NAV APPRECIATION +{formatPercentage(navChange)} → INVESTORS 🚀</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span className="text-green-400">SYSTEM OPERATIONAL - TREASURY GROWS 📈</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span className="text-yellow-400">ACTIVE INVESTORS: {Math.floor(data.totalSupply / 100)} | PROFIT SHARING: ACTIVE ✅</span>
          </div>
          <div className="retro-terminal-line">
            <span className="retro-terminal-prompt">CCIT:\&gt;</span>
            <span className="retro-terminal-cursor">█</span>
          </div>
        </div>

        {/* Enhanced Deposit Modal */}
        {showDepositModal && (
          <div className="fixed inset-0 bg-black bg-opacity-70 flex items-center justify-center z-50 backdrop-blur-sm">
            <div className="retro-card max-w-md w-full mx-4 animate-pulse">
              <h3 className="retro-pixel-font text-xl mb-4 text-center flex items-center justify-center gap-2">
                💰 INSERT COIN 💰
              </h3>
              
              <div className="mb-4">
                <div className="text-sm text-gray-400 mb-2">
                  Available: {formatAPT(data.aptBalance)} APT
                </div>
                <input
                  type="number"
                  value={depositAmount}
                  onChange={(e) => setDepositAmount(e.target.value)}
                  placeholder="Enter APT amount"
                  className="retro-input w-full mb-4 text-lg"
                  step="0.01"
                  min="0"
                  max={data.aptBalance}
                />
                
                <QuickAmountSelector
                  amounts={[10, 50, 100, data.aptBalance]}
                  onSelect={setDepositAmount}
                  symbol="APT"
                  disabled={transactionLoading}
                />

                {depositAmount && (
                  <div className="bg-black/30 p-3 rounded border border-cyan-400/30 text-sm">
                    <div className="flex justify-between">
                      <span>Deposit Amount:</span>
                      <span>{depositAmount} APT</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Est. CCIT Received:</span>
                      <span className="text-green-400">
                        ~{(parseFloat(depositAmount) / data.nav).toFixed(3)} CCIT
                      </span>
                    </div>
                  </div>
                )}
              </div>

              <div className="flex gap-3">
                <EnhancedButton
                  onClick={() => setShowDepositModal(false)}
                  variant="secondary"
                  className="flex-1"
                  disabled={transactionLoading}
                >
                  CANCEL
                </EnhancedButton>
                <EnhancedButton
                  onClick={handleDeposit}
                  loading={transactionLoading}
                  variant="primary"
                  className="flex-1"
                >
                  {transactionLoading ? 'PROCESSING...' : 'DEPOSIT'}
                </EnhancedButton>
              </div>
            </div>
          </div>
        )}

        {/* Enhanced Withdraw Modal */}
        {showWithdrawModal && (
          <div className="fixed inset-0 bg-black bg-opacity-70 flex items-center justify-center z-50 backdrop-blur-sm">
            <div className="retro-card max-w-md w-full mx-4 animate-pulse">
              <h3 className="retro-pixel-font text-xl mb-4 text-center flex items-center justify-center gap-2">
                🎰 CASH OUT 🎰
              </h3>
              
              <div className="mb-4">
                <div className="text-sm text-gray-400 mb-2">
                  Available: {formatCCIT(data.ccitBalance)} CCIT
                </div>
                <input
                  type="number"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  placeholder="Enter CCIT amount"
                  className="retro-input w-full mb-4 text-lg"
                  step="0.01"
                  min="0"
                  max={data.ccitBalance}
                />
                
                <QuickAmountSelector
                  amounts={[100, 500, 1000, data.ccitBalance]}
                  onSelect={setWithdrawAmount}
                  symbol="CCIT"
                  disabled={transactionLoading}
                />

                {withdrawAmount && (
                  <div className="bg-black/30 p-3 rounded border border-green-400/30 text-sm">
                    <div className="flex justify-between">
                      <span>Withdraw Amount:</span>
                      <span>{withdrawAmount} CCIT</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Est. APT Received:</span>
                      <span className="text-green-400">
                        ~{(parseFloat(withdrawAmount) * data.nav * 0.999).toFixed(4)} APT
                      </span>
                    </div>
                    <div className="text-xs text-gray-400 mt-1">
                      *0.1% redemption fee applies
                    </div>
                  </div>
                )}
              </div>

              <div className="flex gap-3">
                <EnhancedButton
                  onClick={() => setShowWithdrawModal(false)}
                  variant="secondary"
                  className="flex-1"
                  disabled={transactionLoading}
                >
                  CANCEL
                </EnhancedButton>
                <EnhancedButton
                  onClick={handleWithdraw}
                  loading={transactionLoading}
                  variant="success"
                  className="flex-1"
                >
                  {transactionLoading ? 'PROCESSING...' : 'WITHDRAW'}
                </EnhancedButton>
              </div>
            </div>
          </div>
        )}

        {/* Enhanced Footer */}
        <footer className="text-center p-8 border-t-4 border-yellow-400 mt-12">
          <div className="flex items-center justify-center gap-4 mb-4">
            <CoinImage size={32} spinning={dataLoading} />
            <div className="retro-pixel-font text-lg text-cyan-400 leading-relaxed">
              🎰 CHAINCASINO.APT × INVESTOR TERMINAL 🎰
            </div>
            <CoinImage size={32} spinning={dataLoading} />
          </div>
          <div className="retro-pixel-font text-sm text-cyan-400 mb-2">
            POWERED BY APTOS MOVE 2 • FUNGIBLE ASSET STANDARD<br />
            EST. 2024 • WHERE DEFI MEETS RETRO GAMING
          </div>
          <div className="text-xs text-gray-400">
            🚀 Building the future of decentralized gaming • 💎 HODL for maximum gains
          </div>
        </footer>
      </div>
    </div>
  );
};

export default InvestorPortal;
