import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AptosWalletAdapterProvider } from '@aptos-labs/wallet-adapter-react';

// Pages
import { GameHub } from './components/games/GameHub';
import { SevenOut } from './components/games/SevenOut';
import { AptosFortune } from './components/games/AptosFortune';
import AptosRoulette from './components/games/AptosRoulette';

// Components
import InvestorPortal from './pages/InvestorPortal';
import { WalletSelector } from './components/WalletSelector';
import { Toaster } from './components/ui/toaster';

// Styles
import './styles/retro-arcade.css';

// Create a client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 3,
      refetchOnWindowFocus: false,
    },
  },
});

// Use empty wallets array for now - the FA template handles wallet detection automatically
const wallets: any[] = [];

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AptosWalletAdapterProvider plugins={wallets} autoConnect={true}>
        <Router>
          <div className="App">
            {/* Fixed wallet selector */}
            <div className="fixed top-4 right-4 z-50">
              <WalletSelector />
            </div>
            
            <Routes>
              {/* Main investor portal */}
              <Route path="/" element={<InvestorPortal />} />
              
              {/* Game Hub */}
              <Route path="/game-hub" element={<GameHub />} />

              {/* SevenOut game route */}
              <Route path="/sevenout" element={<SevenOut />} />

              {/* AptosFortune game route */}
              <Route path="/fortune" element={<AptosFortune />} />

              {/* AptosRoulette game route */}
              <Route path="/roulette" element={<AptosRoulette />} />

              {/* Catch all - redirect to home */}
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
            
            <Toaster />
          </div>
        </Router>
      </AptosWalletAdapterProvider>
    </QueryClientProvider>
  );
}

export default App;
